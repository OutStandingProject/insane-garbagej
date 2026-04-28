local Lobby = {}

local lastLobbyIndx = 0
local Lobbies = {}

local Utils = require 'modules.utils.server'

function Lobby.GetLobbyById(lobbyId)
    return Lobbies[lobbyId] or nil
end

function Lobby.IsPlayerInLobby(lobbyId, source)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end
    for _, member in pairs(lobby.members) do
        if member.source == source then
            return true
        end
    end
    return false
end

function Lobby.IsPlayerFree(source)
    for key, lobby in pairs(Lobbies) do
        for key, member in pairs(lobby.members) do
            if member.source == source then
                return false
            end
        end
    end
    return true
end

function Lobby.UpdateMembers(lobby, exceptSource)
    if not lobby then return false end
    if #lobby.members == 0 then
        return Lobby.Delete(lobby.id)
    end
    for _, member in pairs(lobby.members) do
        if member.source ~= exceptSource then
            TriggerClientEvent(_e('client:updateLobbyMembers'), member.source, lobby.members)
        end
    end
    return true
end

function Lobby.UpdateData(lobby)
    if not lobby then return false end
    if #lobby.members == 0 then
        return Lobby.Delete(lobby.id)
    end
    if not lobby.leaderId then
        lobby.leaderId = lobby.members[1].source
    end
    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:setPlayerLobby'), member.source, lobby)
    end
    return true
end

function Lobby.UpdateMemberPhoto(lobbyId, source, newPhoto)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end

    for _, member in pairs(lobby.members) do
        if member.source == source then
            member.photo = newPhoto
            Lobby.UpdateMembers(lobby)
            return true
        end
    end
    return false
end

-- Atualiza o mugshot (txd string nativo do GTA V) de um membro no lobby
-- e propaga a todos os outros membros via client:updateLobbyMembers.
function Lobby.UpdateMemberMugshot(lobbyId, source, mugshotTxd)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end

    for _, member in pairs(lobby.members) do
        if member.source == source then
            member.mugshot = mugshotTxd
            Lobby.UpdateMembers(lobby)
            return true
        end
    end
    return false
end

function Lobby.LeaveById(lobbyId, source)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end
    for key, member in pairs(lobby.members) do
        if member.source == source then
            table.remove(lobby.members, key)
            if lobby.leaderId == source then
                lobby.leaderId = nil
                return Lobby.UpdateData(lobby)
            end
            return Lobby.UpdateMembers(lobby)
        end
    end
    return false
end

function Lobby.Delete(lobbyId)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end
    Lobbies[lobbyId] = nil
    return true
end

function Lobby.Create(leader)
    lastLobbyIndx = lastLobbyIndx + 1
    local characterName = server.GetPlayerCharacterName(leader)
    Lobbies[lastLobbyIndx] = {
        id = lastLobbyIndx,
        members = {
            [1] = {
                source        = leader,
                photo         = server.GetProfilePhoto(leader),
                characterName = characterName,
                mugshot       = nil,
            }
        },
        leaderId = leader,
        isTaskStarted = false,
        isTaskFinished = false,
        taskId = nil,
        taskVehicleNetId = nil,
        taskProgress = 0,
        goals = 0,
        lastStepProgress = 0,
        wp = nil,
    }
    return Lobbies[lastLobbyIndx]
end

function Lobby.InvitePlayer(lobbyId, source, targetSource)
    if source == targetSource then
        return { error = locale('player_not_available') }
    end
    local xTargetPlayer = server.GetPlayer(targetSource)
    if not xTargetPlayer then
        return { error = locale('player_not_available') }
    end
    if not Lobby.IsPlayerFree(targetSource) then
        return { error = locale('player_not_available') }
    end
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then
        lobby = Lobby.Create(source)
        TriggerClientEvent(_e('client:setPlayerLobby'), source, lobby)
    end
    local leaderName = server.GetPlayerCharacterName(source)
    TriggerClientEvent(_e('client:receiveLobbyInvite'), targetSource, lobby.id, leaderName)
    return {}
end

function Lobby.Join(lobbyId, source)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then
        return { error = locale('lobby_not_found') }
    end
    if #lobby.members == 4 then
        return { error = locale('lobby_is_full') }
    end
    if not Lobby.IsPlayerFree(source) then
        return { error = locale('already_in_lobby') }
    end
    local characterName = server.GetPlayerCharacterName(source)
    lobby.members[#lobby.members + 1] = {
        source        = source,
        photo         = server.GetProfilePhoto(source),
        characterName = characterName,
        mugshot       = nil,
        deduction     = 0,
    }
    TriggerClientEvent(_e('client:setPlayerLobby'), source, lobby)
    Lobby.UpdateMembers(lobby, source)
    return {}
