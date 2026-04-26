local Inventory = {}

--- Verifica se o player tem um item no inventário (lado cliente via ox_inventory se disponível)
--- @param itemName string Nome do item
--- @param count? number Quantidade mínima (default 1)
--- @return boolean
function Inventory.HasItem(itemName, count)
    count = count or 1
    if exports['ox_inventory'] then
        local item = exports['ox_inventory']:Search('count', itemName)
        return (item or 0) >= count
    end
    return false
end

--- Devolve a quantidade de um item no inventário do player
--- @param itemName string
--- @return number
function Inventory.GetItemCount(itemName)
    if exports['ox_inventory'] then
        return exports['ox_inventory']:Search('count', itemName) or 0
    end
    return 0
end

return Inventory
