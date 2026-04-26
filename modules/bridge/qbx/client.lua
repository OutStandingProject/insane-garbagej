-- Adds a state bag change handler for 'isLoggedIn'
AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, isLoggedIn)
    client.onPlayerLoad(isLoggedIn)
end)

-- Checks if the player is logged in based on local player state
---@return boolean isLoggedIn
function client.IsPlayerLoaded()
    return LocalPlayer.state.isLoggedIn
end

-- [[ Uniform Options ]]
--[[ Male ]]
Config.JobUniforms.male = {
    ['t-shirt'] = { item = 59, texture = 0 },
    ['torso2'] = { item = 56, texture = 0 },
    ['arms'] = { item = 203, texture = 0 },
    ['pants'] = { item = 36, texture = 0 },
    ['shoes'] = { item = 12, texture = 6 },
    ['hat'] = { item = 2, texture = 0 },
}
--[[ Female ]]
Config.JobUniforms.female = {
    ['t-shirt'] = { item = 36, texture = 0 },
    ['torso2'] = { item = 27, texture = 0 },
    ['arms'] = { item = 72, texture = 0 },
    ['pants'] = { item = 35, texture = 0 },
    ['shoes'] = { item = 26, texture = 6 },
    ['hat'] = { item = 5, texture = 0 },
}
-- [[ End Uniform Options ]]
