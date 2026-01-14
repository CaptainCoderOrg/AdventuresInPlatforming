local canvas = require('canvas')
local world = require('world')
local controls = require('controls')
local cfg = require('config/camera')

local Camera = {}
Camera.__index = Camera

--- Creates a new camera instance
--- @param viewport_width number Viewport width in pixels
--- @param viewport_height number Viewport height in pixels
--- @param world_width number World width in tiles
--- @param world_height number World height in tiles
function Camera.new(viewport_width, viewport_height, world_width, world_height)
	local self = setmetatable({}, Camera)

	self._viewport_width = viewport_width
	self._viewport_height = viewport_height
	self._world_width = world_width
	self._world_height = world_height
	self._x = 0
	self._y = 0
	self._target = nil

	-- Horizontal look-ahead state
	self._look_ahead_offset_x = 0
	self._look_ahead_distance_x = cfg.look_ahead_distance_x
	self._look_ahead_speed_x = cfg.look_ahead_speed_x

	-- Vertical framing state
	self._ground_y = nil
	self._fall_time = 0
	self._fall_lerp_min = cfg.fall_lerp_min
	self._fall_lerp_max = cfg.fall_lerp_max
	self._fall_lerp_ramp_duration = cfg.fall_lerp_ramp_duration

	-- Manual look state
	self._manual_x_target = nil
	self._manual_y_target = nil
	self._manual_look_speed = cfg.manual_look_speed

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

--- Calculates target Y for falling state
--- @param reference_y number Player Y position
--- @param tile_size number Pixels per tile
--- @return number Target camera Y
function Camera:_calculate_falling_target_y(reference_y, tile_size)
	local viewport_tiles = self._viewport_height / tile_size
	local desired_y = reference_y - viewport_tiles * cfg.framing_falling

	-- Clamp to prevent camera from overshooting landing position
	if self._target.box then
		local landing_y = world.raycast_down(
			self._target,
			cfg.raycast_distance
		)

		if landing_y then
			self._ground_y = landing_y

			-- Clamp camera to position landing at 2/3 from top (grounded framing)
			-- This ensures smooth transition from falling camera to grounded camera
			local max_cam_y = landing_y - viewport_tiles * cfg.framing_default

			-- Clamp: don't let camera go too low (high Y value) which would overshoot landing
			-- When Y increases downward: higher Y = camera positioned lower = shows more above
			if desired_y > max_cam_y then
				desired_y = max_cam_y
			end
		else
			self._ground_y = self._target.y
		end
	end

	return desired_y
end

--- Calculates target Y for climbing state
--- @param reference_y number Player Y position
--- @param tile_size number Pixels per tile
--- @return number Target camera Y
function Camera:_calculate_climbing_target_y(reference_y, tile_size)
	local viewport_tiles = self._viewport_height / tile_size
	local desired_y

	if self._target.vy < 0 then
		desired_y = reference_y - viewport_tiles * cfg.framing_default
	elseif self._target.vy > 0 then
		desired_y = reference_y - viewport_tiles * cfg.framing_climbing_down
	else
		desired_y = reference_y - viewport_tiles * cfg.framing_climbing_idle
	end

	if self._target.current_ladder then
		if self._target.vy < 0 and self._target.current_ladder.ladder_top then
			local exit_y = self._target.current_ladder.ladder_top.y - cfg.ladder_exit_offset
			local max_y = exit_y - viewport_tiles * cfg.framing_default
			desired_y = math.max(desired_y, max_y)
		elseif self._target.vy > 0 and self._target.current_ladder.ladder_bottom then
			local exit_y = self._target.current_ladder.ladder_bottom.y
			local min_y = exit_y - viewport_tiles * cfg.framing_default
			desired_y = math.min(desired_y, min_y)
		end
	end

	return desired_y
end

--- Calculates target Y for default state
--- @param reference_y number Player Y position
--- @param tile_size number Pixels per tile
--- @return number Target camera Y
function Camera:_calculate_default_target_y(reference_y, tile_size)
	return reference_y - (self._viewport_height / tile_size) * cfg.framing_default
end

--- Configures horizontal look-ahead behavior
--- @param distance_x? number Look-ahead distance in tiles (default from config)
--- @param speed_x? number Interpolation speed (default from config)
function Camera:set_look_ahead(distance_x, speed_x)
	self._look_ahead_distance_x = distance_x or cfg.look_ahead_distance_x
	self._look_ahead_speed_x = speed_x or cfg.look_ahead_speed_x
end

--- Sets the falling camera lerp parameters
--- @param min_lerp? number Starting lerp speed when falling starts (default from config)
--- @param max_lerp? number Maximum lerp speed after ramp (default from config)
--- @param ramp_duration? number Seconds to ramp from min to max (default from config)
function Camera:set_fall_lerp(min_lerp, max_lerp, ramp_duration)
	self._fall_lerp_min = min_lerp or cfg.fall_lerp_min
	self._fall_lerp_max = max_lerp or cfg.fall_lerp_max
	self._fall_lerp_ramp_duration = ramp_duration or cfg.fall_lerp_ramp_duration
end


