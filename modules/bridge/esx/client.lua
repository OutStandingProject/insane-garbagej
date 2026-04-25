-- Event triggered when a player is loaded
RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    client.onPlayerLoad(true)
end)

-- Event triggered when a player logs out
RegisterNetEvent('esx:onPlayerLogout', function(xPlayer)
    client.onPlayerLoad(false)
end)

-- Checks if the player is logged in
---@return boolean isLoggedIn
function client.IsPlayerLoaded()
    return client.framework.IsPlayerLoaded()
end

-- [[ Uniform Options ]]
--[[ Male ]]
Config.JobUniforms.male = {
    ['tshirt_1'] = 59,
    ['tshirt_2'] = 0,
    ['torso_1'] = 0,
    ['torso_2'] = 5,
    ['decals_1'] = 0,
    ['decals_2'] = 0,
    ['arms'] = 203,
    ['pants_1'] = 36,
    ['pants_2'] = 0,
    ['shoes_1'] = 12,
    ['shoes_2'] = 0,
    ['chain_1'] = 0,
    ['chain_2'] = 0,
    ['helmet_1'] = 2,
    ['helmet_2'] = 0
}
--[[ Female ]]
Config.JobUniforms.female = {
    ['tshirt_1'] = 36,
    ['tshirt_2'] = 0,
    ['torso_1'] = 0,
    ['torso_2'] = 27,
    ['decals_1'] = 0,
    ['decals_2'] = 0,
    ['arms'] = 72,
    ['pants_1'] = 35,
    ['pants_2'] = 0,
    ['shoes_1'] = 26,
    ['shoes_2'] = 0,
    ['chain_1'] = 0,
    ['chain_2'] = 0,
    ['helmet_1'] = 5,
    ['helmet_2'] = 0
}