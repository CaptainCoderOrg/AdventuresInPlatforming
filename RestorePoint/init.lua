--- RestorePoint module: Persists restore point data across sessions using localStorage
local localstorage = require("APIS/localstorage")
local json = require("APIS/json")

local RestorePoint = {}

local STORAGE_KEY = "restore_point"
local data = nil  -- In-memory cache

--- Save a restore point (persists to localStorage)
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param level_id string The level identifier (e.g., "level1")
---@param direction number|nil Facing direction (-1 left, 1 right)
function RestorePoint.set(x, y, level_id, direction)
    data = { x = x, y = y, level_id = level_id, direction = direction or 1 }
    local json_str = json.encode(data)
    local success, err = localstorage.set_item(STORAGE_KEY, json_str)
    if not success then
        print("[RestorePoint] Failed to save: " .. (err or "unknown error"))
    end
end

--- Get the current restore point (loads from localStorage if needed)
---@return table|nil data Restore point with x, y, level_id, direction, or nil
function RestorePoint.get()
    if data then return data end

    local json_str = localstorage.get_item(STORAGE_KEY)
    if not json_str then return nil end

    local success, parsed = pcall(json.decode, json_str)
    if success and type(parsed) == "table" then
        data = parsed
        return data
    end
    return nil
end

--- Clear the restore point (removes from localStorage)
function RestorePoint.clear()
    data = nil
    localstorage.remove_item(STORAGE_KEY)
end

return RestorePoint