--- Updates camera position to follow target (call each frame)
--- @param tile_size number Pixels per tile (for conversion)
--- @param dt number Delta time in seconds
--- @param lerp_factor? number Interpolation factor (0-1, default 1.0)
function Camera:update(tile_size, dt, lerp_factor)
	if not self._target then return end

	lerp_factor = lerp_factor or 1.0

	-- Horizontal look-ahead
	local target_offset_x = self._target.direction * self._look_ahead_distance_x

	-- Smoothly interpolate horizontal offset
	self._look_ahead_offset_x = self._look_ahead_offset_x +
		(target_offset_x - self._look_ahead_offset_x) * self._look_ahead_speed_x

	local target_cam_x = self._target.x + self._look_ahead_offset_x -
		(self._viewport_width / 2 / tile_size)

	-- Vertical camera positioning: track Y when in stable states
	local is_grounded = self._target.is_grounded
	local is_wall_sliding = self._target.state and self._target.state.name == "wall_slide"
	local is_climbing = self._target.state and self._target.state.name == "climb"
	local is_moving_up = self._target.vy and self._target.vy < 0

	-- Update stored Y when in stable state (grounded or wall sliding) and not moving up
	if (is_grounded or is_wall_sliding) and not is_moving_up then
		self._ground_y = self._target.y
	end

	-- Check if falling at terminal velocity
	local is_falling_fast = self._target.vy and self._target.vy >= cfg.terminal_velocity

	-- Track falling duration for lerp speed ramping
	if is_falling_fast then
		self._fall_time = self._fall_time + dt
	else
		self._fall_time = 0
	end

	-- Determine reference Y based on player state
	local reference_y
	if is_climbing or is_falling_fast then
		-- Climbing or falling at max speed: use player's current position
		reference_y = self._target.y
	else
		-- Normal: use stored stable position
		reference_y = self._ground_y or self._target.y
	end

	-- Calculate camera target based on player state
	local target_cam_y
	if is_falling_fast then
		target_cam_y = self:_calculate_falling_target_y(reference_y, tile_size)
	elseif is_climbing then
		target_cam_y = self:_calculate_climbing_target_y(reference_y, tile_size)
	else
		target_cam_y = self:_calculate_default_target_y(reference_y, tile_size)
	end

	-- Manual look controls (right analog stick with proportional adjustment)
	local viewport_tiles = self._viewport_height / tile_size
	local look_x = controls.get_camera_look_x()
	local look_y = controls.get_camera_look_y()

	if look_y ~= 0 then
		local target_framing
		if look_y < 0 then
			-- Looking up: interpolate between default and up framing
			local t = math.abs(look_y)
			target_framing = cfg.framing_default + (cfg.manual_look_down_framing - cfg.framing_default) * t
		else
			-- Looking down: interpolate between default and down framing
			local t = look_y
			target_framing = cfg.framing_default + (cfg.manual_look_up_framing - cfg.framing_default) * t
		end

		local manual_target_y = reference_y - viewport_tiles * target_framing
		self._manual_y_target = self._manual_y_target or target_cam_y
		self._manual_y_target = self._manual_y_target +
			(manual_target_y - self._manual_y_target) * self._manual_look_speed
		target_cam_y = self._manual_y_target
	else
		-- Fade back to state-calculated position
		if self._manual_y_target then
			self._manual_y_target = self._manual_y_target +
				(target_cam_y - self._manual_y_target) * self._manual_look_speed
			target_cam_y = self._manual_y_target

			if math.abs(self._manual_y_target - target_cam_y) < cfg.epsilon then
				self._manual_y_target = nil
			end
		end
	end

	if look_x ~= 0 then
		local manual_offset_x = look_x * cfg.manual_look_horizontal_distance
		self._manual_x_target = self._manual_x_target or 0
		self._manual_x_target = self._manual_x_target +
			(manual_offset_x - self._manual_x_target) * self._manual_look_speed
		target_cam_x = target_cam_x + self._manual_x_target
	else
		-- Fade back to no horizontal offset
		if self._manual_x_target then
			self._manual_x_target = self._manual_x_target +
				(0 - self._manual_x_target) * self._manual_look_speed

			if math.abs(self._manual_x_target) < cfg.epsilon then
				self._manual_x_target = nil
			else
				target_cam_x = target_cam_x + self._manual_x_target
			end
		end
	end

	local max_cam_x = self._world_width - (self._viewport_width / tile_size)
	local max_cam_y = self._world_height - (self._viewport_height / tile_size)

	target_cam_x = math.max(0, math.min(target_cam_x, max_cam_x))
	target_cam_y = math.max(0, math.min(target_cam_y, max_cam_y))

	--- Apply epsilon snapping to prevent floating-point drift.
	--- When delta is below epsilon (0.01 tiles ~0.5 pixels), snap to target
	--- instead of lerping to prevent endless approach without arrival.
	local delta_x = target_cam_x - self._x
	local delta_y = target_cam_y - self._y

	if math.abs(delta_x) < cfg.epsilon then
		self._x = target_cam_x
	else
		self._x = self._x + delta_x * lerp_factor
	end

	-- Calculate Y lerp speed based on falling duration
	local y_lerp = lerp_factor
	if is_falling_fast then
		local ramp_progress = math.min(self._fall_time / self._fall_lerp_ramp_duration, 1.0)
		y_lerp = self._fall_lerp_min + (self._fall_lerp_max - self._fall_lerp_min) * ramp_progress
	end

	if math.abs(delta_y) < cfg.epsilon then
		self._y = target_cam_y
	else
		self._y = self._y + delta_y * y_lerp
	end
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
