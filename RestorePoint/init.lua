--- RestorePoint module: Persists restore point data across player recreation
local RestorePoint = {}

local data = nil

--- Save a restore point
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param level table The level module
---@param direction number|nil Facing direction (-1 left, 1 right)
function RestorePoint.set(x, y, level, direction)
    data = { x = x, y = y, level = level, direction = direction or 1 }
end

--- Get the current restore point
---@return table|nil data Restore point data with x, y, level, direction fields, or nil if none set
function RestorePoint.get()
    return data
end

--- Clear the restore point
function RestorePoint.clear()
    data = nil
end

return RestorePoint
