--- Weapon synchronization module for managing equipped weapon state
--- Bridges the gap between equipped_items (UI/persistence) and combat behavior

local controls = require("controls")
local unique_item_registry = require("Prop.unique_item_registry")
local upgrade_effects = require("upgrade/effects")

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

--- Returns true if the given secondary_id is a valid equipped secondary
---@param player table The player object
---@param secondary_id string|nil The secondary item_id to check
---@return boolean is_valid True if secondary_id is equipped and is a secondary type
local function is_valid_secondary(player, secondary_id)
    if not secondary_id or not player.equipped_items or not player.equipped_items[secondary_id] then
        return false
    end
    local def = unique_item_registry[secondary_id]
    return def and def.type == "secondary"
end

--- Returns the first equipped weapon found (helper for fallback scenarios)
---@param player table The player object
---@return string|nil weapon_id The first equipped weapon's item_id, or nil if none
---@return table|nil weapon_def The weapon's definition from unique_item_registry, or nil if none
function weapon_sync.get_first_equipped_weapon(player)
    local weapons = weapon_sync.get_all_equipped_weapons(player)
    if #weapons > 0 then
        return weapons[1].id, weapons[1].def
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

--- Returns all equipped weapons as an array (cached, invalidated by sync())
---@param player table The player object
---@return table Array of {id, def} pairs for each equipped weapon
function weapon_sync.get_all_equipped_weapons(player)
    if player._cached_weapons then return player._cached_weapons end

    local weapons = player._weapon_cache or {}
    player._weapon_cache = weapons
    local count = 0

    if player.equipped_items then
        for item_id, equipped in pairs(player.equipped_items) do
            if equipped then
                local def = unique_item_registry[item_id]
                if def and def.type == "weapon" then
                    count = count + 1
                    local entry = weapons[count]
                    if not entry then
                        entry = {}
                        weapons[count] = entry
                    end
                    entry.id = item_id
                    entry.def = def
                end
            end
        end
    end
    -- Clear stale entries
    for i = count + 1, #weapons do weapons[i] = nil end
    player._cached_weapons = weapons
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

-- Secondary item functions (similar pattern to weapons)

--- Returns all equipped secondaries as an array (cached, invalidated by sync())
---@param player table The player object
---@return table Array of {id, def} pairs for each equipped secondary
function weapon_sync.get_equipped_secondaries(player)
    if player._cached_secondaries then return player._cached_secondaries end

    local secondaries = player._secondary_cache or {}
    player._secondary_cache = secondaries
    local count = 0

    if player.equipped_items then
        for item_id, equipped in pairs(player.equipped_items) do
            if equipped then
                local def = unique_item_registry[item_id]
                if def and def.type == "secondary" then
                    count = count + 1
                    local entry = secondaries[count]
                    if not entry then
                        entry = {}
                        secondaries[count] = entry
                    end
                    entry.id = item_id
                    entry.def = def
                end
            end
        end
    end
    -- Clear stale entries
    for i = count + 1, #secondaries do secondaries[i] = nil end
    player._cached_secondaries = secondaries
    return secondaries
end

--- Returns the secondary id and definition for a specific ability slot.
--- Falls back to player.active_ability_slot if slot is nil.
---@param player table The player object
---@param slot number|nil Ability slot index (1-6), falls back to player.active_ability_slot
---@return string|nil secondary_id The secondary's item_id, or nil if slot is empty/invalid
---@return table|nil secondary_def The secondary's definition from unique_item_registry, or nil
function weapon_sync.get_slot_secondary(player, slot)
    slot = slot or player.active_ability_slot
    if not slot or not player.ability_slots then return nil, nil end
    local item_id = player.ability_slots[slot]
    if not item_id then return nil, nil end
    if not is_valid_secondary(player, item_id) then return nil, nil end
    return item_id, unique_item_registry[item_id]
end

--- Returns the projectile spec for a specific ability slot (or active_ability_slot as fallback)
--- Maps secondary item_id to the corresponding projectile definition
---@param player table The player object
---@param slot number|nil Ability slot (1-6), falls back to player.active_ability_slot
---@return table|nil spec The projectile spec, or nil if no secondary equipped
function weapon_sync.get_secondary_spec(player, slot)
    local secondary_id = weapon_sync.get_slot_secondary(player, slot)
    if not secondary_id then return nil end

    -- Map secondary item IDs to projectile specs
    -- This requires Projectile module to be loaded lazily to avoid circular dependency
    local Projectile = require("Projectile")
    if secondary_id == "throwing_axe" then
        return Projectile.get_axe()
    elseif secondary_id == "shuriken" then
        return Projectile.get_shuriken()
    end
    return nil
end

--- Returns whether a secondary ability in the given slot is unlocked.
--- Throwable secondaries check has_axe/has_shuriken flags.
--- Non-throwable secondaries (e.g., minor_healing) are always unlocked (gated by equip logic).
---@param player table The player object
---@param slot number|nil Ability slot (1-6), falls back to player.active_ability_slot
---@return boolean True if the secondary is unlocked
function weapon_sync.is_secondary_unlocked(player, slot)
    local secondary_id = weapon_sync.get_slot_secondary(player, slot)
    if not secondary_id then return false end
    if secondary_id == "throwing_axe" then return player.has_axe end
    if secondary_id == "shuriken" then return player.has_shuriken end
    if secondary_id == "hammer" then return player.has_hammer end
    return true
end

--- Returns the charge definition and runtime state for an item, or nil if not charge-based.
---@param player table The player object
---@param item_id string|nil Item ID to look up
---@return table|nil def Registry definition (only if charge-based)
---@return table|nil state Runtime charge state
local function resolve_charge(player, item_id)
    if not item_id then return nil, nil end
    local def = unique_item_registry[item_id]
    if not def or not def.max_charges then return nil, nil end
    return def, player.charge_state[item_id]
