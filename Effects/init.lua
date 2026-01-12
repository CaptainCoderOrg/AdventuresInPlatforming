local sprites = require('sprites')
local canvas = require('canvas')
local Animation = require('Animation')

local Effects = {}
Effects.__index = Effects
Effects.all = {}
Effects.next_id = 1

-- Animation definitions
Effects.animations = {
	HIT = Animation.create_definition("effect_hit", 4, {
		width = 16,
		height = 16,
		ms_per_frame = 80,
		loop = false  -- One-shot animation
	})
}

--- Updates all active effects, removes finished ones
--- @param dt number Delta time in seconds
function Effects.update(dt)
	local to_remove = {}

	for effect, _ in pairs(Effects.all) do
		-- Update animation
		effect.animation:play(dt)

		-- Check if animation finished
		if effect.animation:is_finished() then
			table.insert(to_remove, effect)
		end
	end

	-- Remove finished effects
	for _, effect in ipairs(to_remove) do
		Effects.all[effect] = nil
	end
end

--- Draws all active effects
function Effects.draw()
	canvas.save()
	for effect, _ in pairs(Effects.all) do
		effect.animation:draw(
			effect.x * sprites.tile_size,
			effect.y * sprites.tile_size
		)
	end
	canvas.restore()
end

--- Creates a new effect instance
--- @param name string Effect name for ID generation
--- @param animation_def table Animation definition
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @return table Effect instance
function Effects.new(name, animation_def, x, y)
	local self = setmetatable({}, Effects)

	self.id = name .. "_" .. Effects.next_id
	Effects.next_id = Effects.next_id + 1

	self.animation = Animation.new(animation_def)
	self.x = x
	self.y = y

	-- Register in active effects
	Effects.all[self] = true

	return self
end

--- Factory: Creates a hit effect at specified location
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @param direction number Direction for flipping (1 = right, -1 = left)
--- @return table Hit effect instance
function Effects.create_hit(x, y, direction)
	direction = direction or 1
	local effect = Effects.new("hit", Effects.animations.HIT, x, y)
	effect.animation.flipped = direction
	return effect
end

return Effects
