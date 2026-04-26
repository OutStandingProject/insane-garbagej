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

    Abordagem:
      1. Congela o ped e força heading = 180° (a olhar para Sul, Y-).
         Com heading 180°, a frente do ped aponta para Y- (coords.y diminui).
      2. Câmara colocada DIRETAMENTE À FRENTE do ped:
            camX = coords.x          (mesmo X)
            camY = coords.y - 1.3    (1.3m na frente, direção Y-)
            camZ = coords.z + 0.65   (altura do peito/pescoço)
      3. PointCamAtCoord aponta para o centro do ped (coords.z + 0.60).
      4. FOV 28° = retrato compacto sem distorção.
      5. Aguarda 400ms para o motor renderizar a câmara.
      6. Screenshot via requestScreenshot (dataURL base64).
      7. Restaura heading original e descongela o ped.

    Esta abordagem é determinística — não depende do heading original
    nem de offsets trigonométricos. O ped fica sempre de frente.
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

    -- Congela o ped e força heading = 180° (frente do ped aponta para Y-)
    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, 180.0)

    -- Câmara diretamente à frente do ped (Y- = frente com heading 180°)
    local camX = coords.x
    local camY = coords.y - 1.3
    local camZ = coords.z + 0.65

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, camX, camY, camZ)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.60)
    SetCamFov(cam, 28.0)
    RenderScriptCams(true, false, 0, true, false)

    -- Aguarda render da câmara e posição do ped
    Citizen.Wait(400)

    exports['screenshot-basic']:requestScreenshot(function(data)
        -- Restaura câmara do jogo
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)

        -- Restaura ped
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

    -- Tira foto ID card apenas se ainda não tiver uma nesta sessão
    if not client.currentMugshot or client.currentMugshot == '' then
        Citizen.CreateThread(function()
            takeIDCardScreenshot(function(dataUrl)
                if dataUrl and dataUrl ~= '' then
                    client.currentMugshot = dataUrl
                    client.SendReactMessage('ui:setPlayerMugshot', dataUrl)
                    if client.inLobby and client.lobby and client.lobby.id then
                        TriggerServerEvent(_e('server:syncMugshot'), dataUrl)
                    end
                end
            end)
        end)
    end
end

--- Toggles the player's job duty status and handles related actions.
--- @param pointIndex integer The index of the working point.
--- @param openTablet boolean
local function toggleJobDuty(pointIndex, openTablet)
    local goingOnDuty = not client.onDuty

    if Config.JobUniforms.active then
        local progressLabel = goingOnDuty and 'A vestir uniforme...' or 'A despir uniforme...'
        local completed = playDutyClothingSequence(progressLabel)
        if not completed then return end
    end

    client.onDuty = goingOnDuty

    if Config.JobUniforms.active then
        setJobUniform(client.onDuty)
    end

    client.workingPoint = client.onDuty and pointIndex or nil
    Utils.Notify(locale(client.onDuty and 'on_duty' or 'off_duty'), client.onDuty and 'success' or 'inform')

    if not client.onDuty and client.inLobby then
        Lobby.Leave()
    end

    if client.onDuty and openTablet then
        openMenu()
    end
end

RegisterNetEvent('insane-garbagej:ToggleJobDuty', function(pointIndex)
    local points = Config.JobOptions.startPoints
    if not pointIndex or not points[pointIndex] then
        return Utils.Notify('Working point not found !', 'error')
    end
    toggleJobDuty(pointIndex)
end)

local function removeTabletBlip()
    if tabletBlip and DoesBlipExist(tabletBlip) then
        RemoveBlip(tabletBlip)
        tabletBlip = nil
    end
end

local function refreshTabletBlip()
    removeTabletBlip()
    if not client.onDuty or not client.workingPoint then return end
    local point = Config.JobOptions.startPoints[client.workingPoint]
    local tablet = point and point.interaction and point.interaction.tablet
    if not tablet or not tablet.blip or not tablet.blip.active then return end
    tabletBlip = addBlip(tablet.coords, tablet.blip)
