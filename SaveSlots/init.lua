--- SaveSlots module: Manages 3 save slots using localStorage
local localstorage = require("APIS/localstorage")
local json = require("APIS/json")

local SaveSlots = {}

SaveSlots.SLOT_COUNT = 3

-- Storage key prefix
local STORAGE_KEY_PREFIX = "save_slot_"
local OLD_STORAGE_KEY = "restore_point"

-- In-memory cache for slots
local slots = {}

--- Get storage key for a slot
---@param slot_index number Slot index (1-3)
---@return string key Storage key
local function get_key(slot_index)
    return STORAGE_KEY_PREFIX .. tostring(slot_index)
end

--- Load a slot from localStorage
---@param slot_index number Slot index (1-3)
---@return table|nil data Slot data or nil if empty
local function load_slot(slot_index)
    local json_str = localstorage.get_item(get_key(slot_index))
    if not json_str then return nil end

    local success, parsed = pcall(json.decode, json_str)
    if success and type(parsed) == "table" then
        return parsed
    end
    return nil
end

--- Save a slot to localStorage
---@param slot_index number Slot index (1-3)
---@param data table Slot data
local function save_slot(slot_index, data)
    local json_str = json.encode(data)
    local success, err = localstorage.set_item(get_key(slot_index), json_str)
    if not success then
        print("[SaveSlots] Failed to save slot " .. slot_index .. ": " .. (err or "unknown error"))
    end
end

--- Migrate old restore_point data to slot 1 if it exists and slot 1 is empty
local function migrate_old_data()
    -- Check if slot 1 already has data
    if slots[1] then return end

    -- Check for old restore_point data
    local json_str = localstorage.get_item(OLD_STORAGE_KEY)
    if not json_str then return end

    local success, parsed = pcall(json.decode, json_str)
    if success and type(parsed) == "table" then
        -- Convert old format to new format
        local migrated = {
            x = parsed.x,
            y = parsed.y,
            level_id = parsed.level_id,
            direction = parsed.direction or 1,
            campfire_name = "Campfire",  -- Default name for migrated data
            playtime = 0,
            max_health = 3,
            level = 1,
        }

        -- Save to slot 1
        slots[1] = migrated
        save_slot(1, migrated)

        -- Remove old data
        localstorage.remove_item(OLD_STORAGE_KEY)

        print("[SaveSlots] Migrated old restore_point to slot 1")
    end
end

--- Initialize the module and load all slots from storage
function SaveSlots.init()
    for i = 1, SaveSlots.SLOT_COUNT do
        slots[i] = load_slot(i)
    end
    migrate_old_data()
end

--- Get data from a save slot
---@param slot_index number Slot index (1-3)
---@return table|nil data Slot data or nil if empty
function SaveSlots.get(slot_index)
    if slot_index < 1 or slot_index > SaveSlots.SLOT_COUNT then
        return nil
    end
    return slots[slot_index]
end

--- Save data to a slot
---@param slot_index number Slot index (1-3)
---@param data table Slot data to save
function SaveSlots.set(slot_index, data)
    if slot_index < 1 or slot_index > SaveSlots.SLOT_COUNT then
        print("[SaveSlots] Invalid slot index: " .. tostring(slot_index))
        return
    end
    slots[slot_index] = data
    save_slot(slot_index, data)
end

--- Check if a slot has saved data
---@param slot_index number Slot index (1-3)
---@return boolean has_data True if slot has data
function SaveSlots.has_data(slot_index)
    return SaveSlots.get(slot_index) ~= nil
end

--- Clear a save slot
---@param slot_index number Slot index (1-3)
function SaveSlots.clear(slot_index)
    if slot_index < 1 or slot_index > SaveSlots.SLOT_COUNT then
        return
    end
    slots[slot_index] = nil
    localstorage.remove_item(get_key(slot_index))
end

--- Core player stats that must be preserved across saves and level transitions
--- This is the single source of truth for persistent player data
---@type string[]
SaveSlots.PLAYER_STAT_KEYS = {
    "max_health", "max_stamina", "max_energy",
    "level", "experience", "gold",
    "defense", "recovery", "critical_chance",
    "stat_upgrades", "unique_items",
}

--- Transient state preserved during level transitions but reset at campfires
---@type string[]
SaveSlots.TRANSIENT_KEYS = { "damage", "energy_used", "stamina_used", "projectile_ix" }

--- Copy a value, creating deep copies for tables (stat_upgrades) and arrays (unique_items)
---@param key string The stat key being copied
---@param value any The value to copy
---@return any copy Deep copy for tables/arrays, direct value otherwise
local function copy_stat_value(key, value)
    if value == nil then return nil end
    if key == "unique_items" then
        local prop_common = require("Prop/common")
        return prop_common.copy_array(value)
    elseif key == "stat_upgrades" then
        local copy = {}
        for stat, count in pairs(value) do
            copy[stat] = count
        end
        return copy
    end
    return value
end

--- Get core player stats for preservation
--- Use this for level transitions; add transient state (damage, energy_used, etc.) separately
---@param player table Player instance
---@return table stats Core player stats
function SaveSlots.get_player_stats(player)
    local stats = {}
    for _, key in ipairs(SaveSlots.PLAYER_STAT_KEYS) do
        stats[key] = copy_stat_value(key, player[key])
    end
    return stats
end

--- Restore core player stats from saved data
--- Inverse of get_player_stats; handles deep copies for tables/arrays
---@param player table Player instance to restore stats to
---@param stats table Saved stats data
function SaveSlots.restore_player_stats(player, stats)
    for _, key in ipairs(SaveSlots.PLAYER_STAT_KEYS) do
        if stats[key] ~= nil then
            player[key] = copy_stat_value(key, stats[key])
        end
    end
end

--- Get transient state for level transitions (not saved at campfires)
---@param player table Player instance
---@return table state Transient state values
function SaveSlots.get_transient_state(player)
    local state = {}
    for _, key in ipairs(SaveSlots.TRANSIENT_KEYS) do
        state[key] = player[key]
    end
    return state
end

--- Restore transient state from saved data
--- Inverse of get_transient_state
---@param player table Player instance to restore state to
---@param state table Saved transient state
function SaveSlots.restore_transient_state(player, state)
    for _, key in ipairs(SaveSlots.TRANSIENT_KEYS) do
        if state[key] ~= nil then
            player[key] = state[key]
        end
    end
end

--- Build complete player save data structure for campfire saves
--- Includes position, level info, and playtime in addition to core stats
---@param player table Player instance
---@param level_id string Current level ID
---@param campfire_name string Name of the campfire
---@return table data Complete save data structure
function SaveSlots.build_player_data(player, level_id, campfire_name)
    local Playtime = require("Playtime")
    local Prop = require("Prop")

    local data = SaveSlots.get_player_stats(player)
    data.x = player.x
    data.y = player.y
    data.level_id = level_id
    data.direction = player.direction
    data.campfire_name = campfire_name or "Campfire"
    data.playtime = Playtime.get()
    data.prop_states = Prop.get_persistent_states()
    return data
end

--- Format playtime as HH:MM:SS
---@param seconds number Total seconds played
---@return string formatted Formatted time string
function SaveSlots.format_playtime(seconds)
    seconds = math.floor(seconds or 0)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

return SaveSlots
