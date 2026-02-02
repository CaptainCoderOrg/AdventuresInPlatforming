--- Weapon synchronization module for managing equipped weapon state
--- Bridges the gap between equipped_items (UI/persistence) and combat behavior

local unique_item_registry = require("Prop.unique_item_registry")

local weapon_sync = {}

--- Returns true if the given weapon_id is a valid equipped weapon
---@param player table The player object
---@param weapon_id string|nil The weapon item_id to check
---@return boolean is_valid True if weapon_id is equipped and is a weapon type
local function is_valid_weapon(player, weapon_id)
    if not weapon_id or not player.equipped_items or not player.equipped_items[weapon_id] then
        return false
    end
    local def = unique_item_registry[weapon_id]
    return def and def.type == "weapon"
end

--- Returns the first equipped weapon found (helper for fallback scenarios)
---@param player table The player object
---@return string|nil weapon_id The first equipped weapon's item_id, or nil if none
---@return table|nil weapon_def The weapon's definition from unique_item_registry, or nil if none
function weapon_sync.get_first_equipped_weapon(player)
    if not player.equipped_items then return nil, nil end

    for item_id, equipped in pairs(player.equipped_items) do
        if equipped then
            local def = unique_item_registry[item_id]
            if def and def.type == "weapon" then
                return item_id, def
            end
        end
    end
    return nil, nil
end

--- Returns the active weapon id and definition from player's equipped_items
--- Uses player.active_weapon if set and valid, otherwise falls back to first equipped weapon
---@param player table The player object
---@return string|nil weapon_id The active weapon's item_id, or nil if none
---@return table|nil weapon_def The weapon's definition from unique_item_registry, or nil if none
function weapon_sync.get_equipped_weapon(player)
    if not player.equipped_items then return nil, nil end

    -- Return active_weapon if valid, otherwise fall back to first equipped weapon
    if is_valid_weapon(player, player.active_weapon) then
        return player.active_weapon, unique_item_registry[player.active_weapon]
    end
    return weapon_sync.get_first_equipped_weapon(player)
end

--- Returns all equipped weapons as an array
---@param player table The player object
---@return table Array of {id, def} pairs for each equipped weapon
function weapon_sync.get_all_equipped_weapons(player)
    local weapons = {}
    if not player.equipped_items then return weapons end

    for item_id, equipped in pairs(player.equipped_items) do
        if equipped then
            local def = unique_item_registry[item_id]
            if def and def.type == "weapon" then
                table.insert(weapons, { id = item_id, def = def })
            end
        end
    end
    return weapons
end

--- Cycles to the next equipped weapon
--- Returns the new active weapon's name if switched, nil if no other weapons
---@param player table The player object
---@return string|nil weapon_name The new active weapon's display name, or nil if not switched
function weapon_sync.cycle_weapon(player)
    local weapons = weapon_sync.get_all_equipped_weapons(player)
    if #weapons <= 1 then return nil end  -- Need at least 2 weapons to cycle

    -- Find current active weapon index
    local current_index = 1
    for i, weapon in ipairs(weapons) do
        if weapon.id == player.active_weapon then
            current_index = i
            break
        end
    end

    -- Advance to next weapon (wrap around)
    local next_index = (current_index % #weapons) + 1
    local next_weapon = weapons[next_index]

    player.active_weapon = next_weapon.id
    return next_weapon.def.name
end

--- Returns the stats table for the currently equipped weapon
---@param player table The player object
---@return table|nil stats The weapon's stats table, or nil if no weapon equipped
function weapon_sync.get_weapon_stats(player)
    local _, weapon_def = weapon_sync.get_equipped_weapon(player)
    return weapon_def and weapon_def.stats
end

--- Syncs player ability flags from equipped_items
--- Updates has_shield, has_axe, has_shuriken, can_dash, has_double_jump, has_wall_slide
--- Also ensures active_weapon is valid (auto-selects first equipped weapon if needed)
---@param player table The player object
function weapon_sync.sync(player)
    if not player.equipped_items then
        player.equipped_items = {}
    end

    -- Sync shield
    player.has_shield = player.equipped_items.shield == true

    -- Sync secondary weapons
    player.has_axe = player.equipped_items.throwing_axe == true
    player.has_shuriken = player.equipped_items.shuriken == true

    -- Sync accessories
    player.can_dash = player.equipped_items.dash_amulet == true
    player.has_double_jump = player.equipped_items.jump_ring == true
    player.has_wall_slide = player.equipped_items.grip_boots == true

    -- Ensure active_weapon is valid (auto-select first equipped weapon if invalid)
    if not is_valid_weapon(player, player.active_weapon) then
        player.active_weapon = weapon_sync.get_first_equipped_weapon(player)
    end
end

return weapon_sync