end

--- Creates start points and sets up blips.
local function createStartPoints()
    if startPointsCreated then return end
    local points = Config.JobOptions.startPoints
    if not points then return end

    for index, point in pairs(points) do
        if point.active then
            local interaction = point.interaction
            local duty = interaction and interaction.duty
            if duty and duty.coords and duty.blip and duty.blip.active then
                startPointBlips[index] = addBlip(duty.coords, duty.blip)
            end
        end
    end
    startPointsCreated = true
end

--- Marker interaction thread (duty + tablet zones via tecla E)
local function startInteractionMarkers()
    if markerThreadsStarted then return end
    markerThreadsStarted = true

    CreateThread(function()
        local showingText = false
        local currentText = nil

        while true do
            local waitTime = 1000
            local playerCoords = GetEntityCoords(cache.ped)
            local handledText = false

            for index, point in pairs(Config.JobOptions.startPoints) do
                if point.active and point.interaction then
                    local duty   = point.interaction.duty
                    local tablet = point.interaction.tablet

                    -- Duty zone
                    if duty then
                        local dist = #(playerCoords - duty.coords)
                        if dist <= (duty.marker.drawDist or 10.0) then
                            waitTime = 0
                            DrawMarker(
                                duty.marker.type or 2,
                                duty.coords.x, duty.coords.y, duty.coords.z + 0.2,
                                0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                                duty.marker.scale.x, duty.marker.scale.y, duty.marker.scale.z,
                                duty.marker.color.r, duty.marker.color.g, duty.marker.color.b, duty.marker.color.a,
                                true, true, 2, false, nil, nil, false
                            )

                            if dist <= (duty.marker.interactDist or 1.8) then
                                handledText = true
                                if currentText ~= duty.drawText then
                                    Utils.ShowTextUI(duty.drawText)
                                    currentText = duty.drawText
                                    showingText = true
                                end
                                if IsControlJustPressed(0, 38) then
                                    toggleJobDuty(index, false)
                                    Wait(500)
                                end
                            end
                        end
                    end

                    -- Tablet zone (so quando on duty neste ponto)
                    if tablet then
                        local canUseTablet = client.onDuty and client.workingPoint == index
                        if canUseTablet then
                            local dist = #(playerCoords - tablet.coords)
                            if dist <= (tablet.marker.drawDist or 10.0) then
                                waitTime = 0
                                DrawMarker(
                                    tablet.marker.type or 2,
                                    tablet.coords.x, tablet.coords.y, tablet.coords.z + 0.2,
                                    0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                                    tablet.marker.scale.x, tablet.marker.scale.y, tablet.marker.scale.z,
                                    tablet.marker.color.r, tablet.marker.color.g, tablet.marker.color.b, tablet.marker.color.a,
                                    true, true, 2, false, nil, nil, false
                                )

                                if dist <= (tablet.marker.interactDist or 1.8) then
                                    handledText = true
                                    if currentText ~= tablet.drawText then
                                        Utils.ShowTextUI(tablet.drawText)
                                        currentText = tablet.drawText
                                        showingText = true
                                    end
                                    if IsControlJustPressed(0, 38) then
                                        openMenu()
                                        Wait(500)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if showingText and not handledText then
                Utils.HideTextUI()
                showingText = false
                currentText = nil
            end

            Wait(waitTime)
        end
    end)
end

