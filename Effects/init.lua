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

-- Module-level table to avoid allocation each frame
local to_remove = {}

--- Removes items from a set that match a predicate.
--- @param set table Set (table with items as keys)
--- @param should_remove function Predicate returning true if item should be removed
local function remove_from_set(set, should_remove)
	-- Clear module-level table instead of allocating new one
	for i = 1, #to_remove do to_remove[i] = nil end
	local item = next(set)
	while item do
		if should_remove(item) then
			to_remove[#to_remove + 1] = item
		end
		item = next(set, item)
	end
	for i = 1, #to_remove do
		set[to_remove[i]] = nil
	end
end

-- Module-level predicates to avoid closure allocation per frame
local function effect_finished(effect)
	return effect.animation:is_finished()
end

local function text_expired(text)
	return text.elapsed >= text.lifetime
end

local function particle_expired(particle)
	return particle.elapsed >= particle.lifetime
end

--- Updates all active effects, removes finished ones
--- @param dt number Delta time in seconds
function Effects.update(dt)
	local effect = next(state.all)
	while effect do
		effect.animation:play(dt)
		effect = next(state.all, effect)
	end
	remove_from_set(state.all, effect_finished)

	local text = next(state.damage_texts)
	while text do
		text.y = text.y + text.vy * dt
		text.elapsed = text.elapsed + dt
		text = next(state.damage_texts, text)
	end
	remove_from_set(state.damage_texts, text_expired)

	text = next(state.status_texts)
	while text do
		text.y = text.y + text.vy * dt
		text.elapsed = text.elapsed + dt
		text = next(state.status_texts, text)
	end
	remove_from_set(state.status_texts, text_expired)

	local particle = next(state.fatigue_particles)
	while particle do
		particle.x = particle.x + particle.vx * dt
		particle.y = particle.y + particle.vy * dt
		particle.elapsed = particle.elapsed + dt
		particle = next(state.fatigue_particles, particle)
	end
	remove_from_set(state.fatigue_particles, particle_expired)
end

--- Draws all active effects (hit effects, damage text, status text, particles)
---@return nil
function Effects.draw()
	canvas.save()
	local effect = next(state.all)
	while effect do
		effect.animation:draw(
			effect.x * sprites.tile_size,
			effect.y * sprites.tile_size
		)
		effect = next(state.all, effect)
	end

	local text = next(state.damage_texts)
	while text do
		local alpha = 1 - (text.elapsed / text.lifetime)

		canvas.set_global_alpha(alpha)
		canvas.set_color(text.color)
		canvas.set_font_family("menu_font")
		canvas.set_font_size(6*config.ui.SCALE)

		local px = text.x * sprites.tile_size - text.cached_width / 2
		local py = text.y * sprites.tile_size
		canvas.draw_text(px, py, text.display)
		text = next(state.damage_texts, text)
	end

	text = next(state.status_texts)
	while text do
		local alpha = 1 - (text.elapsed / text.lifetime)

		canvas.set_global_alpha(alpha)
		canvas.set_color(text.color)
		canvas.set_font_family("menu_font")
		canvas.set_font_size(6*config.ui.SCALE)

		local px = text.x * sprites.tile_size - text.cached_width / 2
		local py = text.y * sprites.tile_size
		canvas.draw_text(px, py, text.message)
		text = next(state.status_texts, text)
	end

	local particle = next(state.fatigue_particles)
	while particle do
		local alpha = 1 - (particle.elapsed / particle.lifetime)
		canvas.set_global_alpha(alpha * 0.7)
		canvas.set_fill_style(particle.color)
		local px = particle.x * sprites.tile_size
		local py = particle.y * sprites.tile_size
		canvas.fill_rect(px, py, particle.size, particle.size)
		particle = next(state.fatigue_particles, particle)
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
--- @return nil
function Effects.create_damage_text(x, y, damage)
	local display = tostring(damage)
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6*config.ui.SCALE)
	local cached_width = canvas.get_text_width(display)

	local text = {
		x = x,
		y = y,
		vy = -2,          -- Float upward (tiles/second)
		display = display,  -- Pre-cache string conversion
		color = damage > 0 and "#FF0000" or "#FFFFFF",  -- Pre-cache color
		lifetime = 0.8,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
	}
	state.damage_texts[text] = true
end

--- Factory: Creates floating status text at specified location (e.g. "TIRED")
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @return nil
function Effects.create_fatigue_text(x, y)
	local message = "TIRED"
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6*config.ui.SCALE)
	local cached_width = canvas.get_text_width(message)

	local text = {
		x = x + 0.5,      -- Center on player
		y = y + 0.5,      -- Start at player center
		vy = -1,          -- Float upward slowly (tiles/second)
		message = message,
		color = "#FF0000", -- Red
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
	}
	state.status_texts[text] = true
end

--- Factory: Creates floating gold text at specified location (e.g. "+100 gold")
--- @param x number X position in tile coordinates
--- @param y number Y position in tile coordinates
--- @param amount number Gold amount to display
--- @return nil
function Effects.create_gold_text(x, y, amount)
	local message = "+" .. tostring(amount) .. " gold"
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6*config.ui.SCALE)
	local cached_width = canvas.get_text_width(message)

	local text = {
		x = x + 0.5,      -- Center on chest
		y = y,            -- Start at chest top
		vy = -2,          -- Float upward (tiles/second)
		message = message,
		color = "#FFD700", -- Gold color
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
	}
	state.status_texts[text] = true
end

--- Factory: Creates a sweat droplet that drips from the player
--- @param x number X position in tile coordinates (player center)
--- @param y number Y position in tile coordinates (player center)
--- @return nil
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
--- @return nil
function Effects.clear()
	for k in pairs(state.all) do state.all[k] = nil end
	for k in pairs(state.damage_texts) do state.damage_texts[k] = nil end
	for k in pairs(state.status_texts) do state.status_texts[k] = nil end
	for k in pairs(state.fatigue_particles) do state.fatigue_particles[k] = nil end
end

return Effects