end

local function startLastStep(lobbyId)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    lobby.lastStepProgress = 0
    for key, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:StartLastStep'), member.source)
    end
end

local function SendNextDumpsterToLobby(lobbyId)
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return false end
    if not lobby.isTaskStarted or lobby.isTaskFinished then return false end

    local task = Config.Tasks[lobby.taskId]
    if not task then return false end

    local lastDumpsterCoordKey = lobby.lastDumpsterCoordKey

    local function randomDumpsterCoord()
        local newKey
        local attempts = 0

        repeat
            newKey = math.random(#Config.DumpsterCoords)
            attempts = attempts + 1
        until newKey ~= lastDumpsterCoordKey or attempts >= 5

        lobby.lastDumpsterCoordKey = newKey
        return Config.DumpsterCoords[newKey]
    end

    local newDumpsterCoord = randomDumpsterCoord()

    lobby.currentDumpsterProgress = {
        dumpster = 0,
        bin_bag = 0,
    }

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(
            _e('client:OnNewDumpsterCoordCreated'),
            member.source,
            newDumpsterCoord,
            task.max_client < 3 and 'model_1' or 'model_2'
        )
    end

    return true
end

-- Cria uma lobby solo para o jogador ao iniciar o duty.
-- Se o jogador ja tiver uma lobby ativa, devolve o ID existente sem criar nova.
lib.callback.register(_e('server:CreateSoloLobby'), function(source)
    -- Se ja esta numa lobby, devolve o ID dessa lobby
    for _, lobby in pairs(Lobbies) do
        if Lobby.IsPlayerInLobby(lobby.id, source) then
            return { lobbyId = lobby.id }
        end
    end
    -- Cria lobby nova
    local lobby = Lobby.Create(source)
    return { lobbyId = lobby.id }
end)

lib.callback.register(_e('server:LeaveLobby'), function(source, lobbyId)
    if not lobbyId then return false end
    return Lobby.LeaveById(lobbyId, source)
end)

lib.callback.register(_e('server:InvitePlayerToLobby'), function(source, lobbyId, targetSource)
    return Lobby.InvitePlayer(lobbyId, source, targetSource)
end)

lib.callback.register(_e('server:JoinLobby'), function(source, lobbyId)
    return Lobby.Join(lobbyId, source)
end)

lib.callback.register(_e('server:StartLobbyTask'), function(source, lobbyId, taskId, wp)
    local lobby = Lobby.GetLobbyById(lobbyId)
    local task = Config.Tasks[taskId]
    if not task then
        return { error = locale('error_occ') }
    end
    if not lobby then
        lobby = Lobby.Create(source)
        TriggerClientEvent(_e('client:setPlayerLobby'), source, lobby)
    end
    if lobby.leaderId ~= source then
        return { error = locale('only_leader_can_do') }
    end
    if lobby.isTaskStarted then
        return { error = locale('already_on_task') }
    end
    if task.level > server.GetProfileLevel(source) then
        return { error = locale('task_level_too_high') }
    end
    if #lobby.members > (task.max_client or 0) then
        return { error = locale('mission_too_many_people') }
    end
    lobby.isTaskStarted = true
    lobby.taskId = taskId
    lobby.taskProgress = 0
    lobby.goals = task.goals
    lobby.wp = wp
    for key, member in pairs(lobby.members) do
        member.deduction = 0
        TriggerClientEvent(_e('client:onTaskStart'), member.source, {
            taskId = taskId,
            taskType = task.max_client < 3 and 'model_1' or 'model_2',
            goals = lobby.goals
        })
    end
    return {}
end)

-- Evento: cliente envia o seu mugshot (txd nativo) para o servidor
-- que o guarda no lobby e distribui a todos os membros.
RegisterNetEvent(_e('server:syncMugshot'), function(mugshotTxd)
    local src = source
    -- Procura o lobby do jogador
    for _, lobby in pairs(Lobbies) do
        if Lobby.IsPlayerInLobby(lobby.id, src) then
            Lobby.UpdateMemberMugshot(lobby.id, src, mugshotTxd)
            return
        end
    end
end)

RegisterNetEvent(_e('server:OnTaskVehicleCreated'), function(lobbyId, netId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if lobby.leaderId ~= src then return end

    lobby.taskVehicleNetId = netId
    for key, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:OnTaskVehicleCreated'), member.source, netId)
    end
end)

RegisterNetEvent(_e('server:GiveDumpsterCoordToLobby'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if lobby.leaderId ~= src then return end

    SendNextDumpsterToLobby(lobbyId)
end)

RegisterNetEvent(_e('server:DeleteTaskObject'), function(lobbyId, index)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end

    for key, member in pairs(lobby.members) do
        if member.source ~= src then
            TriggerClientEvent(_e('client:DeleteTaskObject'), member.source, index)
        end
    end

    if src and lobbyId and index then
        Utils.debug("triggered DeleteTaskObject by: " .. src, 'lobby: ' .. lobbyId, 'index: ' .. index)
    end
end)

RegisterNetEvent(_e('server:FinishTaskClearLobby'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if lobby.leaderId ~= src then return end

    local task = Config.Tasks[lobby.taskId]
    if not task then return end
    local exp = task.exp
    local fee = task.fee

    for key, member in pairs(lobby.members) do
        local x = 0
        if member.deduction > 0 then
            x = (fee * .10) * member.deduction
        end
        server.SetProfileExp(member.source, exp)
        server.PlayerAddMoney(member.source, 'bank', fee - x)
        TriggerClientEvent(_e('client:TaskCompleted'), member.source)
    end

    lobby.isTaskStarted = false
    lobby.isTaskFinished = false
    lobby.taskId = nil
    lobby.taskVehicleNetId = nil
    lobby.taskProgress = 0
    lobby.goals = 0
    lobby.lastStepProgress = 0
    lobby.currentDumpsterProgress = nil
    lobby.lastDumpsterCoordKey = nil
end)

RegisterNetEvent(_e('server:IncProgressGoal'), function(lobbyId, data)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskStarted then return end
    if lobby.isTaskFinished then return end

    local task = Config.Tasks[lobby.taskId]
    if not task then return end

    lobby.currentDumpsterProgress = lobby.currentDumpsterProgress or {
        dumpster = 0,
        bin_bag = 0,
    }

    if not data or not data.type then return end
    if data.type ~= 'dumpster' and data.type ~= 'bin_bag' then return end

    lobby.currentDumpsterProgress[data.type] += 1

    if lobby.currentDumpsterProgress.dumpster == 1 and lobby.currentDumpsterProgress.bin_bag == 3 then
        lobby.taskProgress += 1

        for _, member in pairs(lobby.members) do
            if member.source == src then
                member.deduction += 1
            end
            TriggerClientEvent(_e('client:updateTaskProgress'), member.source, lobby.taskProgress)
        end

        Citizen.Wait(100)

        if lobby.taskProgress >= task.goals then
            lobby.isTaskFinished = true
            startLastStep(lobbyId)
            for _, member in pairs(lobby.members) do
                TriggerClientEvent(_e('client:setPlayerLobby'), member.source, lobby)
            end
        else
            SendNextDumpsterToLobby(lobbyId)
        end
    end
end)

RegisterNetEvent(_e('server:IncProgressLastStep'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskFinished then return end

    local need = Config.JobOptions.startPoints[lobby.wp].lastStep.count * #lobby.members
    if lobby.lastStepProgress >= need then return end

    lobby.lastStepProgress += 1
    local state = lobby.lastStepProgress >= need

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:updateLastStepProgress'), member.source, lobby.lastStepProgress, state)
    end
end)

RegisterNetEvent(_e('server:LastStepBagReachedEnd'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskFinished then return end

    if src ~= lobby.leaderId then return end

    local need = Config.JobOptions.startPoints[lobby.wp].lastStep.count * #lobby.members
    if lobby.lastStepProgress >= need then return end

    lobby.lastStepProgress += 1
    local state = lobby.lastStepProgress >= need

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:updateLastStepProgress'), member.source, lobby.lastStepProgress, state)
    end
end)

RegisterNetEvent(_e('server:SyncLastStepBagConveyor'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskFinished then return end

    local need = Config.JobOptions.startPoints[lobby.wp].lastStep.count * #lobby.members
    if lobby.lastStepProgress >= need then return end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:PlayLastStepBagConveyor'), member.source, src)
    end
end)

RegisterNetEvent(_e('server:FinishLastStepBagConveyor'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskFinished then return end

    local need = Config.JobOptions.startPoints[lobby.wp].lastStep.count * #lobby.members
    if lobby.lastStepProgress >= need then return end

    lobby.lastStepProgress += 1
    local state = lobby.lastStepProgress >= need

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:updateLastStepProgress'), member.source, lobby.lastStepProgress, state)
    end
end)

RegisterNetEvent(_e('server:SpawnLobbyLastStepBags'), function(lobbyId)
    local src = source
    local lobby = Lobby.GetLobbyById(lobbyId)
    if not lobby then return end
    if not Lobby.IsPlayerInLobby(lobbyId, src) then return end
    if not lobby.isTaskFinished then return end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e('client:SpawnLastStepBags'), member.source)
    end
end)

return Lobby
