--- Tile transform helper for Tiled flip support.
--- Handles horizontal and vertical flips from Tiled's flip flags.
local canvas = require("canvas")

local tile_transform = {}

--- Apply canvas transforms for Tiled flip flags.
--- Must be called after canvas.save() and before drawing.
--- Call canvas.restore() after drawing to undo transforms.
---
---@param flip_h boolean Horizontal flip flag
---@param flip_v boolean Vertical flip flag
---@param width number Tile width in pixels
---@param height number Tile height in pixels
function tile_transform.apply(flip_h, flip_v, width, height)
	-- Translate to center, apply transforms, translate back
	local cx = width / 2
	local cy = height / 2
	canvas.translate(cx, cy)

	-- Apply horizontal flip
	if flip_h then
		canvas.scale(-1, 1)
	end

	-- Apply vertical flip
	if flip_v then
		canvas.scale(1, -1)
	end

	-- Translate back to origin
	canvas.translate(-cx, -cy)
end

--- Check if any transform flags are set.
---@param flip_h boolean|nil Horizontal flip flag
---@param flip_v boolean|nil Vertical flip flag
---@return boolean True if any flag is set
function tile_transform.has_transform(flip_h, flip_v)
	return flip_h or flip_v or false
end

return tile_transform