end

--- Returns true if the secondary in the given slot has charges available (or is not charge-based).
--- Non-charge items always pass.
---@param player table The player object
---@param slot number|nil Ability slot (1-6), falls back to player.active_ability_slot
---@return boolean True if throw is allowed by charge system
function weapon_sync.has_throw_charges(player, slot)
    local sec_id = weapon_sync.get_slot_secondary(player, slot)
    local def, state = resolve_charge(player, sec_id)
    if not def or not state then return true end
    local max = upgrade_effects.get_max_charges(player, sec_id, def.max_charges)
    return state.used_charges < max
end

--- Consumes one charge from the active ability slot's secondary and starts recharge timer.
---@param player table The player object
function weapon_sync.consume_charge(player)
    local sec_id = weapon_sync.get_slot_secondary(player)
    local def, state = resolve_charge(player, sec_id)
    if not def or not state then return end
    local max = upgrade_effects.get_max_charges(player, sec_id, def.max_charges)
    state.used_charges = math.min(state.used_charges + 1, max)
    if state.recharge_timer == 0 then
        local recharge = upgrade_effects.get_recharge(player, sec_id, def.recharge)
        state.recharge_timer = recharge
        state.effective_recharge = recharge
    end
end

--- Ticks recharge timers for ALL equipped charge secondaries.
--- When a timer elapses: restore 1 charge, restart timer if more charges still spent, else stop.
---@param player table The player object
---@param dt number Delta time in seconds
function weapon_sync.update_charges(player, dt)
    for item_id, state in pairs(player.charge_state) do
        if state.recharge_timer > 0 then
            state.recharge_timer = state.recharge_timer - dt
            if state.recharge_timer <= 0 then
                state.used_charges = math.max(0, state.used_charges - 1)
                if state.used_charges > 0 then
                    -- More charges to recover, restart timer
                    local def = unique_item_registry[item_id]
                    local recharge = def and upgrade_effects.get_recharge(player, item_id, def.recharge) or 0
                    state.recharge_timer = recharge
                    state.effective_recharge = recharge
                else
                    state.recharge_timer = 0
                end
            end
        end
    end
end

--- Returns charge info for HUD rendering.
---@param item_id string Secondary item ID
---@param player table The player object
---@return number available Available charges
---@return number max_charges Maximum charges
---@return number progress Recharge progress 0.0-1.0 (0 = just started, 1 = about to restore)
function weapon_sync.get_charge_info(item_id, player)
    local def, state = resolve_charge(player, item_id)
    if not def then return 0, 0, 0 end
    local max = upgrade_effects.get_max_charges(player, item_id, def.max_charges)
    if not state then return max, max, 0 end
    local available = max - state.used_charges
    local progress = 0
    local effective_recharge = state.effective_recharge or def.recharge
    if state.recharge_timer > 0 and effective_recharge > 0 then
        progress = 1 - (state.recharge_timer / effective_recharge)
    end
    return available, max, progress
end

--- Syncs player ability flags from equipped_items
--- Updates has_axe, has_shuriken, has_shield, can_dash, has_double_jump, has_wall_slide
--- Scans ability_slots to cache dash_slot/shield_slot positions
--- Also ensures active_weapon is valid (auto-selects first equipped weapon if needed)
---@param player table The player object
function weapon_sync.sync(player)
    -- Invalidate cached equipment lists
    player._cached_weapons = nil
    player._cached_secondaries = nil

    if not player.equipped_items then
        player.equipped_items = {}
    end

    -- Sync secondary weapons
    player.has_axe = player.equipped_items.throwing_axe == true
    player.has_shuriken = player.equipped_items.shuriken == true
    player.has_hammer = player.equipped_items.hammer == true

    -- Sync accessories
    player.has_double_jump = player.equipped_items.jump_ring == true
    player.has_wall_slide = player.equipped_items.grip_boots == true

    -- Ensure active_weapon is valid (auto-select first equipped weapon if invalid)
    if not is_valid_weapon(player, player.active_weapon) then
        player.active_weapon = weapon_sync.get_first_equipped_weapon(player)
    end

    -- Validate ability_slots: clear any slot with an invalid/unequipped secondary
    if player.ability_slots then
        for i = 1, controls.ABILITY_SLOT_COUNT do
            if player.ability_slots[i] and not is_valid_secondary(player, player.ability_slots[i]) then
                player.ability_slots[i] = nil
            end
        end
    end

    -- Scan ability_slots for dash/shield positions (avoids per-frame scanning)
    player.dash_slot = nil
    player.shield_slot = nil
    if player.ability_slots then
        for i = 1, controls.ABILITY_SLOT_COUNT do
            local item = player.ability_slots[i]
            if item == "dash_amulet" then player.dash_slot = i
            elseif item == "shield" then player.shield_slot = i end
        end
    end
    player.can_dash = player.dash_slot ~= nil
    player.has_shield = player.shield_slot ~= nil

    -- Initialize charge_state entries for equipped charge-based secondaries
    if not player.charge_state then player.charge_state = {} end
    local secondaries = weapon_sync.get_equipped_secondaries(player)
    for _, sec in ipairs(secondaries) do
        if sec.def.max_charges and not player.charge_state[sec.id] then
            player.charge_state[sec.id] = { used_charges = 0, recharge_timer = 0 }
        end
    end
    -- Remove charge_state entries for unequipped secondaries
    for item_id in pairs(player.charge_state) do
        if not player.equipped_items[item_id] then
            player.charge_state[item_id] = nil
        end
    end
end

return weapon_sync
