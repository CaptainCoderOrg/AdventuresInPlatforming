--- Shop transaction handling: purchase validation and execution
local transactions = {}

--- Check if player can afford an item
---@param player table Player instance
---@param price number Item price in gold
---@return boolean can_afford True if player has enough gold
function transactions.can_afford(player, price)
    return player and player.gold and player.gold >= price
end

--- Check if player already owns a unique item
---@param player table Player instance
---@param item_id string Unique item ID
---@return boolean owns True if player already has this item
function transactions.owns_unique_item(player, item_id)
    if not player or not player.unique_items then
        return false
    end
    for _, item in ipairs(player.unique_items) do
        if item.id == item_id then
            return true
        end
    end
    return false
end

--- Get current count of a stackable item
---@param player table Player instance
---@param item_id string Stackable item ID
---@return number count Current stack count (0 if none)
function transactions.get_stackable_count(player, item_id)
    if not player or not player.stackable_items then
        return 0
    end
    return player.stackable_items[item_id] or 0
end

--- Check if player can purchase an item (has gold and doesn't already own unique items)
---@param player table Player instance
---@param item table Shop item definition
---@return boolean can_buy True if purchase is valid
---@return string|nil reason Reason if purchase is not valid
function transactions.can_purchase(player, item)
    if not transactions.can_afford(player, item.price) then
        return false, "Not enough gold"
    end

    if item.type == "unique" and transactions.owns_unique_item(player, item.item_id) then
        return false, "Already owned"
    end

    -- Check max stack for stackable items
    if item.type == "stackable" and item.max_stack then
        local current = transactions.get_stackable_count(player, item.item_id)
        if current >= item.max_stack then
            return false, "Max owned"
        end
    end

    return true, nil
end

--- Execute a purchase transaction
---@param player table Player instance
---@param item table Shop item definition
---@return boolean success True if purchase succeeded
function transactions.purchase(player, item)
    local can_buy, _ = transactions.can_purchase(player, item)
    if not can_buy then
        return false
    end

    -- Deduct gold
    player.gold = player.gold - item.price

    -- Give item based on type
    if item.type == "unique" then
        -- Add unique item to player's inventory
        if not player.unique_items then
            player.unique_items = {}
        end
        table.insert(player.unique_items, { id = item.item_id })
    elseif item.type == "stackable" then
        -- Add to stackable item count
        if not player.stackable_items then
            player.stackable_items = {}
        end
        local amount = item.amount or 1
        player.stackable_items[item.item_id] = (player.stackable_items[item.item_id] or 0) + amount
    elseif item.type == "stat" then
        -- Modify player stat
        if item.stat_key and item.stat_value then
            player[item.stat_key] = (player[item.stat_key] or 0) + item.stat_value
        end
    end

    return true
end

return transactions
