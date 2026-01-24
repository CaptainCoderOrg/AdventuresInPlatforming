--- Shared utilities for prop definitions
local sprites = require("sprites")
local combat = require("combat")

local common = {}

--- Standard animation draw for props
---@param prop table Prop instance with animation
function common.draw(prop)
    if prop.animation then
        local px = prop.x * sprites.tile_size
        local py = prop.y * sprites.tile_size
        prop.animation:draw(px, py)
    end
end

--- Check if player is touching a prop
--- Uses combat system spatial indexing for efficient overlap detection
---@param prop table Prop instance with box
---@param player table Player instance with box
---@return boolean True if overlapping
function common.player_touching(prop, player)
    return combat.collides(prop, player)
end

--- Check if player should take damage from a hazard and apply it
--- Consolidates the common pattern of checking touch, invincibility, and health
---@param prop table Prop instance with box
---@param player table Player instance
---@param damage number Amount of damage to deal
---@return boolean True if damage was dealt
function common.damage_player(prop, player, damage)
    if not player then return false end
    if not common.player_touching(prop, player) then return false end
    if player:is_invincible() then return false end
    if player:health() <= 0 then return false end

    player:take_damage(damage, prop.x)  -- Pass prop X for shield check
    return true
end

--- Check if player has a specific unique item
---@param player table Player instance
---@param item_id string Item identifier to check
---@return boolean True if player has the item
function common.player_has_item(player, item_id)
    if not player or not player.unique_items then return false end
    local items = player.unique_items
    for i = 1, #items do
        if items[i] == item_id then return true end
    end
    return false
end

--- Create a shallow copy of an array (for saving without reference issues)
---@param arr table Array to copy
---@return table copy New array with same values
function common.copy_array(arr)
    local copy = {}
    for i = 1, #arr do
        copy[i] = arr[i]
    end
    return copy
end

return common
