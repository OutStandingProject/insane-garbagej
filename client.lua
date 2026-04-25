
client = {
    framework = shared.GetFrameworkObject(),
    load = false,
    uiLoad = false,
    --[[ Script Global Vars]]
    onDuty = false,
    workingPoint = nil,
    inLobby = false,
    lobby = {
        id = nil,
        members = {}, --[[@type table<key, {source:number, photo: number, characterName: string, mugshot: string}>]]
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

--- Gera o headshot (mugshot) nativo do GTA V para o ped local.
--- Retorna o txd string que pode ser usado como src na NUI.
---@return string
local function generatePlayerHeadshot()
    local ped = cache.ped
    local handle = RegisterPedHeadshotHandle(ped)
    local timeout = 0
    while not IsPedHeadshotReady(handle) and timeout < 100 do
        Citizen.Wait(50)
        timeout = timeout + 1
    end
    if IsPedHeadshotReady(handle) then
        local txd = GetPedHeadshotTxdString(handle)
        -- Não unregister imediatamente para a NUI conseguir carregar a imagem
        -- O GTA limpa automaticamente quando o resource reinicia
        return txd or ""
    end
    UnregisterPedHeadshot(handle)
    return ""
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

        -- Freeze total e invisível
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
                local offsetZ = math.sin(elapsed * 7.5) * 0.2 -- velocidade 2.5, amplitude 0.3

                DrawMarker(
                    2,
                    -328.0, -1538.83, 32.3 + offsetZ, -- Z animado
                    0.0, 0.0, 0.0,
                    0.0, 180.0, 0.0,
                    0.5, 0.5, 0.5,
                    168, 255, 202, 200,
                    false, true, 2, false, nil, nil, false
                )
                Citizen.Wait(0)
            end
        end)

        -- Blackscreen inicial
        DoScreenFadeOut(500)
        Citizen.Wait(500)

        -- Teleporta e posiciona câmera com ecrã preto
        SetEntityCoords(playerPed, -325.39, -1535.83, 31.43, false, false, false, false)
        SetEntityHeading(playerPed, 128.49)
        Citizen.Wait(300)

        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamCoord(cam, -325.09, -1535.78, 33.00)
        SetCamRot(cam, -15.0, 0.0, 128.49)
        SetCamFov(cam, 75.0)
        RenderScriptCams(true, false, 0, true, false)

        -- Fade in para revelar o local
        DoScreenFadeIn(500)
        Citizen.Wait(500)

        Utils.Notify('Agora que já estás devidamente equipado escolhe uma tarefa.', 'success', 5000)

        Citizen.Wait(3000)

        -- Destrói câmera primeiro
        camDone = true
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)

        -- Blackscreen imediatamente antes do teleporte
        DoScreenFadeOut(300)
        Citizen.Wait(300) -- aguarda ecrã ficar preto

        -- Teleporte acontece com ecrã preto
        SetEntityCoords(playerPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
        SetEntityHeading(playerPed, originalHeading)
        SetEntityVisible(playerPed, true, false)
        FreezeEntityPosition(playerPed, false)
        DisplayRadar(true)
        DisplayHud(true)

        -- Pequena pausa para garantir que o jogo carregou a posição
        Citizen.Wait(1000)

        -- Fade in para revelar o player já no duty
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
    local userProfile = lib.callback.await(_e('server:getPlayerProfile'), false)
    userProfile.source = cache.serverId
    userProfile.level = getUserLevel(userProfile.exp)
    userProfile.nextLevelExp = getNextLevelExp(userProfile.exp)

    -- Gerar headshot nativo do GTA V (mugshot do ped atual)
    Citizen.CreateThread(function()
        local mugshot = generatePlayerHeadshot()
        userProfile.mugshot = mugshot or ""
        client.SendReactMessage('ui:setUserProfile', userProfile)
        -- Envia também separadamente para atualizar só o mugshot caso o perfil já esteja carregado
        client.SendReactMessage('ui:setPlayerMugshot', mugshot or "")
    end)

    client.SendReactMessage('ui:setVisible', true)
    SetNuiFocus(true, true)
    lib.callback(_e('server:GetRanks'), false, function(data)
        if data then
            local function getUserLevel(experience)
                for lvl, requireRep in pairs(Config.JobOptions.ranks) do
                    if experience < requireRep then return math.max(0, lvl - 1) end
                end
                return 1
            end

            local filteredData = {}
            for key, value in pairs(data) do
                if value.exp > 0 then
                    value.level = getUserLevel(value.exp)
                    table.insert(filteredData, value)
                end
            end
            client.SendReactMessage('ui:setRanks', filteredData)
        end
    end)
end

--- Toggles the player's job duty status and handles related actions.
--- @param pointIndex integer The index of the working point.
--- @param openTablet boolean
local function toggleJobDuty(pointIndex, openTablet)
    local goingOnDuty = not client.onDuty

    if Config.JobUniforms.active then
        local progressLabel = goingOnDuty and 'A vestir uniforme...' or 'A despir uniforme...'
        local completed = playDutyClothingSequence(progressLabel)

        if not completed then
            return
        end
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
    if not pointIndex or
        not points[pointIndex]
    then
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

--- Creates start points and employer peds for the job.
local function createStartPoints()
    if startPointsCreated then
        return
    end

    local points = Config.JobOptions.startPoints
    if not points then
        return
    end

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
                    local duty = point.interaction.duty
                    local tablet = point.interaction.tablet

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

--- Creates a task vehicle at a clear spawn location.
--- @param spawnCoords table List of potential spawn coordinates.
--- @param type string The type of the vehicle.
--- @return vehicleNetId, veh
local function createTaskVehicle(spawnCoords, type)
    local function findClearSpawnCoord(coords)
        for _, v in pairs(coords) do
            if not IsAnyVehicleNearPoint(v.x, v.y, v.z, 1.0) then
                return vector4(v.x, v.y, v.z, v.w)
            end
        end
        return nil
    end
    local model, plate = Config.TaskVehicles[type], Config.TaskVehicles.plate
    lib.requestModel(model)
    local spawnPoint = findClearSpawnCoord(spawnCoords)
    if not spawnPoint then return false end

    local veh = CreateVehicle(model, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)
    if not DoesEntityExist(veh) then return false end

    local vehicleNetId = VehToNet(veh)
    SetEntityCoords(veh, spawnPoint.x, spawnPoint.y, spawnPoint.z)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNeedsToBeHotwired(veh, false)
    if plate then
        SetVehicleNumberPlateText(veh, plate)
    end
    SetVehicleFuelLevel(veh, 100.0)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDeformationFixed(veh)
    SetModelAsNoLongerNeeded(model)
    return vehicleNetId, veh
end

--- Sets up the task vehicle and assigns it to the player.
--- @param taskType string
local function SetupTask(taskType)
    if not client.workingPoint then
        return Utils.Notify(locale('start_point_not_found'), 'error')
    end

    if client.lobby?.leaderId == cache.serverId then
        local startPoint = Config.JobOptions.startPoints[client.workingPoint]
        local taskVehicleSpawnCoords = startPoint.taskVehicleSpawnCoords

        local vehNetId, vehEntity = createTaskVehicle(taskVehicleSpawnCoords, taskType)
        if not vehNetId then
            Utils.Notify(locale('no_slot_for_task_veh'), 'error')
            Citizen.Wait(3000)
            return SetupTask(taskType)
        end
        Citizen.Wait(777)
        TriggerServerEvent(_e('server:OnTaskVehicleCreated'), client.lobby?.id, vehNetId)
        TriggerServerEvent(_e('server:GiveDumpsterCoordToLobby'), client.lobby?.id)
    end
end

--- Sets the task information text on the UI.
--- @param text string
local function setTaskInfoText(text)
    client.SendReactMessage('ui:setTaskInfo', text)
end

function deleteTaskVehicle()
    if not client.lobby.taskVehicleNetId or
        not NetworkDoesEntityExistWithNetworkId(client.lobby.taskVehicleNetId) then
        return
    end

    local vehicle = NetToVeh(client.lobby.taskVehicleNetId)

    if DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
    end
end

function deleteCreatedObjects()
    for _, object in pairs(createdObjects) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    for _, object in pairs(taskObjects) do
        if object and DoesEntityExist(object.id) then
            if object.targetable then
                Target.RemoveLocalEntity(object.id)
            end
            DeleteEntity(object.id)
        end
    end

    createdObjects = {}
    taskObjects = {}
end

function deleteTaskObject(entity)
    for key, object in pairs(taskObjects) do
        if object and object.id == entity then
            if DoesEntityExist(object.id) then
                if object.targetable then
                    Target.RemoveLocalEntity(object.id)
                end
                DeleteEntity(object.id)
            end
            taskObjects[key] = false
            return key
        end
    end
    return nil
end

function deleteCreatedPeds()
    for _, ped in pairs(createdPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    createdPeds = {}

    for key, blip in pairs(startPointBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
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
    client.hands = { busy = false, held_object = nil, }
end

function deleteBlips()
    if lastDumpster and lastDumpster.blip and DoesBlipExist(lastDumpster.blip) then
        RemoveBlip(lastDumpster.blip)
        lastDumpster.blip = nil
    end
end

--[[ @ ]]

--- Prepare the frontend and send the data
function client.SetupUI()
    if client.uiLoad then return end
    local defaultLocale = GetConvar('ox:locale', 'en')
    client.SendReactMessage('ui:setupUI', {
        setLocale = lib.loadJson(('locales.%s'):format(defaultLocale)).ui,
        setTasks = Config.Tasks,
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

--- Starts the client resource.
function client.StartResource()
    if client.IsPlayerLoaded() then
        client.onPlayerLoad(true)
    end
end

RegisterNetEvent(_e('client:openMenu'), openMenu)

--[[ Commands ]]

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

--[[ End Commands ]]

--[[ @ ]]

RegisterNUICallback('nui:loadUI', function(_, resultCallback)
    resultCallback(true)
    client.SetupUI()
end)

RegisterNUICallback('nui:onLoadUI', function(_, resultCallback)
    resultCallback(true)
    client.uiLoad = true
end)

RegisterNUICallback('nui:hideFrame', function(_, resultCallback)
    client.SendReactMessage('ui:setVisible', false)
    SetNuiFocus(false, false)
    resultCallback(true)
end)

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

--[[ End @ ]]

---@param script 'delivery'|'towtruck'
---@param resultCallback function
RegisterNUICallback('nui:openBundleApp', function(script, resultCallback)
    local key = Config.Bundle[script]
    if key and shared.IsResourceStart(key) then
        client.SendReactMessage('ui:setVisible', false)
        SetNuiFocus(false, false)
        exports[key].OpenApp()
    end
    resultCallback(true)
end)

---@param photo number
---@param resultCallback function
RegisterNUICallback('nui:updateProfilePhoto', function(newPhoto, resultCallback)
    local response = lib.callback.await(_e('server:updateProfilePhoto'), false, newPhoto, client.lobby?.id)
    if response then
        client.SendReactMessage('ui:setProfilePhoto', newPhoto)
    end
    resultCallback(true)
end)

---@param targetSource number
---@param resultCallback function
RegisterNUICallback('nui:sendInviteToPlayer', function(targetSource, resultCallback)
    Lobby.Invite(targetSource)
    resultCallback(true)
end)

---@param task any
---@param resultCallback function
RegisterNUICallback('nui:startLobbyWithTask', function(taskId, resultCallback)
    if not client.workingPoint then
        return Utils.Notify(locale('need_to_on_duty'), 'error')
    end
    local point = Config.JobOptions.startPoints[ client.workingPoint --[[@as number]] ]
    if not point then return end
    local tabletCoords = point.interaction and point.interaction.tablet and point.interaction.tablet.coords
    if not tabletCoords then return end

    local distance = #(tabletCoords - GetEntityCoords(cache.ped))
    if distance > 15.0 then
        return Utils.Notify(locale('far_from_point'), 'error')
    end
    Lobby.StartTask(taskId)
    resultCallback(true)
end)

RegisterNetEvent(_e('client:setPlayerLobby'), function(newLobby)
    Lobby.UpdateData(newLobby)
end)

RegisterNetEvent(_e('client:onTaskStart'), function(data)
    setTaskInfoText(nil)
    client.lobby.isTaskStarted = true
    client.lobby.taskId = data.taskId
    client.lobby.goals = data.goals
    client.lobby.taskProgress = 0
    client.SendReactMessage('ui:setCurrentLobby', client.lobby)
    --[[ Close UI ]]
    client.SendReactMessage('ui:setVisible', false)
    SetNuiFocus(false, false)
    --[[ End Close UI ]]
    SetupTask(data.taskType)
    createInformationMarkers()
end)

RegisterNetEvent(_e('client:OnTaskVehicleCreated'), function(netId, type)
    local plate = Config.TaskVehicles.plate
    client.lobby.taskVehicleNetId = netId
    Utils.Notify(locale('task_vehicle_created'), 'success')
    local vehicle = NetToVeh(netId)
    if not plate then
        plate = GetVehicleNumberPlateText(vehicle)
    end
    if cache.serverId == client.lobby.leaderId then
        SetPedIntoVehicle(cache.ped, vehicle, -1)
    else
        for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            if GetPedInVehicleSeat(vehicle, seat) == 0 then
                SetPedIntoVehicle(cache.ped, vehicle, seat)
                break
            end
        end
    end

    Utils.GiveVehicleKey(plate, vehicle)
    addBlip(vehicle, {
        active = true,
        scale = 0.65,
        color = 2,
        sprite = 318,
        title = locale('task_vehicle')
    })
    --[[ Debug ]]
    Utils.debug('Vehicle Created|Entity:', vehicle)
end)

RegisterNetEvent(_e('client:updateTaskProgress'), function(newProgress)
    client.lobby.taskProgress = newProgress
    Utils.Notify(locale('task_progress_updated'), 'success')
    client.SendReactMessage('ui:setTaskProgress', newProgress)
end)

RegisterNetEvent(_e('client:DeleteTaskObject'), function(index)
    --[[ Debug ]]
    if index then
        Utils.debug("triggered client:DeleteTaskObject", 'index: ' .. index)
    end
    for key, object in pairs(taskObjects) do
        if key == index and object then
            Utils.debug('object deleted', index, object.id, DoesEntityExist(object.id))
            if DoesEntityExist(object.id) then
                DeleteObject(object.id)
            end
            taskObjects[key] = false
            return
        end
    end
end)

RegisterNetEvent(_e('client:TaskCompleted'), function()
    Utils.Notify(locale('task_completed'), 'success', 2500)
    deleteCreatedObjects()
    deleteBlips()
    lastDumpster = {}
    client.lobby.isTaskStarted = false
    client.lobby.isTaskFinished = false
    client.lobby.taskId = nil
    client.lobby.taskVehicleNetId = nil
    client.lobby.taskProgress = 0
    client.lobby.goals = 0
    client.SendReactMessage('ui:setCurrentLobby', client.lobby)
end)

local function GetDirectionFromRotation(rotation)
    local dm = (math.pi / 180)
    return vector3(-math.sin(dm * rotation.z) * math.abs(math.cos(dm * rotation.x)),
        math.cos(dm * rotation.z) * math.abs(math.cos(dm * rotation.x)), math.sin(dm * rotation.x))
end

local function createTrashModelAndCheckInPedHand()
    if client.hands.busy then return end

    lib.requestModel(Config.Models.bin_bag)
    local objBinBag = CreateObject(Config.Models.bin_bag, 0, 0, 0, true, false, false)
    SetModelAsNoLongerNeeded(Config.Models.bin_bag)

    local boneIndex = GetPedBoneIndex(cache.ped, 57005)
    AttachEntityToEntity(objBinBag, cache.ped, boneIndex, 0.12, 0.0, 0.0, 25.0, 270.0, 180.0, true, true, false, true, 1, true)
    local animDict = 'anim@heists@narcotics@trash'
    lib.requestAnimDict(animDict)
    TaskPlayAnim(cache.ped, animDict, 'walk', 1.0, -1.0, -1, 49, 0, 0, 0, 0)
    RemoveAnimDict(animDict)

    setTaskInfoText(locale('info_binbag_progress'))
    client.hands = { busy = true, held_object = objBinBag }

    Citizen.CreateThread(function()
        local taskVehicle = client.lobby and client.lobby.taskVehicleNetId and NetToVeh(client.lobby.taskVehicleNetId)
        local textUI = false

        if taskVehicle and DoesEntityExist(taskVehicle) then
            local taskVehModel = GetEntityModel(taskVehicle)
            local isModel1 = taskVehModel == joaat(Config.TaskVehicles.model_1)
            SetVehicleDoorOpen(taskVehicle, isModel1 and 4 or 5)

            while client.hands.busy do
                local playerPed, playerPos = cache.ped, GetEntityCoords(cache.ped)
                local targetPos = Utils.GetVehicleDoorPosition(taskVehicle)
                local distFromTarget = #(playerPos - targetPos)
                local nearTarget = distFromTarget <= (isModel1 and 7.5 or 3.0)

                if nearTarget and not textUI then
                    Utils.ShowTextUI('[E] ' .. locale('throw_it'))
                    textUI = true
                elseif not nearTarget and textUI then
                    Utils.HideTextUI()
                    textUI = false
                end

                if nearTarget and IsControlJustPressed(0, 38) then
                    ClearPedTasksImmediately(playerPed)
                    TaskPlayAnim(playerPed, animDict, 'throw_b', 1.0, -1.0, -1, 2, 0, 0, 0, 0)
                    RemoveAnimDict(animDict)
                    Citizen.Wait(500)

                    DetachEntity(client.hands.held_object)
                    local bagBreaked = false
                    local throwPower = isModel1 and 15.0 or 5.0
                    local throwDirection = (targetPos - playerPos) / #(targetPos - playerPos)

                    SetEntityVelocity(client.hands.held_object, throwDirection.x * throwPower,
                    throwDirection.y * throwPower, (throwDirection.z + 0.33) * throwPower)

                    Citizen.Wait(450)
                    DeleteEntity(client.hands.held_object)
                    ClearPedTasksImmediately(playerPed)
                    client.hands = { busy = false, held_object = nil }
                    Utils.HideTextUI()

                    TriggerServerEvent(_e('server:IncProgressGoal'), client.lobby.id,
                    { type = 'bin_bag', bagBreaked = bagBreaked })
                    break
                end

                Citizen.Wait(5)
            end
        end
    end)
end

local function createMovableDumpsterAndCheckInPedHand()
    if client.hands.busy then return end

    lib.requestModel(Config.Models.dumpster)
    local objDumpster = CreateObject(Config.Models.dumpster, 0, 0, 0, true, false, false)
    SetModelAsNoLongerNeeded(Config.Models.dumpster)

    AttachEntityToEntity(objDumpster, cache.ped, -1,
        0.0, 1.05, -1.0,
        0.0, 0.0, 0.0,
        true, true, false, true, 1, true)

    local animDict = 'missfinale_c2ig_11'
    lib.requestAnimDict(animDict)
    TaskPlayAnim(cache.ped, animDict, 'pushcar_offcliff_f', 8.0, -8.0, -1, 49, 0, false, false, false)
    RemoveAnimDict(animDict)

    setTaskInfoText(locale('info_dumpster_progress'))
    client.hands = { busy = true, held_object = objDumpster }

    Citizen.CreateThread(function()
        local taskVehicle = client.lobby and client.lobby.taskVehicleNetId and NetToVeh(client.lobby.taskVehicleNetId)
        local textUI = false
        local createdNetDumpster = nil
        local originalCoords = vector3(lastDumpster.coords)
        local originalHeading = lastDumpster.coords.w

        if taskVehicle and DoesEntityExist(taskVehicle) then
            SetVehicleDoorOpen(taskVehicle, 5)

            while client.hands.busy do
                local playerPed, playerPos = cache.ped, GetEntityCoords(cache.ped)
                local targetPos = Utils.GetVehicleDoorPosition(taskVehicle)
                local nearTarget = #(playerPos - targetPos) <= 3.0

                if nearTarget and not textUI then
                    Utils.ShowTextUI('[E] ' .. locale('put_it_on_vehicle'))
                    textUI = true
                elseif not nearTarget and textUI then
                    Utils.HideTextUI()
                    textUI = false
                end

                if IsControlJustPressed(0, 38) then
                    SetVehicleDoorShut(taskVehicle, 5, true)
                    ClearPedTasksImmediately(playerPed)
                    DetachEntity(client.hands.held_object)
                    createdNetDumpster = client.hands.held_object
                    AttachEntityToEntity(createdNetDumpster, taskVehicle, GetEntityBoneIndexByName(taskVehicle, 'boot'),
                        0.0, -2.75, -1.2, 0.0, 0.0, 180.0, false, true, false, false, true, true)
                    Citizen.Wait(250)
                    SetVehicleDoorOpen(taskVehicle, 5)
                    Citizen.Wait(2000)
                    SetVehicleDoorShut(taskVehicle, 5)
                    Citizen.Wait(250)
                    DetachEntity(createdNetDumpster)
                    client.hands = { busy = false, held_object = nil }
                    Utils.HideTextUI()
                    textUI = false
                    break
                end
                Citizen.Wait(5)
            end

            if DoesEntityExist(createdNetDumpster) then
                setTaskInfoText('Devolve o caixote à posição inicial!')

                while true do
                    local playerPos = GetEntityCoords(cache.ped)
                    local dumpsterPos = GetEntityCoords(createdNetDumpster)
                    local distToDumpster = #(playerPos - dumpsterPos)

                    if distToDumpster <= 3.0 then
                        if not textUI then
                            Utils.ShowTextUI('[E] Pegar no caixote')
                            textUI = true
                        end

                        if IsControlJustPressed(0, 38) then
                            Utils.HideTextUI()
                            textUI = false

                            lib.requestAnimDict(animDict)
                            TaskPlayAnim(cache.ped, animDict, 'pushcar_offcliff_f', 8.0, -8.0, -1, 49, 0, false, false, false)
                            RemoveAnimDict(animDict)

                            AttachEntityToEntity(createdNetDumpster, cache.ped, -1,
                                0.0, 1.05, -1.0,
                                0.0, 0.0, 0.0,
                                true, true, false, true, 1, true)

                            client.hands = { busy = true, held_object = createdNetDumpster }
                            break
                        end
                    elseif textUI then
                        Utils.HideTextUI()
                        textUI = false
                    end

                    Citizen.Wait(5)
                end

                while true do
                    local playerPos = GetEntityCoords(cache.ped)
                    local distToOriginal = #(playerPos - originalCoords)

                    if distToOriginal <= 3.0 then
                        if not textUI then
                            Utils.ShowTextUI('[E] Devolver caixote à posição inicial')
                            textUI = true
                        end

                        if IsControlJustPressed(0, 38) then
                            ClearPedTasksImmediately(cache.ped)
                            DetachEntity(createdNetDumpster)
                            SetEntityCoords(createdNetDumpster, originalCoords.x, originalCoords.y, originalCoords.z)
                            SetEntityHeading(createdNetDumpster, originalHeading)
                            FreezeEntityPosition(createdNetDumpster, false)
                            client.hands = { busy = false, held_object = nil }
                            Utils.HideTextUI()
                            textUI = false

                            TriggerServerEvent(_e('server:IncProgressGoal'), client.lobby.id, { type = 'dumpster' })
                            break
                        end
                    elseif textUI then
                        Utils.HideTextUI()
                        textUI = false
                    end

                    Citizen.Wait(5)
                end
            end

            Citizen.CreateThread(function()
                while true do
                    Citizen.Wait(5000)
                    if not DoesEntityExist(createdNetDumpster) then break end
                    local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(createdNetDumpster))
                    if dist > 80.0 then
                        DeleteEntity(createdNetDumpster)
                        break
                    end
                end
            end)
        end
    end)
end

local function createDumpster(coords, targetable)
    local model = Config.Models.dumpster
    lib.requestModel(model)
    local object = CreateObject(model,
        coords.x, coords.y, coords.z,
        false, false, false)
    if not DoesEntityExist(object) then
        Utils.debug('Failed to create Dumpster. Will try again')
        Citizen.Wait(2000)
        return createDumpster(coords)
    end
    SetEntityCoords(object, coords.xyz)
    SetEntityHeading(object, coords.w)
    SetModelAsNoLongerNeeded(model)
    taskObjects[#taskObjects + 1] = { id = object, targetable = targetable, type = 'dumpster' }
    SetEntityCoords(object, coords.x, coords.y, coords.z)
    FreezeEntityPosition(object, true)
    return object
end

local function createBinBags(dumpster)
    local objects = {}
    local coords = GetEntityCoords(dumpster)
    local heading = GetEntityHeading(dumpster)
    local model = Config.Models.bin_bag

    lib.requestModel(model)

    local minDim, maxDim = GetModelDimensions(GetEntityModel(dumpster))
    local dumpsterDepth = maxDim.x - minDim.x

    local headingRad = math.rad(heading)
    local headingBackRad = math.rad(heading + 180)

    local frontOffset = dumpsterDepth / 2 + 0.3
    local backOffset = dumpsterDepth / 2 + 0.3

    local function createBag(xOffset, yOffset)
        local bag = CreateObject(model, xOffset, yOffset, coords.z, false, false, false)
        SetEntityHeading(bag, heading)
        table.insert(objects, bag)

        local objCoords = GetEntityCoords(bag)
        SetEntityCoords(bag, objCoords.x, objCoords.y, objCoords.z)
        FreezeEntityPosition(bag, true)

        taskObjects[#taskObjects + 1] = { id = bag, targetable = true }
    end

    for i = 1, 2 do
        createBag(coords.x + backOffset * math.cos(headingBackRad),
            coords.y + backOffset * math.sin(headingBackRad))
        backOffset = backOffset + 0.6
    end

    createBag(coords.x + frontOffset * math.cos(headingRad),
        coords.y + frontOffset * math.sin(headingRad))

    SetModelAsNoLongerNeeded(model)

    return objects
end

local function checkVehScoop()
    Citizen.CreateThread(function()
        local taskVehicle = client.lobby and client.lobby.taskVehicleNetId and NetToVeh(client.lobby.taskVehicleNetId)
        if not taskVehicle then return end
        if not DoesEntityExist(taskVehicle) then return end
        SetVehicleDoorShut(taskVehicle, 4)
        local scoopBoneIndex = GetEntityBoneIndexByName(taskVehicle, "scoop")
        local dumpsterCoords = vector3(lastDumpster.coords)
        local textUI = false
        local lastTextUpdate = 0
        local textUpdateInterval = 100
        local attachedDumpster = nil
        local particules = false
        local scoopFull = false

        while client.lobby?.isTaskStarted do
            local wait = 1000
            if cache.vehicle and cache.vehicle == taskVehicle and
                GetPedInVehicleSeat(taskVehicle, -1) == cache.ped
            then
                local scoopCoords = GetWorldPositionOfEntityBone(taskVehicle, scoopBoneIndex)
                local scoopRotation = GetEntityBoneRotation(taskVehicle, scoopBoneIndex)
                local distance = #(dumpsterCoords - scoopCoords)

                if not lastDumpster.attached and not scoopFull then
                    if distance <= 6.0 and scoopRotation.x <= -75.0 then
                        wait = 5
                        if not textUI then
                            Utils.ShowTextUI('[E] ' .. locale('clean_dumpster'))
                            textUI = true
                        end
                        if IsControlJustPressed(0, 38) then
                            setTaskInfoText(locale('clean_dumpster'))
                            SetVehicleDoorOpen(taskVehicle, 4)
                            lastDumpster.attached = true
                            local findIndex = deleteTaskObject(lastDumpster.entity)
                            TriggerServerEvent(_e('server:DeleteTaskObject'), client.lobby.id, findIndex)
                            lib.requestModel(Config.Models.dumpster)
                            attachedDumpster = CreateObject(Config.Models.dumpster, 0, 0, 0, true, false, false)
                            lastDumpster.entity = attachedDumpster
                            SetModelAsNoLongerNeeded(Config.Models.dumpster)
                            AttachEntityToEntity(
                                attachedDumpster,
                                taskVehicle,
                                scoopBoneIndex,
                                0, 1.75, 3.25,
                                82.0, 0.0, 0.0,
                                true, true, false, true, 1, true
                            )
                            lib.requestNamedPtfxAsset('core')
                        end
                    elseif textUI then
                        textUI = false
                        Utils.HideTextUI()
                    end

                elseif lastDumpster.attached and not scoopFull then
                    if GetGameTimer() - lastTextUpdate >= textUpdateInterval then
                        if not textUI then textUI = true end
                        Utils.ShowTextUI(locale('per_dumpster', lastDumpster.clean))
                        lastTextUpdate = GetGameTimer()
                    end

                    if scoopRotation.x > 2.0 then
                        if not particules then
                            UseParticleFxAssetNextCall('core')
                            local effectName = 'veh_exhaust_truck'
                            local coords = Utils.GetVehicleDoorPosition(taskVehicle)
                            particules = StartParticleFxLoopedAtCoord(effectName,
                                coords.x, coords.y, coords.z,
                                0.0, 0.0, 0.0,
                                2.5, false, false, false)

                            Citizen.CreateThread(function()
                                local blocking = true

                                Citizen.CreateThread(function()
                                    while blocking do
                                        DisableControlAction(0, 99, true)
                                        DisableControlAction(0, 100, true)
                                        DisableControlAction(0, 101, true)
                                        DisableControlAction(0, 75, true)
                                        DisableControlAction(0, 76, true)
                                        DisableControlAction(0, 21, true)
                                        DisableControlAction(0, 36, true)
                                        DisableControlAction(0, 60, true)
                                        DisableControlAction(0, 61, true)
                                        DisableControlAction(0, 62, true)
                                        DisableControlAction(0, 110, true)
                                        DisableControlAction(0, 111, true)
                                        DisableControlAction(0, 112, true)
                                        DisableControlAction(0, 126, true)
                                        DisableControlAction(0, 127, true)
                                        DisableControlAction(0, 128, true)
                                        DisableControlAction(0, 131, true)
                                        DisableControlAction(0, 132, true)
                                        DisableControlAction(0, 155, true)
                                        DisableControlAction(0, 209, true)
                                        DisableControlAction(0, 210, true)
                                        DisableControlAction(0, 224, true)
                                        DisableControlAction(0, 239, true)
                                        DisableControlAction(0, 240, true)
                                        DisableControlAction(0, 254, true)
                                        DisableControlAction(0, 258, true)
                                        DisableControlAction(0, 280, true)
                                        DisableControlAction(0, 281, true)
                                        DisableControlAction(0, 326, true)
                                        DisableControlAction(0, 340, true)
                                        DisableControlAction(0, 341, true)
                                        DisableControlAction(0, 343, true)
                                        Citizen.Wait(0)
                                    end
                                end)

                                lib.progressBar({
                                    duration = 5000,
                                    label = locale('clean_dumpster'),
                                    useWhileDead = false,
                                    canCancel = false,
                                    disable = {
                                        move = true,
                                        car = true,
                                        combat = true,
                                        mouse = false,
                                    }
                                })

                                blocking = false
                            end)
                        end

                        wait = 50
                        lastDumpster.clean = math.min(100, lastDumpster.clean + 1)

                        if lastDumpster.clean >= 100 then
                            StopParticleFxLooped(particules, false)
                            RemoveNamedPtfxAsset('core')
                            particules = false
                            scoopFull = true
                            Utils.HideTextUI()
                            textUI = false
                            setTaskInfoText('Volta ao caixote e baixa a scoop para o pousar!')
                        end
                    end

                elseif scoopFull then
                    local distToOriginal = #(dumpsterCoords - scoopCoords)

                    if distToOriginal <= 6.0 and scoopRotation.x <= -75.0 then
                        wait = 5
                        if not textUI then
                            Utils.ShowTextUI('[E] Pousar o caixote')
                            textUI = true
                        end

                        if IsControlJustPressed(0, 38) then
                            DetachEntity(attachedDumpster)
                            SetEntityCoords(attachedDumpster, dumpsterCoords.x, dumpsterCoords.y, dumpsterCoords.z)
                            SetEntityHeading(attachedDumpster, lastDumpster.coords.w)
                            FreezeEntityPosition(attachedDumpster, false)
                            SetVehicleDoorShut(taskVehicle, 4)

                            Utils.HideTextUI()
                            textUI = false
                            scoopFull = false
                            lastDumpster.attached = false

                            TriggerServerEvent(_e('server:IncProgressGoal'), client.lobby.id, { type = 'dumpster' })
                            setTaskInfoText(locale('info_binbag_progress'))

                            Citizen.CreateThread(function()
                                while true do
                                    Citizen.Wait(5000)
                                    if not DoesEntityExist(attachedDumpster) then break end
                                    local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(attachedDumpster))
                                    if dist > 80.0 then
                                        DeleteEntity(attachedDumpster)
                                        break
                                    end
                                end
                            end)

                            break
                        end
                    elseif textUI then
                        textUI = false
                        Utils.HideTextUI()
                    end
                end

            elseif textUI then
                textUI = false
                Utils.HideTextUI()
            end

            Citizen.Wait(wait)
        end

        if textUI then
            Utils.HideTextUI()
        end
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(5000)
                if not DoesEntityExist(attachedDumpster) then break end
                local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(attachedDumpster))
                if dist > 80.0 then
                    DeleteEntity(attachedDumpster)
                    break
                end
            end
        end)
    end)
end

local function ejectAllPlayersFromVehicle()
    local vehicle = cache.vehicle
    if vehicle then
        local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
        for seat = -1, maxSeats - 1 do
            local ped = GetPedInVehicleSeat(vehicle, seat)
            if ped ~= 0 and IsPedAPlayer(ped) then
                TaskLeaveVehicle(ped, vehicle, 0)
            end
        end
    end
end

local function lastStepThread()
    if client.hands.busy then return end

    lib.requestModel(Config.Models.bin_bag)
    local objBinBag = CreateObject(Config.Models.bin_bag, 0, 0, 0, true, false, false)
    SetModelAsNoLongerNeeded(Config.Models.bin_bag)

    local boneIndex = GetPedBoneIndex(cache.ped, 57005)
    AttachEntityToEntity(objBinBag, cache.ped, boneIndex, 0.12, 0.0, 0.0, 25.0, 270.0, 180.0, true, true, false, true, 1, true)

    local animDict = 'anim@heists@narcotics@trash'
    lib.requestAnimDict(animDict)
    TaskPlayAnim(cache.ped, animDict, 'walk', 1.0, -1.0, -1, 49, 0, 0, 0, 0)
    RemoveAnimDict(animDict)

    client.hands = { busy = true, held_object = objBinBag }

    Citizen.CreateThread(function()
        local textUI = false
        local lastStepData = Config.JobOptions.startPoints[client.workingPoint]?.lastStep
        local targetPos = lastStepData and lastStepData.bagPlaceCoords

        if not targetPos then
            client.hands = { busy = false, held_object = nil }
            return
        end

        while client.hands.busy do
            local wait = 500
            local playerPed = cache.ped
            local playerPos = GetEntityCoords(playerPed)
            local distFromTarget = #(playerPos - targetPos)
            local nearTarget = distFromTarget <= 2.0

            if nearTarget and not textUI then
                Utils.ShowTextUI('[E] Colocar saco na passadeira')
                textUI = true
            elseif not nearTarget and textUI then
                Utils.HideTextUI()
                textUI = false
            end

            if nearTarget then
                wait = 5

                if IsControlJustPressed(0, 38) then
                    ClearPedTasksImmediately(playerPed)
                    lib.requestAnimDict(animDict)
                    TaskPlayAnim(playerPed, animDict, 'throw_b', 1.0, -1.0, 1200, 2, 0, 0, 0, 0)

                    Citizen.Wait(500)

                    if DoesEntityExist(client.hands.held_object) then
                        DetachEntity(client.hands.held_object, true, true)
                        DeleteEntity(client.hands.held_object)
                    end

                    ClearPedTasksImmediately(playerPed)
                    client.hands = { busy = false, held_object = nil }
                    Utils.HideTextUI()

                    TriggerServerEvent(_e('server:SyncLastStepBagConveyor'), client.lobby.id)
                    break
                end
            end

            Citizen.Wait(wait)
        end
    end)
end

---@param newDumpsterCoord vector4
---@param taskId number
RegisterNetEvent(_e('client:OnNewDumpsterCoordCreated'), function(newDumpsterCoord, taskType)
    lastDumpster.coords = newDumpsterCoord
    lastDumpster.clean = 0
    lastDumpster.attached = false
    local dumpsterObject = createDumpster(newDumpsterCoord, taskType == 'model_2')
    local binBagObjects = createBinBags(dumpsterObject)
    lastDumpster.entity = dumpsterObject
    Target.AddLocalEntity(binBagObjects, {
        {
            label = locale('pick_up'),
            icon = 'fa-solid fa-recycle',
            distance = 2.0,
            onSelect = function(data)
                if client.hands.busy then return end
                local entity = type(data) == 'table' and data.entity or data
                local findIndex = deleteTaskObject(entity)
                TriggerServerEvent(_e('server:DeleteTaskObject'), client.lobby.id, findIndex)
                createTrashModelAndCheckInPedHand()
            end
        },
    })
    if taskType == 'model_2' then
        Target.AddLocalEntity(dumpsterObject, {
            {
                label = locale('pick_up'),
                icon = 'fa-solid fa-recycle',
                distance = 1.5,
                onSelect = function(data)
                    if client.hands.busy then return end
                    local entity = type(data) == 'table' and data.entity or data
                    local findIndex = deleteTaskObject(entity)
                    TriggerServerEvent(_e('server:DeleteTaskObject'), client.lobby.id, findIndex)
                    createMovableDumpsterAndCheckInPedHand()
                end
            },
        })
    else
        checkVehScoop()
    end
    deleteBlips()
    lastDumpster.blip = addBlip(newDumpsterCoord, {
        scale = 0.7,
        color = 5,
        sprite = 728,
        title = locale('dumpster')
    }, true)
    setTaskInfoText(locale('go_marked_destination'))
end)

RegisterNetEvent(_e('client:StartLastStep'), function()
    client.lobby.lastStepProgress = 0
    local need = Config.JobOptions.startPoints[client.workingPoint].lastStep.count * #client.lobby.members
    setTaskInfoText(locale("destroy_garbage_with_team", client.lobby.lastStepProgress, need))
    deleteBlips()
    if client.hands.busy then
        if DoesEntityExist(client.hands.held_object) then
            DetachEntity(client.hands.held_object)
            DeleteEntity(client.hands.held_object)
            ClearPedTasksImmediately(cache.ped)
        end
        client.hands.busy = false
        client.hands.held_object = nil
    end
    if not client.workingPoint then return end
    local coords = Config.JobOptions.startPoints[client.workingPoint].lastStep.destroyCoords
    SetNewWaypoint(coords.x, coords.y)
    Citizen.CreateThread(function()
        local textUI = false
        local targetCoords = Config.JobOptions.startPoints[client.workingPoint].lastStep.destroyCoords
        while client.lobby.isTaskFinished do
            local wait = 1000
            if cache.vehicle then
                local taskVehicle = NetToVeh(client.lobby.taskVehicleNetId)
                if cache.vehicle == taskVehicle then
                    if GetPedInVehicleSeat(taskVehicle, -1) == cache.ped then
                        local vehCoords = GetEntityCoords(taskVehicle)
                        local distance = #(targetCoords - vehCoords)
                        if distance <= 50.0 then
                            wait = 0
                            DrawMarker(2,
                                targetCoords.x, targetCoords.y, targetCoords.z + .5,
                                0.0, 0.0, 0.0,
                                0.0, 180.0, 0.0,
                                .5, .5, .5,
                                168, 255, 202, 100,
                                true, true, 2, false
                            )
                        end
                        if distance < 15.0 then
                            if not textUI then
                                textUI = true
                                Utils.ShowTextUI('[E]' .. locale('hand_over_vehicle'))
                            end
                            if IsControlJustPressed(0, 38) then
                                SetVehicleDoorOpen(cache.vehicle, 5)
                                ejectAllPlayersFromVehicle()
                                TriggerServerEvent(_e('server:SpawnLobbyLastStepBags'), client.lobby.id)
                                break
                            end
                        elseif textUI then
                            textUI = false
                            Utils.HideTextUI()
                        end
                    elseif textUI then
                        textUI = false
                        Utils.HideTextUI()
                    end
                end
            end
            Citizen.Wait(wait)
        end
        if textUI then
            Utils.HideTextUI()
        end
    end)
end)

RegisterNetEvent(_e('client:SpawnLastStepBags'), function()
    local taskVehicle = NetToVeh(client.lobby.taskVehicleNetId)
    if DoesEntityExist(taskVehicle) then
        local backPos = Utils.GetVehicleBackPosition(taskVehicle)

        local distanceBehind = -1.0
        local sideOffset = 0.6

        local vehicleHeading = GetEntityHeading(taskVehicle)
        local backX = backPos.x - math.sin(math.rad(vehicleHeading)) * distanceBehind
        local backY = backPos.y + math.cos(math.rad(vehicleHeading)) * distanceBehind


        local localBags = {}

        local _count = Config.JobOptions.startPoints[client.workingPoint]?.lastStep?.count or 3

        for i = 1, _count do
            local binBagX = backX + i * sideOffset * math.cos(math.rad(vehicleHeading))
            local binBagY = backY + i * sideOffset * math.sin(math.rad(vehicleHeading))
            local binBagZ = backPos.z

            local binBag = CreateObject(Config.Models.bin_bag, binBagX, binBagY, binBagZ, false, false, false)
            SetEntityInvincible(binBag, true)
            PlaceObjectOnGroundProperly(binBag)
            localBags[#localBags + 1] = binBag
            createdObjects[#createdObjects + 1] = binBag
        end
        Target.AddLocalEntity(localBags, {
            {
                label = locale('pick_up'),
                icon = 'fa-solid fa-recycle',
                distance = 1.5,
                onSelect = function(data)
                    if client.hands.busy then return end
                    local entity = type(data) == 'table' and data.entity or data
                    DeleteEntity(entity)
                    lastStepThread()
                end
            },
        })
    end
end)

RegisterNetEvent(_e('client:PlayLastStepBagConveyor'), function(ownerSource)
    if not client.workingPoint then return end

    local lastStepData = Config.JobOptions.startPoints[client.workingPoint]?.lastStep
    if not lastStepData or not lastStepData.conveyor then return end

    local conveyor = lastStepData.conveyor
    local startCoords = conveyor.startCoords
    local endCoords = conveyor.endCoords
    local speed = conveyor.speed or 1.0

    lib.requestModel(Config.Models.bin_bag)
    local bag = CreateObject(Config.Models.bin_bag, startCoords.x, startCoords.y, startCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(Config.Models.bin_bag)

    if not DoesEntityExist(bag) then return end

    SetEntityInvincible(bag, true)
    FreezeEntityPosition(bag, true)
    SetEntityCollision(bag, false, false)
    SetEntityCoordsNoOffset(bag, startCoords.x, startCoords.y, startCoords.z, true, true, true)

    createdObjects[#createdObjects + 1] = bag

    Citizen.CreateThread(function()
        local currentPos = vector3(startCoords.x, startCoords.y, startCoords.z)
        local finalPos = vector3(endCoords.x, endCoords.y, endCoords.z)

        while DoesEntityExist(bag) do
            local direction = finalPos - currentPos
            local distance = #direction

            if distance <= 0.05 then
                DeleteEntity(bag)

                if cache.serverId == ownerSource then
                    local rewardChance = Config.ThrowBinBag.rewardChance or 25
                    local rewardRoll = math.random(1, 100)

                    if rewardRoll <= rewardChance then
                        TriggerServerEvent(_e('server:GiveRandomSmallBoxItem'))
                    end

                    Citizen.Wait(1000)
                    TriggerServerEvent(_e('server:FinishLastStepBagConveyor'), client.lobby.id)
                end

                break
            end

            local delta = GetFrameTime()
            local step = speed * delta
            local normalized = direction / distance
            local moveStep = math.min(step, distance)

            currentPos = currentPos + (normalized * moveStep)
            SetEntityCoordsNoOffset(bag, currentPos.x, currentPos.y, currentPos.z, true, true, true)

            Citizen.Wait(0)
        end
    end)
end)

RegisterNetEvent(_e('client:updateLastStepProgress'), function(data, finish)
    client.lobby.lastStepProgress = data
    local need = Config.JobOptions.startPoints[client.workingPoint].lastStep.count * #client.lobby.members
    setTaskInfoText(locale("destroy_garbage_with_team", client.lobby.lastStepProgress, need))

    if cache.serverId == client.lobby.leaderId and finish then
        deleteTaskVehicle()
        TriggerServerEvent(_e('server:FinishTaskClearLobby'), client.lobby.id)
    end
end)

RegisterNetEvent(_e('client:LastStepBagFullyProcessed'), function()
    if cache.serverId == client.lobby.leaderId then
        deleteTaskVehicle()
        TriggerServerEvent(_e('server:FinishTaskClearLobby'), client.lobby.id)
    end
end)

RegisterNetEvent('mp-garbage:SignIn', function()
    client.onDuty = not client.onDuty
    Utils.Notify(client.onDuty and 'You are now on duty!' or 'You are now off duty!', client.onDuty and 'success' or 'inform')

    if Config.JobUniforms.active then
        local xPlayer = client.framework.Functions.GetPlayerData()
        if xPlayer and xPlayer.charinfo then
            local outfitData = xPlayer.charinfo.gender == 1 and Config.JobUniforms.female or Config.JobUniforms.male
            outfitData['hat'].texture = math.random(8)
            TriggerEvent('qb-clothing:client:loadOutfit', { outfitData = outfitData })
        end
    end

    client.workingPoint = client.onDuty and 1 or nil

    if not client.onDuty and client.inLobby then
        Lobby.Leave()
    end
end)

RegisterNetEvent('mp-garbage:opentab', function()
    if client.onDuty then
        openMenu()
    else
        TriggerEvent("pyh-tablet:Notify", "Garbage Management", "you need to be on duty!", 'assets/hq.png', 2000)
    end
end)

RegisterNetEvent('mp-garbage:SignOut', function()
    client.onDuty = false
    Utils.Notify('You are now off duty!', 'inform')

    if Config.JobUniforms.active then
        if shared.framework == 'esx' then
            client.framework.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                if skin then TriggerEvent('skinchanger:loadSkin', skin) end
            end)
        else
            TriggerEvent('rcore_clothing:reloadSkin', true)
        end
    end

    client.workingPoint = nil

    if client.inLobby then
        Lobby.Leave()
    end
end)
