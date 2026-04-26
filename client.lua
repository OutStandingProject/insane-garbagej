client = {
    framework = shared.GetFrameworkObject(),
    load = false,
    uiLoad = false,
    --[[ Script Global Vars]]
    onDuty = false,
    workingPoint = nil,
    inLobby = false,
    currentMugshot = nil,
    lobby = {
        id = nil,
        members = {},
        leaderId = nil,
        isTaskStarted = false,
        isTaskFinished = false,
        taskId = nil,
        taskVehicleNetId = nil,
        taskProgress = 0,
        goals = 0,
        lastStepProgress = 0,
    },
    hands = {
        busy = false,
        held_object = nil,
    },
}

require 'modules.bridge.client'

local Utils = require 'modules.utils.client'
local Target = require 'modules.target.client'
local Lobby = require 'modules.lobby.client'

---@type table<number, entityId>
local createdPeds = {}
---@type table<number, {id: number, targetable: boolean}>
local createdObjects = {}
---@type table<number, {id: number, targetable: boolean}>
local taskObjects = {}

local startPointsCreated = false
local startPointBlips = {}
local tabletBlip = nil
local markerThreadsStarted = false

local lastDumpster = {
    blip = nil, coords = nil, clean = 0, attached = false, entity = nil,
}

local _headshotHandle = nil

---Sends message to the ReactUI.
---@param action string
---@param data any
function client.SendReactMessage(action, data)
    SendNUIMessage({ action = action, data = data })
end

--- Gera o headshot (mugshot) nativo do GTA V para o ped local.
---@return string
local function generatePlayerHeadshot()
    local ped = cache.ped
    if not ped or not DoesEntityExist(ped) then return "" end

    if _headshotHandle and _headshotHandle ~= 0 then
        Citizen.InvokeNative(0xD4F7B05C, _headshotHandle)
        _headshotHandle = nil
    end

    local handle = Citizen.InvokeNative(0x4462658788425018, ped)
    if not handle or handle == 0 then return "" end

    local timeout = 0
    while not Citizen.InvokeNative(0x1F3F7683, handle) and timeout < 100 do
        Citizen.Wait(50)
        timeout = timeout + 1
    end

    if Citizen.InvokeNative(0x1F3F7683, handle) then
        local txd = Citizen.InvokeNative(0xDB4CAEDBCE1C2728, handle, Citizen.ResultAsString())
        if txd and txd ~= "" then
            _headshotHandle = handle
            return txd
        end
    end

    Citizen.InvokeNative(0xD4F7B05C, handle)
    return ""
end

--- Liberta o handle do headshot guardado (chamado ao fechar o menu).
local function releaseHeadshotHandle()
    if _headshotHandle and _headshotHandle ~= 0 then
        Citizen.InvokeNative(0xD4F7B05C, _headshotHandle)
        _headshotHandle = nil
        client.currentMugshot = nil
    end
end

--- Calculates the user's level on experience
--- @param experience number Total experience of the user.
--- @return number level
local function getUserLevel(experience)
    for lvl, reqExp in pairs(Config.JobOptions.ranks) do
        if experience < reqExp then return math.max(0, lvl - 1) end
    end
    return 1
end

--- Returns the experience points needed for the next level.
--- @param exp number Current experience points of the user.
--- @return number
local function getNextLevelExp(exp)
    for _, reqExp in pairs(Config.JobOptions.ranks) do
        if exp < reqExp then return reqExp end
    end
    return 1
end

--- Adds a blip on the map for the given target (entity or coordinates).
--- @param target number|table Entity ID or vector3 coordinates.
--- @param blip table Table containing blip properties: sprite, color, scale, title.
--- @param route boolean Whether to set a waypoint for the blip.
--- @return number
local function addBlip(target, blip, route)
    local blipId = type(target) == 'number' and AddBlipForEntity(target) or AddBlipForCoord(vector3(target))
    SetBlipSprite(blipId, blip.sprite)
    SetBlipColour(blipId, blip.color)
    SetBlipScale(blipId, blip.scale)
    SetBlipAsShortRange(blipId, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blip.title)
    EndTextCommandSetBlipName(blipId)
    SetBlipFlashes(blipId, true)
    SetBlipFlashTimer(blipId, 5000)

    if route then SetNewWaypoint(target.x, target.y) end
    return blipId
end