-- NUI Callbacks
RegisterNUICallback('nui:hideFrame', function(_, cb)
    client.SendReactMessage('ui:setVisible', false)
    SetNuiFocus(false, false)
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

RegisterNUICallback('nui:sendInviteToPlayer', function(targetSource, cb)
    Lobby.Invite(targetSource)
    cb({})
end)

RegisterNUICallback('nui:updateProfilePhoto', function(newPhoto, cb)
    local response = lib.callback.await(_e('server:updateProfilePhoto'), false, newPhoto, client.lobby?.id)
    if response then
        client.SendReactMessage('ui:setProfilePhoto', newPhoto)
    end
    cb({})
end)

RegisterNUICallback('nui:openBundleApp', function(script, cb)
    local key = Config.Bundle[script]
    if key and shared.IsResourceStart(key) then
        client.SendReactMessage('ui:setVisible', false)
        SetNuiFocus(false, false)
        exports[key].OpenApp()
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
        for _, profile in pairs(ranks) do
            rankList[#rankList + 1] = profile
        end
        table.sort(rankList, function(a, b)
            return (tonumber(a.exp) or 0) > (tonumber(b.exp) or 0)
        end)
        client.SendReactMessage('ui:setRanks', rankList)
    end)
end)

-- Commands
if Config.Commands.OpenMenu.active then
    RegisterCommand(Config.Commands.OpenMenu.command, function()
        if not client.onDuty then
            return Utils.Notify(locale('need_to_on_duty'), 'error')
        end
        local point = client.workingPoint and Config.JobOptions.startPoints[client.workingPoint]
        local tabletCoords = point and point.interaction and point.interaction.tablet and point.interaction.tablet.coords
        if not tabletCoords then return end
        local distance = #(GetEntityCoords(cache.ped) - tabletCoords)
        if distance > 2.0 then
            return Utils.Notify(locale('far_from_point'), 'error')
        end
        openMenu()
    end, false)
end

if Config.Commands.LeaveTask.active then
    RegisterCommand(Config.Commands.LeaveTask.command, function()
        if client.inLobby and client.lobby?.isTaskStarted then
            Lobby.Leave()
        else
            Utils.Notify(locale('not_on_task'))
        end
    end, false)
end

RegisterCommand(Config.Commands.AcceptInvite.command, function()
    if not client.inLobby then
        Lobby.AcceptLastInvite()
    end
end, false)

RegisterNetEvent(_e('client:openMenu'), openMenu)

-- Player load/unload
function client.SetupUI()
    if client.uiLoad then return end
    local defaultLocale = GetConvar('ox:locale', 'en')
    local localeData = lib.loadJson(('locales.%s'):format(defaultLocale))
    client.SendReactMessage('ui:setupUI', {
        setLocale = localeData and localeData.ui or {},
        setTasks  = Config.Tasks,
    })
end

function client.onPlayerLoad(isLoggedIn)
    client.load = isLoggedIn
    if isLoggedIn then
        createStartPoints()
        startInteractionMarkers()
        refreshTabletBlip()
    else
        TriggerServerEvent(_e('server:onPlayerLogout'))
        deleteCreatedPeds()
        deleteCreatedObjects()
        deleteTaskVehicle()
        deletePedHands()
        if client.onDuty then
            toggleJobDuty()
        end
    end
end

function client.StartResource()
    if client.IsPlayerLoaded() then
        client.onPlayerLoad(true)
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == shared.resource then
        Citizen.Wait(2000)
        client.StartResource()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == shared.resource then
        client.onPlayerLoad(false)
        Utils.HideTextUI()
    end
end)

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
    lastDumpster.coords   = dumpsterCoord
    lastDumpster.clean    = 0
    lastDumpster.attached = false
    lastDumpster.entity   = nil

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

RegisterNetEvent(_e('client:setPlayerLobby'), function(newLobby)
    Lobby.UpdateData(newLobby)
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

function deleteCreatedPeds()
    for _, ped in pairs(createdPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    createdPeds = {}
    for key, blip in pairs(startPointBlips) do
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
        startPointBlips[key] = nil
    end
    removeTabletBlip()
    startPointsCreated = false
end

function deletePedHands()
    if client.hands.busy then
        ClearPedTasksImmediately(cache.ped)
        if DoesEntityExist(client.hands.held_object) then
            DeleteEntity(client.hands.held_object)
        end
    end
    client.hands = { busy = false, held_object = nil }
end
