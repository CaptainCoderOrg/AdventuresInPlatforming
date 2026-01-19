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
