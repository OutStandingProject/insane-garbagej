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

---Sends message to the ReactUI.
---@param action string
---@param data any
function client.SendReactMessage(action, data)
    SendNUIMessage({ action = action, data = data })
end

--[[
    takeIDCardScreenshot
    --------------------
    Tira uma foto tipo cartão de cidadão do ped do jogador.
]]
---@param cb fun(url: string)
local function takeIDCardScreenshot(cb)
    if GetResourceState('screenshot-basic') ~= 'started' then
        cb('')
        return
    end

    local ped = cache.ped
    if not ped or not DoesEntityExist(ped) then
        cb('')
        return
    end

    local coords          = GetEntityCoords(ped)
    local originalHeading = GetEntityHeading(ped)

    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, 180.0)

    local camX = coords.x
    local camY = coords.y - 1.3
    local camZ = coords.z + 0.65

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, camX, camY, camZ)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.60)
    SetCamFov(cam, 28.0)
    RenderScriptCams(true, false, 0, true, false)

    Citizen.Wait(400)

    exports['screenshot-basic']:requestScreenshot(function(data)
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
        SetEntityHeading(ped, originalHeading)
        FreezeEntityPosition(ped, false)
        cb(data or '')
    end)
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

    -- Cria lobby solo imediatamente ao abrir o menu (se ainda nao tiver lobby)
    if not client.lobby.id then
        local lobbyResult = lib.callback.await(_e('server:CreateSoloLobby'), false)
        if lobbyResult and lobbyResult.lobbyId then
            client.lobby.id = lobbyResult.lobbyId
            client.lobby.leaderId = GetPlayerServerId(PlayerId())
            client.inLobby = true
        end
    end

    local exp        = tonumber(profile.exp) or 0
    local nextLvlExp = getNextLevelExp(exp)
    local level      = getUserLevel(exp)
    local playerSrc  = GetPlayerServerId(PlayerId())

    local defaultLocale = GetConvar('ox:locale', 'en')
    local localeData    = lib.loadJson(('locales.%s'):format(defaultLocale))

    client.SendReactMessage('ui:openMenu', {
        setLocale = localeData and localeData.ui or {},
        setTasks  = Config.Tasks,
        profile   = {
            source        = playerSrc,
            characterName = profile.characterName,
            exp           = exp,
            nextLevelExp  = nextLvlExp,
            level         = level,
            photo         = profile.photo,
            mugshot       = client.currentMugshot or '',
        },
    })

    SetNuiFocus(true, true)

    if not client.currentMugshot or client.currentMugshot == '' then
        Citizen.CreateThread(function()
            takeIDCardScreenshot(function(dataUrl)
                if dataUrl and dataUrl ~= '' then
                    client.currentMugshot = dataUrl
                    client.SendReactMessage('ui:setPlayerMugshot', dataUrl)
                    Lobby.SyncMugshot()
                end
            end)
        end)
    end
end

-- NUI: abrir menu
RegisterNUICallback('nui:loadUI', function(_, cb)
    client.uiLoad = true
    cb({})
end)

RegisterNUICallback('nui:onLoadUI', function(_, cb)
    client.uiLoad = true
    cb({})
end)

RegisterNUICallback('nui:hideFrame', function(_, cb)
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('nui:registerCallbacks', function(_, cb)
    cb({})
end)

-- NUI: convidar jogador por ID
RegisterNUICallback('nui:invitePlayer', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    if not targetId then
        return cb({ success = false, message = 'ID inválido.' })
    end
    local result = Lobby.Invite(targetId)
    if result then
        cb({ success = true })
    else
        cb({ success = false, message = 'Jogador não disponível.' })
    end
end)

-- NUI: sair da lobby
RegisterNUICallback('nui:leaveLobby', function(_, cb)
    Lobby.Leave()
    cb({})
end)

-- NUI: iniciar tarefa — fecha o NUI imediatamente e inicia a task
RegisterNUICallback('nui:startLobbyWithTask', function(data, cb)
    local taskId
    if type(data) == 'table' then
        taskId = tonumber(data.taskId)
    else
        taskId = tonumber(data)
    end
    -- Fecha o NUI antes de iniciar para libertar o controlo do jogador
    SetNuiFocus(false, false)
    cb({})
    -- Inicia a task
    Lobby.StartTask(taskId)
end)

-- Convite recebido: mostra alerta e aguarda resposta
RegisterNetEvent(_e('client:receiveLobbyInvite'), function(lobbyId, leaderName)
    if not client.onDuty then return end
    Lobby.SetLastInvite(lobbyId)

    local alert = lib.alertDialog({
        header  = '🚛 Convite de Lobby',
        content = (leaderName or 'Um jogador') .. ' convidou-te para a sua lobby. Queres aceitar?',
        centered = true,
        cancel  = true,
        labels  = { confirm = 'Aceitar', cancel = 'Recusar' },
    })

    if alert == 'confirm' then
        Lobby.AcceptLastInvite()
    end
end)
