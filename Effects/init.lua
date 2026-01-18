local sprites = require('sprites')
local canvas = require('canvas')
local Animation = require('Animation')
local state = require('Effects/state')
local config = require('config')

local Effects = {}
Effects.__index = Effects

-- Animation definitions
Effects.animations = {
	HIT = Animation.create_definition(sprites.effects.hit, 4, {
		width = 16,
		height = 16,
		loop = false
	}),
	SHURIKEN_HIT = Animation.create_definition(sprites.effects.shuriken_hit, 6, {
		width = 8,
		height = 8,
		loop = false
	}),
}

--- Removes items from a set that match a predicate.
--- @param set table Set (table with items as keys)
--- @param should_remove function Predicate returning true if item should be removed
local function remove_from_set(set, should_remove)
	local to_remove = {}
	for item in pairs(set) do
		if should_remove(item) then
			table.insert(to_remove, item)
		end
	end
	for _, item in ipairs(to_remove) do
		set[item] = nil
	end
end

--- Updates all active effects, removes finished ones
--- @param dt number Delta time in seconds
function Effects.update(dt)
	for effect in pairs(state.all) do
		effect.animation:play(dt)
	end
	remove_from_set(state.all, function(effect)
		return effect.animation:is_finished()
	end)

	for text in pairs(state.damage_texts) do
		text.y = text.y + text.vy * dt
		text.elapsed = text.elapsed + dt
	end
	remove_from_set(state.damage_texts, function(text)
		return text.elapsed >= text.lifetime
	end)
end

--- Draws all active effects
function Effects.draw()
	canvas.save()
	for effect, _ in pairs(state.all) do
		effect.animation:draw(
			effect.x * sprites.tile_size,
			effect.y * sprites.tile_size
		)
	end

	for text, _ in pairs(state.damage_texts) do
		local alpha = 1 - (text.elapsed / text.lifetime)
		local color = text.damage > 0 and "#FF0000" or "#FFFFFF"
		local display = tostring(text.damage)

		canvas.set_global_alpha(alpha)
		canvas.set_color(color)
		canvas.set_font_family("menu_font")
		canvas.set_font_size(6*config.ui.SCALE)

		local text_width = canvas.get_text_width(display)
		local px = text.x * sprites.tile_size - text_width / 2
		local py = text.y * sprites.tile_size
		canvas.draw_text(px, py, display)
	end
	canvas.set_global_alpha(1)

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

	self.id = name .. "_" .. state.next_id
	state.next_id = state.next_id + 1

	self.animation = Animation.new(animation_def)
	self.x = x
	self.y = y

	-- Register in active effects
	state.all[self] = true

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

--- Factory: Creates a shuriken hit effect at specified location
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @param direction number|nil Direction for flipping (1 = right, -1 = left), defaults to 1
--- @return table Shuriken hit effect instance
function Effects.create_shuriken_hit(x, y, direction)
	direction = direction or 1
	local off_x = 0.25
	local effect = Effects.new("shuriken_hit", Effects.animations.SHURIKEN_HIT, x + off_x, y + 0.25)
	effect.animation.flipped = -direction
	return effect
end

--- Factory: Creates floating damage text at specified location
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @param damage number Damage amount (0 for blocked hits)
function Effects.create_damage_text(x, y, damage)
	local text = {
		x = x,
		y = y,
		vy = -2,          -- Float upward (tiles/second)
		damage = damage,
		lifetime = 0.8,   -- Duration in seconds
		elapsed = 0,
	}
	state.damage_texts[text] = true
end

--- Clears all effects (for level reloading)
function Effects.clear()
	state.all = {}
	state.damage_texts = {}
end

return Effects
