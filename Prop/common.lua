--- Shared utilities for prop definitions
local sprites = require("sprites")
local combat = require("combat")
local stackable_item_registry = require("Prop.stackable_item_registry")

local common = {}

-- Lazy-loaded to avoid circular dependency (Prop/init.lua requires this module)
local Prop = nil
local Effects = nil

--- Standard animation draw for props
---@param prop table Prop instance with animation
---@param y_offset number|nil Optional Y offset in tiles
function common.draw(prop, y_offset)
    if prop.animation then
        local y = prop.y + (y_offset or 0)
        prop.animation:draw(sprites.px(prop.x), sprites.px(y))
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

--- Check if player has a specific item (checks both stackable and unique items)
---@param player table Player instance
---@param item_id string Item identifier to check
---@return boolean True if player has the item
function common.player_has_item(player, item_id)
    if not player then return false end
    -- Check stackable_items first
    if player.stackable_items and player.stackable_items[item_id] and player.stackable_items[item_id] > 0 then
        return true
    end
    -- Fall back to unique_items
    if not player.unique_items then return false end
    local items = player.unique_items
    for i = 1, #items do
        if items[i] == item_id then return true end
    end
    return false
end

--- Add a stackable item to the player's inventory
---@param player table Player instance
---@param item_id string Item identifier
---@param count number|nil Amount to add (default: 1)
---@return boolean True if item was added
function common.add_stackable_item(player, item_id, count)
    if not player or not player.stackable_items then return false end
    count = count or 1
    if count <= 0 then return false end

    local item_def = stackable_item_registry[item_id]
    local max_stack = (item_def and item_def.max_stack) or 99

    local current = player.stackable_items[item_id] or 0
    local new_count = math.min(current + count, max_stack)
    player.stackable_items[item_id] = new_count

    return true
end

--- Consume a stackable item from the player's inventory
--- Displays the item name above the player when consumed
---@param player table Player instance
---@param item_id string Item identifier
---@param count number|nil Amount to consume (default: 1)
---@return boolean True if item was consumed, false if insufficient quantity
function common.consume_stackable_item(player, item_id, count)
    if not player or not player.stackable_items then return false end
    count = count or 1
    if count <= 0 then return true end

    local current = player.stackable_items[item_id] or 0
    if current < count then
        return false
    end

    local new_count = current - count
    if new_count <= 0 then
        player.stackable_items[item_id] = nil
    else
        player.stackable_items[item_id] = new_count
    end

    -- Display item name above player
    Effects = Effects or require("Effects")
    local item_def = stackable_item_registry[item_id]
    if item_def and item_def.name then
        Effects.create_text(player.x, player.y, item_def.name)
    end

    return true
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

--- Filter for levers that are not currently toggling
---@param prop table Lever prop instance
---@return boolean True if lever can be toggled
local function lever_not_toggling(prop)
    return prop.state_name ~= "toggling"
end

--- Check if a hitbox overlaps a lever and toggle it if found
--- Returns true if a lever was hit (caller should mark hit_lever = true)
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@return boolean True if lever was toggled
function common.check_lever_hit(hitbox)
    Prop = Prop or require("Prop")
    local lever = Prop.check_hit("lever", hitbox, lever_not_toggling)
    if lever then
        lever.definition.toggle(lever)
        return true
    end
    return false
end

--- Update text display visibility based on player proximity
--- Common pattern used by interactive props with text prompts
---@param prop table Prop instance with text_display
---@param dt number Delta time in seconds
---@param player table The player object
function common.update_text_display(prop, dt, player)
    local touching = common.player_touching(prop, player)
    prop.text_display:update(dt, touching)
end

--- Draw prop animation and text display
--- Common pattern for interactive props with text prompts
---@param prop table Prop instance with animation and text_display
function common.draw_with_text(prop)
    common.draw(prop)
    prop.text_display:draw(prop.x, prop.y)
end

return common
