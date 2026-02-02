local canvas = require('canvas')
local config = require('config')

local Animation = {}
Animation.__index = Animation

--- Creates a new animation definition (shared template)
--- @param name string Sprite sheet name
--- @param frame_count number Total frames in animation
--- @param options table Options: ms_per_frame, width, height, loop
--- @return table Animation definition
function Animation.create_definition(name, frame_count, options)
	options = options or {}
	return {
		name = name,
		frame_count = frame_count,
		ms_per_frame = options.ms_per_frame or 80,
		width = options.width or 16,
		height = options.height or 16,
		loop = options.loop ~= false  -- Default true
	}
end

--- Creates a new animation instance (per-entity state)
--- @param definition table Animation definition
--- @param options table Options: flipped, start_frame, ms_per_frame (override)
--- @return table Animation instance
function Animation.new(definition, options)
	options = options or {}
	local self = setmetatable({}, Animation)

	self.definition = definition
	self.reverse = options.reverse or false
	-- Set starting frame based on playback direction
	if options.start_frame then
		self.frame = options.start_frame
	else
		self.frame = self.reverse and (definition.frame_count - 1) or 0
	end
	self.flipped = options.flipped or 1
	self.elapsed = 0  -- Accumulated time in milliseconds
	self.playing = true
	self.finished = false
	self.ms_per_frame = options.ms_per_frame  -- nil means use definition

	return self
end

--- Advances animation by delta time
--- @param dt number Delta time in seconds
function Animation:play(dt)
	if not self.playing or self.finished then
		return
	end

	-- Guard against zero or negative dt
	if dt <= 0 then
		return
	end

	-- Accumulate elapsed time (convert dt from seconds to milliseconds)
	self.elapsed = self.elapsed + (dt * 1000)

	local ms_per_frame = self.ms_per_frame or self.definition.ms_per_frame
	if self.elapsed >= ms_per_frame then
		local frames_to_advance = math.floor(self.elapsed / ms_per_frame)
		self.elapsed = self.elapsed % ms_per_frame  -- Keep remainder

		if self.reverse then
			self.frame = self.frame - frames_to_advance

			if self.frame < 0 then
				if self.definition.loop then
					-- Wrap to end for looping reverse animations
					self.frame = (self.definition.frame_count - 1) - (math.abs(self.frame + 1) % self.definition.frame_count)
				else
					self.frame = 0
					self.finished = true
					self.playing = false
				end
			end
		else
			self.frame = self.frame + frames_to_advance

			-- Handle frame wrapping/clamping
			if self.frame >= self.definition.frame_count then
				if self.definition.loop then
					self.frame = self.frame % self.definition.frame_count
				else
					self.frame = self.definition.frame_count - 1
					self.finished = true
					self.playing = false
				end
			end
		end
	end
end

--- Resets animation to beginning
function Animation:reset()
	self.frame = 0
	self.elapsed = 0
	self.finished = false
	self.playing = true
end

--- Reinitializes an existing animation instance with a new definition.
--- Avoids allocation by reusing the existing table.
--- @param definition table Animation definition
--- @param options table|nil Options: flipped, reverse, start_frame, ms_per_frame
--- @return table Self for chaining
function Animation:reinit(definition, options)
	options = options or {}
	self.definition = definition
	self.reverse = options.reverse or false
	if options.start_frame then
		self.frame = options.start_frame
	else
		self.frame = self.reverse and (definition.frame_count - 1) or 0
	end
	self.flipped = options.flipped or 1
	self.elapsed = 0
	self.playing = true
	self.finished = false
	self.ms_per_frame = options.ms_per_frame  -- nil means use definition
	return self
end

--- Pauses animation playback
function Animation:pause()
	self.playing = false
end

--- Resumes animation playback if not finished
function Animation:resume()
	if not self.finished then
		self.playing = true
	end
end

--- Checks if animation is finished (for non-looping animations)
--- @return boolean
function Animation:is_finished()
	return self.finished
end

--- Draws the animation at the specified position
--- @param x number X coordinate in pixels
--- @param y number Y coordinate in pixels
--- @param rotation number Optional rotation in radians
function Animation:draw(x, y, rotation)
	local definition = self.definition
	local frame = self.frame
	local flipped = self.flipped

	local x_adjust = 0
	if flipped == 1 then
		x_adjust = definition.width
	elseif definition.width > config.ui.TILE then
		x_adjust = -config.ui.TILE
	end

	canvas.save()
	canvas.translate(x + (x_adjust * config.ui.SCALE), y)
	canvas.scale(-flipped, 1)
	if rotation and rotation ~= 0 then
		-- Rotate around bottom-center so sprite stays grounded
		local cx = definition.width * config.ui.SCALE / 2
		local cy = definition.height * config.ui.SCALE
		canvas.translate(cx, cy)
		canvas.rotate(rotation * flipped)  -- Flip rotation direction with sprite
		canvas.translate(-cx, -cy)
	end
	canvas.draw_image(definition.name, 0, 0,
		definition.width * config.ui.SCALE, definition.height * config.ui.SCALE,
		frame * definition.width, 0,
		definition.width, definition.height)
	canvas.restore()
end

return Animation
