--[[ Load the required file based to the server framework ]]

local success, result = pcall(lib.load, ('modules.bridge.%s.server'):format(shared.framework))

if not success then
    lib.print.error(result)
end

if Config.Tablet.active then
    server.CreateUseableItem(Config.Tablet.itemName, function(source)
        TriggerClientEvent(_e('client:openMenu'), source)
    end)
end