--- Sets the job uniform based on the current framework and state.
--- @param state boolean Whether to apply the job uniform or revert to the original skin.
local function setJobUniform(state)
    local framework = shared.framework

    if state then
        if framework == 'esx' then
            client.framework.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                if skin then
                    local uniform = skin.sex == 0 and Config.JobUniforms.male or Config.JobUniforms.female
                    TriggerEvent('skinchanger:loadClothes', skin, uniform)
                end
            end)
        else
            local xPlayer = client.framework.Functions.GetPlayerData()
            if xPlayer and xPlayer.charinfo then
                local outfitData = xPlayer.charinfo.gender == 1 and Config.JobUniforms.female or Config.JobUniforms.male
                outfitData['hat'].texture = math.random(8)
                TriggerEvent('qb-clothing:client:loadOutfit', { outfitData = outfitData })
            end
        end
    else
        if framework == 'esx' then
            client.framework.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                if skin then TriggerEvent('skinchanger:loadSkin', skin) end
            end)
        elseif framework == 'qb' then
            TriggerServerEvent('rcore_clothing:reloadSkin')
        else
            TriggerEvent('rcore_clothing:reloadSkin', true)
        end
    end
end

local function playDutyClothingSequence(labelText)
    local playerPed = cache.ped
    local animDict = 'clothingshirt'
    local animName = 'try_shirt_positive_d'
    local duration = 3000

    lib.requestAnimDict(animDict)
    FreezeEntityPosition(playerPed, true)
    TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, duration, 49, 0, false, false, false)

    local success = lib.progressBar({
        duration = duration,
        label = labelText or 'A trocar de roupa...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true,
            mouse = false,
        }
    })

    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)
    RemoveAnimDict(animDict)

    if success and labelText == 'A vestir uniforme...' then

        local originalCoords = GetEntityCoords(playerPed)
        local originalHeading = GetEntityHeading(playerPed)

        FreezeEntityPosition(playerPed, true)
        SetEntityVisible(playerPed, false, false)
        DisplayRadar(false)
        DisplayHud(false)

        local camDone = false

        Citizen.CreateThread(function()
            while not camDone do
                DisableAllControlActions(0)
                Citizen.Wait(0)
            end
        end)

        Citizen.CreateThread(function()
            local startTime = GetGameTimer()
            while not camDone do
                local elapsed = (GetGameTimer() - startTime) / 1000.0
                local offsetZ = math.sin(elapsed * 7.5) * 0.2

                DrawMarker(
                    2,
                    -328.0, -1538.83, 32.3 + offsetZ,
                    0.0, 0.0, 0.0,
                    0.0, 180.0, 0.0,
                    0.5, 0.5, 0.5,
                    168, 255, 202, 200,
                    false, true, 2, false, nil, nil, false
                )
                Citizen.Wait(0)
            end
        end)

        DoScreenFadeOut(500)
        Citizen.Wait(500)

        SetEntityCoords(playerPed, -325.39, -1535.83, 31.43, false, false, false, false)
        SetEntityHeading(playerPed, 128.49)
        Citizen.Wait(300)

        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamCoord(cam, -325.09, -1535.78, 33.00)
        SetCamRot(cam, -15.0, 0.0, 128.49)
        SetCamFov(cam, 75.0)
        RenderScriptCams(true, false, 0, true, false)

        DoScreenFadeIn(500)
        Citizen.Wait(500)

        Utils.Notify('Agora que já estás devidamente equipado escolhe uma tarefa.', 'success', 5000)

        Citizen.Wait(3000)

        camDone = true
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)

        DoScreenFadeOut(300)
        Citizen.Wait(300)

        SetEntityCoords(playerPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
        SetEntityHeading(playerPed, originalHeading)
        SetEntityVisible(playerPed, true, false)
        FreezeEntityPosition(playerPed, false)
        DisplayRadar(true)
        DisplayHud(true)

        Citizen.Wait(1000)

        DoScreenFadeIn(500)
    end

    return success
end

--- Creates information markers while a task is in progress.
local function createInformationMarkers()
    Citizen.CreateThread(function()
        while client.lobby?.isTaskStarted do
            local waitTime = 1000

            if client.hands.busy then
                if not client.lobby?.isTaskFinished then
                    local vehicle = NetToVeh(client.lobby.taskVehicleNetId)
                    if DoesEntityExist(vehicle) then
                        waitTime = 0
                        local doorCoords = Utils.GetVehicleDoorPosition(vehicle)
                        DrawMarker(2, doorCoords.x, doorCoords.y, doorCoords.z + 1.5, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.5,
                            0.5, 0.5, 168, 255, 202, 100, true, true, 2, false)
                    end
                else
                    waitTime = 0
                    local coords = Config.JobOptions.startPoints[client.workingPoint].lastStep.bagPlaceCoords
                    DrawMarker(2, coords.x, coords.y, coords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.5, 0.5, 0.5, 168,
                        255, 202, 100, true, true, 2, false)
                end
            elseif not client.lobby.isTaskFinished then
                local dumpsterCoords = lastDumpster.coords and vector3(lastDumpster.coords)
                if dumpsterCoords then
                    if lastDumpster.attached then
                        dumpsterCoords = GetEntityCoords(lastDumpster.entity)
                    end

                    if #(GetEntityCoords(cache.ped) - dumpsterCoords) < 15.0 then
                        waitTime = 0
                        DrawMarker(2, dumpsterCoords.x, dumpsterCoords.y, dumpsterCoords.z + 2.0, 0.0, 0.0, 0.0, 0.0,
                            180.0, 0.0, 0.5, 0.5, 0.5, 168, 255, 202, 100, true, true, 2, false)
                    end
                end
            end

            Citizen.Wait(waitTime)
        end
    end)
end

-- Open menu.
local function openMenu()
    if not client.uiLoad then return end
    if not client.onDuty then
        client.onDuty = true
        client.workingPoint = client.onDuty and 1
    end

    local profile = lib.callback.await(_e('server:getPlayerProfile'), false)
    if not profile then return end

    local exp         = tonumber(profile.exp) or 0
    local nextLvlExp  = getNextLevelExp(exp)
    local level       = getUserLevel(exp)
    local playerSrc   = GetPlayerServerId(PlayerId())

    local mugshotTxd = generatePlayerHeadshot()
    client.currentMugshot = mugshotTxd

    client.SendReactMessage('ui:setUserProfile', {
        source        = playerSrc,
        characterName = profile.characterName,
        exp           = exp,
        nextLevelExp  = nextLvlExp,
        level         = level,
        photo         = profile.photo,
        mugshot       = mugshotTxd,
    })

    if mugshotTxd and mugshotTxd ~= '' then
        client.SendReactMessage('ui:setPlayerMugshot', mugshotTxd)
        if client.inLobby and client.lobby and client.lobby.id then
            TriggerServerEvent(_e('server:syncMugshot'), mugshotTxd)
        end
    end

    client.SendReactMessage('ui:setVisible', true)
end

-- NUI Callbacks
RegisterNUICallback('nui:hideFrame', function(_, cb)
    client.SendReactMessage('ui:setVisible', false)
    SetNuiFocus(false, false)
    releaseHeadshotHandle()
    cb({})
end)

RegisterNUICallback('nui:loadUI', function(_, cb)
    client.uiLoad = true
    cb({})
end)

RegisterNUICallback('nui:onLoadUI', function(_, cb)
    client.uiLoad = true
    cb({})
end)

RegisterNUICallback('nui:startLobbyWithTask', function(taskId, cb)
    if client.inLobby then
        Lobby.StartTask(taskId)
    else
        local profile = lib.callback.await(_e('server:getPlayerProfile'), false)
        if profile then
            local lobbyResp = lib.callback.await(_e('server:StartLobbyTask'), false, nil, taskId, client.workingPoint)
            if lobbyResp and lobbyResp.error then
                Utils.Notify(lobbyResp.error, 'error')
            end
        end
    end
    cb({})
end)

-- Ranks
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Citizen.Wait(2000)
    lib.callback(_e('server:GetRanks'), false, function(ranks)
        if not ranks then return end
        local rankList = {}
        for identifier, profile in pairs(ranks) do
            rankList[#rankList + 1] = profile
        end
        table.sort(rankList, function(a, b)
            return (tonumber(a.exp) or 0) > (tonumber(b.exp) or 0)
        end)
        client.SendReactMessage('ui:setRanks', rankList)
    end)
end)

-- Target interaction to open menu
-- O tablet esta em Config.JobOptions.startPoints[1].interaction.tablet
local tabletCfg = Config.JobOptions.startPoints[1].interaction.tablet
Target.AddBoxZone(
    tabletCfg.coords,
    vec3(1.2, 1.2, 1.2),
    0.0,
    {
        name   = 'garbage_tablet',
        label  = tabletCfg.drawText or 'Abrir painel de trabalho',
        icon   = 'fas fa-tablet-alt',
        onEnter = nil,
        onExit  = nil,
        action  = function()
            if not client.uiLoad then return end
            SetNuiFocus(true, true)
            openMenu()
        end,
        canInteract = function() return true end,
    }
)

-- Task events
RegisterNetEvent(_e('client:onTaskStart'), function(taskData)
    client.lobby.isTaskStarted = true
    client.lobby.taskId = taskData.taskId
    client.lobby.goals = taskData.goals

    local task = Config.Tasks[taskData.taskId]
    if not task then return end

    setJobUniform(true)

    local uniformSuccess = playDutyClothingSequence('A vestir uniforme...')
    if not uniformSuccess then return end

    TriggerServerEvent(_e('server:GiveDumpsterCoordToLobby'), client.lobby.id)
end)

RegisterNetEvent(_e('client:OnNewDumpsterCoordCreated'), function(dumpsterCoord, modelType)
    lastDumpster.coords  = dumpsterCoord
    lastDumpster.clean   = 0
    lastDumpster.attached = false
    lastDumpster.entity  = nil

    local blipData = Config.JobOptions.startPoints[1].interaction.tablet.blip
    if lastDumpster.blip then RemoveBlip(lastDumpster.blip) end
    lastDumpster.blip = addBlip(dumpsterCoord, blipData, true)

    createInformationMarkers()
end)

RegisterNetEvent(_e('client:updateTaskProgress'), function(progress)
    client.lobby.taskProgress = progress
    client.SendReactMessage('ui:setTaskProgress', {
        current = progress,
        goals   = client.lobby.goals,
    })
end)

RegisterNetEvent(_e('client:StartLastStep'), function()
    client.lobby.isTaskFinished = true
    if lastDumpster.blip then
        RemoveBlip(lastDumpster.blip)
        lastDumpster.blip = nil
    end
    Utils.Notify(locale('last_step_started'), 'inform', 7000)
end)

RegisterNetEvent(_e('client:updateLastStepProgress'), function(progress, finished)
    client.lobby.lastStepProgress = progress
    if finished then
        TriggerServerEvent(_e('server:FinishTaskClearLobby'), client.lobby.id)
    end
end)

RegisterNetEvent(_e('client:TaskCompleted'), function()
    client.lobby.isTaskStarted  = false
    client.lobby.isTaskFinished = false
    client.lobby.taskProgress   = 0
    deleteCreatedObjects()
    deleteTaskVehicle()
    deleteBlips()
    setJobUniform(false)
    Utils.Notify(locale('task_completed'), 'success', 7000)
    lib.callback(_e('server:GetRanks'), false, function(ranks)
        if not ranks then return end
        local rankList = {}
        for _, profile in pairs(ranks) do
            rankList[#rankList + 1] = profile
        end
        table.sort(rankList, function(a, b)
            return (tonumber(a.exp) or 0) > (tonumber(b.exp) or 0)
        end)
        client.SendReactMessage('ui:setRanks', rankList)
    end)
end)

RegisterNetEvent(_e('client:OnTaskVehicleCreated'), function(netId)
    client.lobby.taskVehicleNetId = netId
end)

RegisterNetEvent(_e('client:SpawnLastStepBags'), function()
end)

RegisterNetEvent(_e('client:PlayLastStepBagConveyor'), function(src)
end)

function deleteCreatedObjects()
    for _, obj in pairs(taskObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    taskObjects = {}
end

function deleteTaskVehicle()
    if client.lobby and client.lobby.taskVehicleNetId then
        local veh = NetToVeh(client.lobby.taskVehicleNetId)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        client.lobby.taskVehicleNetId = nil
    end
end

function deleteBlips()
    for _, blip in pairs(startPointBlips) do RemoveBlip(blip) end
    startPointBlips = {}
    if tabletBlip then RemoveBlip(tabletBlip) tabletBlip = nil end
    if lastDumpster.blip then RemoveBlip(lastDumpster.blip) lastDumpster.blip = nil end
end
