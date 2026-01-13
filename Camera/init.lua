local canvas = require('canvas')

local Camera = {}
Camera.__index = Camera

--- Creates a new camera instance
--- @param viewport_width number Viewport width in pixels
--- @param viewport_height number Viewport height in pixels
--- @param world_width number World width in tiles
--- @param world_height number World height in tiles
function Camera.new(viewport_width, viewport_height, world_width, world_height)
	local self = setmetatable({}, Camera)

	-- Viewport properties (in pixels)
	self._viewport_width = viewport_width
	self._viewport_height = viewport_height

	-- World bounds (in tiles)
	self._world_width = world_width
	self._world_height = world_height

	-- Camera position (in tiles, represents top-left corner of viewport)
	self._x = 0
	self._y = 0

	-- Target to follow (typically player)
	self._target = nil

	return self
end

--- Getters
function Camera:get_x() return self._x end
function Camera:get_y() return self._y end
function Camera:get_viewport_width() return self._viewport_width end
function Camera:get_viewport_height() return self._viewport_height end

--- Setters
function Camera:set_x(x) self._x = x end
function Camera:set_y(y) self._y = y end
function Camera:set_viewport_width(w) self._viewport_width = w end
function Camera:set_viewport_height(h) self._viewport_height = h end

--- Sets the target entity to follow
--- @param target table Entity with .x and .y properties (in tiles)
function Camera:set_target(target)
	self._target = target
end

--- Updates camera position to follow target (call each frame)
--- @param tile_size number Pixels per tile (for conversion)
--- @param lerp_factor? number Interpolation factor (0-1, default 1.0)
function Camera:update(tile_size, lerp_factor)
	if not self._target then return end

	lerp_factor = lerp_factor or 1.0  -- Default: instant

	local target_cam_x = self._target.x - (self._viewport_width / 2 / tile_size)
	local target_cam_y = self._target.y - (self._viewport_height / 2 / tile_size)

	local max_cam_x = self._world_width - (self._viewport_width / tile_size)
	local max_cam_y = self._world_height - (self._viewport_height / tile_size)

	target_cam_x = math.max(0, math.min(target_cam_x, max_cam_x))
	target_cam_y = math.max(0, math.min(target_cam_y, max_cam_y))

	-- Lerp towards target
	self._x = self._x + (target_cam_x - self._x) * lerp_factor
	self._y = self._y + (target_cam_y - self._y) * lerp_factor
end

--- Gets the visible tile bounds for culling
--- @param tile_size number Pixels per tile
--- @return number, number, number, number min_x, min_y, max_x, max_y in tiles
function Camera:get_visible_bounds(tile_size)
	local min_x = math.floor(self._x)
	local min_y = math.floor(self._y)
	local max_x = math.ceil(self._x + (self._viewport_width / tile_size))
	local max_y = math.ceil(self._y + (self._viewport_height / tile_size))

	return min_x, min_y, max_x, max_y
end

--- Applies camera transform to canvas (call before drawing world)
--- @param tile_size number Pixels per tile
function Camera:apply_transform(tile_size)
	-- Translate canvas by negative camera position
	canvas.translate(-self._x * tile_size, -self._y * tile_size)
end

--- Converts screen coordinates to world coordinates
--- @param screen_x number Screen X in pixels
--- @param screen_y number Screen Y in pixels
--- @param tile_size number Pixels per tile
--- @return number, number World X and Y in tiles
function Camera:screen_to_world(screen_x, screen_y, tile_size)
	local world_x = (screen_x / tile_size) + self._x
	local world_y = (screen_y / tile_size) + self._y
	return world_x, world_y
end

--- Converts world coordinates to screen coordinates
--- @param world_x number World X in tiles
--- @param world_y number World Y in tiles
--- @param tile_size number Pixels per tile
--- @return number, number Screen X and Y in pixels
function Camera:world_to_screen(world_x, world_y, tile_size)
	local screen_x = (world_x - self._x) * tile_size
	local screen_y = (world_y - self._y) * tile_size
	return screen_x, screen_y
end

return Camera
