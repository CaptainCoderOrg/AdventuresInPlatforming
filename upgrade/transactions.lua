--- Purchase validation and execution for equipment upgrades

local upgrade_registry = require("upgrade/registry")
local stackable_item_registry = require("Prop/stackable_item_registry")
local prop_common = require("Prop/common")

local transactions = {}

--- Check if player can purchase the next upgrade tier for an item
---@param player table Player instance
---@param item_id string Item identifier
---@return boolean success True if purchase is possible
---@return string reason Reason if purchase is not possible
function transactions.can_purchase(player, item_id)
    local def = upgrade_registry.get(item_id)
    if not def then return false, "No upgrades available" end

    local current_tier = (player.upgrade_tiers and player.upgrade_tiers[item_id]) or 0
    if current_tier >= #def.tiers then return false, "Already maxed" end

    local next_tier = def.tiers[current_tier + 1]

    -- Check gold
    if (player.gold or 0) < next_tier.gold then
        return false, "Not enough gold"
    end

    -- Check material requirement (stackable items)
    if next_tier.material then
        local count = (player.stackable_items and player.stackable_items[next_tier.material]) or 0
        if count < 1 then
            local mat_def = stackable_item_registry[next_tier.material]
            local mat_name = mat_def and mat_def.name or next_tier.material
            return false, "Need " .. mat_name
        end
    end

    return true, ""
end

--- Execute a purchase for the next upgrade tier
---@param player table Player instance
---@param item_id string Item identifier
---@return boolean success True if purchase succeeded
---@return string result Zabarbra's result description
function transactions.purchase(player, item_id)
    local can, reason = transactions.can_purchase(player, item_id)
    if not can then return false, reason end

    local def = upgrade_registry.get(item_id)
    local current_tier = (player.upgrade_tiers and player.upgrade_tiers[item_id]) or 0
    local next_tier = def.tiers[current_tier + 1]

    -- Deduct gold
    player.gold = player.gold - next_tier.gold

    -- Consume material from stackable items if required
    if next_tier.material then
        prop_common.consume_stackable_item(player, next_tier.material)
    end

    -- Increment tier
    if not player.upgrade_tiers then player.upgrade_tiers = {} end
    player.upgrade_tiers[item_id] = current_tier + 1

    return true, next_tier.result or ""
end

return transactions
