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

	for text in pairs(state.status_texts) do
		text.y = text.y + text.vy * dt
		text.elapsed = text.elapsed + dt
	end
	remove_from_set(state.status_texts, function(text)
		return text.elapsed >= text.lifetime
	end)

	for particle in pairs(state.fatigue_particles) do
		particle.x = particle.x + particle.vx * dt
		particle.y = particle.y + particle.vy * dt
		particle.elapsed = particle.elapsed + dt
	end
	remove_from_set(state.fatigue_particles, function(particle)
		return particle.elapsed >= particle.lifetime
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

	for text, _ in pairs(state.status_texts) do
		local alpha = 1 - (text.elapsed / text.lifetime)

		canvas.set_global_alpha(alpha)
		canvas.set_color(text.color)
		canvas.set_font_family("menu_font")
		canvas.set_font_size(6*config.ui.SCALE)

		local text_width = canvas.get_text_width(text.message)
		local px = text.x * sprites.tile_size - text_width / 2
		local py = text.y * sprites.tile_size
		canvas.draw_text(px, py, text.message)
	end

	for particle, _ in pairs(state.fatigue_particles) do
		local alpha = 1 - (particle.elapsed / particle.lifetime)
		canvas.set_global_alpha(alpha * 0.7)
		canvas.set_fill_style(particle.color)
		local px = particle.x * sprites.tile_size
		local py = particle.y * sprites.tile_size
		canvas.fill_rect(px, py, particle.size, particle.size)
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

--- Factory: Creates floating status text at specified location (e.g. "TIRED")
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
function Effects.create_fatigue_text(x, y)
	local text = {
		x = x + 0.5,      -- Center on player
		y = y + 0.5,      -- Start at player center
		vy = -1,          -- Float upward slowly (tiles/second)
		message = "TIRED",
		color = "#FF0000", -- Red
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
	}
	state.status_texts[text] = true
end

--- Factory: Creates a sweat droplet that drips from the player
--- @param x number X position in tile coordinates (player center)
--- @param y number Y position in tile coordinates (player center)
function Effects.create_fatigue_particle(x, y)
	-- Spawn from sides/top of player (around the head area)
	local side = math.random()
	local spawn_x, spawn_y
	if side < 0.4 then
		-- Left side
		spawn_x = x - 0.15
		spawn_y = y - 0.3 + math.random() * 0.2
	elseif side < 0.8 then
		-- Right side
		spawn_x = x + 0.15
		spawn_y = y - 0.3 + math.random() * 0.2
	else
		-- Top (forehead)
		spawn_x = x + (math.random() - 0.5) * 0.2
		spawn_y = y - 0.4
	end

	local particle = {
		x = spawn_x,
		y = spawn_y,
		vx = (math.random() - 0.5) * 0.3,     -- Slight horizontal drift
		vy = 1.5 + math.random() * 1.0,       -- Fall downward (1.5-2.5 tiles/second)
		color = "#88CCFF",                     -- Light blue (sweat)
		size = 5 + math.random() * 3,          -- 5-8 pixels
		lifetime = 0.5 + math.random() * 0.3,  -- 0.5-0.8 seconds
		elapsed = 0,
	}
	state.fatigue_particles[particle] = true
end

--- Clears all effects (for level reloading)
function Effects.clear()
	state.all = {}
	state.damage_texts = {}
	state.status_texts = {}
	state.fatigue_particles = {}
end

return Effects
