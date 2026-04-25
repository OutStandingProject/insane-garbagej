local Inventory = {}

function Inventory.GiveItem(source, itemName, count)
    local xPlayer = server.GetPlayer(source)
    if shared.GetFrameworkName() == 'esx' then
        return xPlayer.addInventoryItem(itemName, count)
    elseif shared.GetFrameworkName() == 'qb' then
        return xPlayer.Functions.AddItem(itemName, count)
    elseif shared.GetFrameworkName() == 'qbx' then
        return xPlayer.Functions.AddItem(itemName, count)
    end
    return false
end

return Inventory
