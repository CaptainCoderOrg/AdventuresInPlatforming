--- RestorePoint module: Persists restore point data across player recreation
local RestorePoint = {}

local data = nil

--- Save a restore point
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param level table The level module
function RestorePoint.set(x, y, level)
    data = { x = x, y = y, level = level }
end

--- Get the current restore point
---@return table|nil data Restore point data with x, y, level fields, or nil if none set
function RestorePoint.get()
    return data
end

--- Clear the restore point
function RestorePoint.clear()
    data = nil
end

return RestorePoint
