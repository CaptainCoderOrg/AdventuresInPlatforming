local canvas = require('canvas')
local world = require('world')

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

	-- Look-ahead offset state
	self._look_ahead_offset_x = 0
	self._look_ahead_offset_y = 0
	self._look_ahead_distance_x = 3
	self._look_ahead_distance_y = 2
	self._look_ahead_speed_x = 0.05
	self._look_ahead_speed_y = 0.03

	-- Grace period timer for wall state transitions
	self._wall_grace_timer = 0
	self._wall_grace_duration = 0.3

	-- Vertical deadzone for wall jump sequences
	self._vertical_deadzone_active = false
	self._vertical_deadzone_timer = 0
	self._vertical_deadzone_grace_duration = 0.25
	self._vertical_deadzone_high_water_mark = 0

	-- Ground-based vertical framing
	self._ground_y = nil

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

--- Configures look-ahead behavior
--- @param distance_x? number Horizontal look-ahead distance in tiles (default 3)
--- @param distance_y? number Vertical look-ahead distance in tiles (default 2)
--- @param speed_x? number Horizontal interpolation speed (default 0.05)
--- @param speed_y? number Vertical interpolation speed (default 0.03)
function Camera:set_look_ahead(distance_x, distance_y, speed_x, speed_y)
	self._look_ahead_distance_x = distance_x or 3
	self._look_ahead_distance_y = distance_y or 2
	self._look_ahead_speed_x = speed_x or 0.05
	self._look_ahead_speed_y = speed_y or 0.03
end


--- Updates camera position to follow target (call each frame)
--- @param tile_size number Pixels per tile (for conversion)
--- @param dt number Delta time in seconds
--- @param lerp_factor? number Interpolation factor (0-1, default 1.0)
function Camera:update(tile_size, dt, lerp_factor)
	if not self._target then return end

	lerp_factor = lerp_factor or 1.0

	local in_wall_state = (self._target.state and
	                       (self._target.state.name == "wall_jump" or
	                        self._target.state.name == "wall_slide"))

	local in_wall_jump = (self._target.state and self._target.state.name == "wall_jump")

	-- Manage vertical deadzone activation and grace period (only for wall_jump)
	if in_wall_jump then
		if not self._vertical_deadzone_active then
			self._vertical_deadzone_active = true
			self._vertical_deadzone_high_water_mark = self._y
		else
			self._vertical_deadzone_high_water_mark = math.min(
				self._vertical_deadzone_high_water_mark,
				self._y
			)
		end
		self._vertical_deadzone_timer = self._vertical_deadzone_grace_duration
	elseif self._vertical_deadzone_timer > 0 then
		self._vertical_deadzone_timer = self._vertical_deadzone_timer - dt
		if self._vertical_deadzone_timer <= 0 then
			self._vertical_deadzone_active = false
		end
	else
		self._vertical_deadzone_active = false
	end

	if in_wall_state then
		self._wall_grace_timer = self._wall_grace_duration
	elseif self._wall_grace_timer > 0 then
		self._wall_grace_timer = self._wall_grace_timer - dt
	end

	local target_offset_x = 0
	if not in_wall_state and self._wall_grace_timer <= 0 then
		target_offset_x = self._target.direction * self._look_ahead_distance_x
	end

	-- Smoothly interpolate horizontal offset
	self._look_ahead_offset_x = self._look_ahead_offset_x +
		(target_offset_x - self._look_ahead_offset_x) * self._look_ahead_speed_x

	local target_cam_x = self._target.x + self._look_ahead_offset_x -
		(self._viewport_width / 2 / tile_size)

	-- Vertical camera positioning
	local target_cam_y
	if self._vertical_deadzone_active then
		-- Wall jump: use velocity-based offset system
		local target_offset_y = 0
		if self._target.vy and math.abs(self._target.vy) > 2 then
			local vy_normalized = math.max(-1, math.min(self._target.vy / 20, 1))
			target_offset_y = vy_normalized * self._look_ahead_distance_y

			if in_wall_jump and target_offset_y > 0 then
				target_offset_y = 0
			end
		end

		self._look_ahead_offset_y = self._look_ahead_offset_y +
			(target_offset_y - self._look_ahead_offset_y) * self._look_ahead_speed_y

		target_cam_y = self._target.y + self._look_ahead_offset_y -
			(self._viewport_height / 2 / tile_size)

		-- Lock camera at highest point
		target_cam_y = math.min(target_cam_y, self._vertical_deadzone_high_water_mark)
	else
		-- Normal gameplay: track ground Y when player is grounded and not moving upward
		local is_grounded = self._target.is_grounded
		local is_moving_up = self._target.vy and self._target.vy < 0

		if is_grounded and not is_moving_up then
			-- Update stored ground position only when truly on ground
			self._ground_y = self._target.y
			print("Player grounded at Y:", self._ground_y)
		end

		-- Use stored ground Y (or player Y if no ground stored yet)
		local reference_y = self._ground_y or self._target.y

		-- Center camera on reference Y
		target_cam_y = reference_y - (self._viewport_height / 2 / tile_size)

		print("is_grounded:", is_grounded, "is_moving_up:", is_moving_up, "reference_y:", reference_y, "target_cam_y:", target_cam_y)
	end

	local max_cam_x = self._world_width - (self._viewport_width / tile_size)
	local max_cam_y = self._world_height - (self._viewport_height / tile_size)

	target_cam_x = math.max(0, math.min(target_cam_x, max_cam_x))
	target_cam_y = math.max(0, math.min(target_cam_y, max_cam_y))

	print("Before lerp - camera._y:", self._y, "target_cam_y (clamped):", target_cam_y, "delta:", (target_cam_y - self._y))

	-- Lerp with epsilon snapping to prevent endless drift
	local epsilon = 0.01
	local delta_x = target_cam_x - self._x
	local delta_y = target_cam_y - self._y

	if math.abs(delta_x) < epsilon then
		self._x = target_cam_x
	else
		self._x = self._x + delta_x * lerp_factor
	end

	if math.abs(delta_y) < epsilon then
		self._y = target_cam_y
	else
		self._y = self._y + delta_y * lerp_factor
	end

	print("After lerp - camera._y:", self._y)
	print("---")
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
