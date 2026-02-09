local sprites = require('sprites')
local sprites_items = require('sprites/items')
local canvas = require('canvas')
local Animation = require('Animation')
local state = require('Effects/state')
local config = require('config')

local Effects = {}
Effects.__index = Effects

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
local typewriter_opts = { align_h = "left", align_v = "top", char_count = 0 }

--- Removes items from a set that match a predicate.
---@param set table Set (table with items as keys)
---@param should_remove fun(item: table): boolean Predicate returning true if item should be removed
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

local function flying_object_finished(obj)
	return obj.phase == "complete"
end

--- Updates all active effects, removes finished ones
---@param dt number Delta time in seconds
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
		if text.follow_player then
			text.x = text.follow_player.x + 0.5
			text.y = text.follow_player.y + text.offset_y
			text.offset_y = text.offset_y + text.vy * dt  -- Float upward relative to player
		else
			text.y = text.y + text.vy * dt
		end
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

	particle = next(state.collect_particles)
	while particle do
		particle.x = particle.x + particle.vx * dt
		particle.y = particle.y + particle.vy * dt
		particle.elapsed = particle.elapsed + dt
		particle = next(state.collect_particles, particle)
	end
	remove_from_set(state.collect_particles, particle_expired)

	particle = next(state.heal_particles)
	while particle do
		particle.x = particle.x + particle.vx * dt
		particle.y = particle.y + particle.vy * dt
		particle.elapsed = particle.elapsed + dt
		particle = next(state.heal_particles, particle)
	end
	remove_from_set(state.heal_particles, particle_expired)

	-- Update flying objects (boss axe drop, etc.)
	local obj = next(state.flying_objects)
	while obj do
		obj.elapsed = obj.elapsed + dt

		if obj.phase == "flying" then
			local t = obj.elapsed / obj.flight_duration
			if t >= 1 then
				obj.x = obj.target_x
				obj.y = obj.target_y
				obj.rotation = obj.end_rotation
				obj.phase = "complete"
				if obj.on_complete then
					obj.on_complete()
				end
			else
				-- Position: ease-in-out for smooth arc
				local ease_t = t * t * (3 - 2 * t)
				obj.x = obj.start_x + (obj.target_x - obj.start_x) * ease_t
				obj.y = obj.start_y + (obj.target_y - obj.start_y) * ease_t

				-- Rotation: ease-out through 3 full rotations over entire flight
				local rot_ease = 1 - (1 - t) * (1 - t)  -- Ease-out
				obj.rotation = obj.start_rotation + (obj.end_rotation - obj.start_rotation) * rot_ease
			end
		end

		obj = next(state.flying_objects, obj)
	end
	remove_from_set(state.flying_objects, flying_object_finished)
end

--- Draws all active effects (hit effects, damage text, status text, particles)
---@return nil
function Effects.draw()
	canvas.save()
	local effect = next(state.all)
	while effect do
		effect.animation:draw(
			sprites.px(effect.x),
			sprites.px(effect.y)
		)
		effect = next(state.all, effect)
	end

	-- Draw damage texts (per-text font size for crits)
	canvas.set_font_family("menu_font")
	local text = next(state.damage_texts)
	while text do
		local font_size = text.font_size or 6
		canvas.set_font_size(font_size * config.ui.SCALE)
		local alpha = 1 - (text.elapsed / text.lifetime)
		canvas.set_global_alpha(alpha)
		canvas.set_color(text.color)
		local px = text.x * sprites.tile_size - text.cached_width / 2
		local py = text.y * sprites.tile_size
		canvas.draw_text(px, py, text.display)
		text = next(state.damage_texts, text)
	end

	text = next(state.status_texts)
	while text do
		local text_font_size = text.font_size or 6
		canvas.set_font_size(text_font_size * config.ui.SCALE)

		local alpha
		if text.fade_delay and text.elapsed < text.fade_delay then
			alpha = 1
		else
			local fade_start = text.fade_delay or 0
			local fade_duration = text.lifetime - fade_start
			alpha = 1 - ((text.elapsed - fade_start) / fade_duration)
		end
		canvas.set_global_alpha(alpha)
		canvas.set_color(text.color)
		local px = text.x * sprites.tile_size - text.cached_width / 2
		local py = text.y * sprites.tile_size

		if text.typewriter_duration then
			local char_count = math.floor((text.elapsed / text.typewriter_duration) * #text.message)
			char_count = math.min(char_count, #text.message)
			local font_height = text_font_size * config.ui.SCALE
			typewriter_opts.char_count = char_count
			canvas.draw_label(px, py - font_height, text.cached_width, font_height, text.message, typewriter_opts)
		else
			canvas.draw_text(px, py, text.message)
		end
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

	particle = next(state.collect_particles)
	while particle do
		local alpha = 1 - (particle.elapsed / particle.lifetime)
		canvas.set_global_alpha(alpha)
		canvas.set_fill_style(particle.color)
		local px = particle.x * sprites.tile_size
		local py = particle.y * sprites.tile_size
		canvas.fill_rect(px, py, particle.size, particle.size)
		particle = next(state.collect_particles, particle)
	end

	particle = next(state.heal_particles)
	while particle do
		local alpha = (1 - (particle.elapsed / particle.lifetime)) * 0.8
		canvas.set_global_alpha(alpha)
		canvas.set_fill_style(particle.color)
		local px = particle.x * sprites.tile_size
		local py = particle.y * sprites.tile_size
		canvas.fill_rect(px, py, particle.size, particle.size)
		particle = next(state.heal_particles, particle)
	end

	canvas.set_global_alpha(1)

	-- Draw flying objects (spinning axe, etc.)
	local obj = next(state.flying_objects)
	while obj do
		local px = obj.x * sprites.tile_size
		local py = obj.y * sprites.tile_size
		local size = obj.sprite_size * config.ui.SCALE

		canvas.save()
		canvas.translate(px + size / 2, py + size / 2)
		canvas.rotate(obj.rotation)
		canvas.draw_image(obj.sprite, -size / 2, -size / 2, size, size)
		canvas.restore()

		obj = next(state.flying_objects, obj)
	end

	canvas.restore()
end

--- Creates a new effect instance
---@param name string Effect name for ID generation
---@param animation_def table Animation definition
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return table Effect instance
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
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param direction number Direction for flipping (1 = right, -1 = left)
---@return table Hit effect instance
function Effects.create_hit(x, y, direction)
	direction = direction or 1
	local effect = Effects.new("hit", Effects.animations.HIT, x, y)
	effect.animation.flipped = direction
	return effect
end

--- Factory: Creates a shuriken hit effect at specified location
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param direction number|nil Direction for flipping (1 = right, -1 = left), defaults to 1
---@return table Shuriken hit effect instance
function Effects.create_shuriken_hit(x, y, direction)
	direction = direction or 1
	local off_x = 0.25
	local effect = Effects.new("shuriken_hit", Effects.animations.SHURIKEN_HIT, x + off_x, y + 0.25)
	effect.animation.flipped = -direction
	return effect
end

--- Factory: Creates floating damage text at specified location
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param damage number Damage amount (0 for blocked hits)
---@param is_crit boolean|nil Whether this is a critical hit (larger text)
---@return nil
function Effects.create_damage_text(x, y, damage, is_crit)
	local display = tostring(damage)
	local font_size = is_crit and 10 or 6
	canvas.set_font_family("menu_font")
	canvas.set_font_size(font_size * config.ui.SCALE)
	local cached_width = canvas.get_text_width(display)

	local text = {
		x = x,
		y = y,
		vy = -2,
		display = display,
		color = is_crit and "#FFFF00" or (damage > 0 and "#FF0000" or "#FFFFFF"),
		lifetime = 0.8,
		elapsed = 0,
		cached_width = cached_width,
		font_size = font_size,
	}
	state.damage_texts[text] = true
end

--- Factory: Creates floating status text at specified location (e.g. "TIRED")
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return nil
function Effects.create_fatigue_text(x, y)
	local message = "TIRED"
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6 * config.ui.SCALE)
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

--- Factory: Creates floating "Perfect Block" text at specified location
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return nil
function Effects.create_perfect_block_text(x, y)
	local message = "Perfect Block"
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6 * config.ui.SCALE)
	local cached_width = canvas.get_text_width(message)

	local text = {
		x = x + 0.5,      -- Center on player
		y = y,            -- Start at player top
		vy = -1.5,        -- Float upward (tiles/second)
		message = message,
		color = "#FFFF00", -- Yellow
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
	}
	state.status_texts[text] = true
end

--- Factory: Creates floating energy text at specified location (e.g. "Low Energy" or "No Energy")
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param current_energy number Current energy amount
---@return nil
function Effects.create_energy_text(x, y, current_energy)
	local message = current_energy > 0 and "Low Energy" or "No Energy"
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6 * config.ui.SCALE)
	local cached_width = canvas.get_text_width(message)

	local text = {
		x = x + 0.5,      -- Center on player
		y = y + 0.5,      -- Start at player center
		vy = -1,          -- Float upward slowly (tiles/second)
		message = message,
		color = "#0088FF", -- Blue (matches energy bar)
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
	}
	state.status_texts[text] = true
end

--- Factory: Creates floating status text with custom message and color
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param message string The text to display
---@param color string|nil Hex color (defaults to white)
---@param font_size number|nil Font size (defaults to 6)
---@return nil
function Effects.create_text(x, y, message, color, font_size)
	font_size = font_size or 6
	-- Cache text width at creation to avoid per-frame allocation
	canvas.set_font_family("menu_font")
	canvas.set_font_size(font_size * config.ui.SCALE)
	local cached_width = canvas.get_text_width(message)

	local text = {
		x = x + 0.5,      -- Center on entity
		y = y,            -- Start at position
		vy = -1,          -- Float upward slowly (tiles/second)
		message = message,
		color = color or "#FFFFFF",
		lifetime = 1.0,   -- Duration in seconds
		elapsed = 0,
		cached_width = cached_width,
		font_size = font_size,
	}
	state.status_texts[text] = true
end

--- Helper: Recalculates cached text width for a status text entry.
---@param text table The status text entry to update
local function update_text_width(text)
	canvas.set_font_family("menu_font")
	canvas.set_font_size(6 * config.ui.SCALE)
	text.cached_width = canvas.get_text_width(text.message)
end

--- Helper: Creates or updates an accumulating status text (gold, XP, heal, etc).
---@param tracker_key string Key in state for tracking active text (e.g. "active_gold_text")
---@param label string|nil Display label (e.g. "gold", "XP"); unused when format_fn is provided
---@param color string Hex color for the text
---@param offset_y number Vertical offset above player head
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number Amount to add
---@param player table|nil Optional player to follow
---@param format_fn fun(amount: number): string|nil Optional message formatter (default: "+{amount} {label}")
local function create_accumulating_text(tracker_key, label, color, offset_y, x, y, amount, player, format_fn)
	local active = state[tracker_key]
	if active and state.status_texts[active] then
		active.amount = active.amount + amount
		active.elapsed = 0
		local new_message = format_fn and format_fn(active.amount) or ("+" .. tostring(active.amount) .. " " .. label)
		if new_message ~= active.message then
			active.message = new_message
			update_text_width(active)
		end
		return
	end

	local message = format_fn and format_fn(amount) or ("+" .. tostring(amount) .. " " .. label)
	local start_x = player and (player.x + 0.5) or (x + 0.5)
	local start_y = player and (player.y + offset_y) or y
	local text = {
		x = start_x,
		y = start_y,
		vy = -0.5,
		message = message,
		color = color,
		lifetime = 1.5,
		elapsed = 0,
		cached_width = 0,
		amount = amount,
		follow_player = player,
		offset_y = offset_y,
	}
	update_text_width(text)
	state.status_texts[text] = true
	state[tracker_key] = text
end

--- Factory: Creates or updates floating gold text (e.g. "+1 gold")
--- If an active gold text exists, adds to it instead of creating a new one.
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number Gold amount to add
---@param player table|nil Optional player to follow
---@return nil
function Effects.create_gold_text(x, y, amount, player)
	create_accumulating_text("active_gold_text", "gold", "#FFD700", -0.2, x, y, amount, player)
end

--- Factory: Creates or updates floating XP text (e.g. "+1 XP")
--- If an active XP text exists, adds to it instead of creating a new one.
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number XP amount to add
---@param player table|nil Optional player to follow
---@return nil
function Effects.create_xp_text(x, y, amount, player)
	create_accumulating_text("active_xp_text", "XP", "#FFFFFF", -0.5, x, y, amount, player)
end

local function format_heal_hp(amount)
	return string.format("+%.1f HP", amount)
end

--- Factory: Creates or updates floating heal text (e.g. "+0.5 HP")
--- Accumulates fractional healing with 1 decimal place display.
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number HP amount to add
---@param player table Player to follow
---@return nil
function Effects.create_heal_text(x, y, amount, player)
	create_accumulating_text("active_heal_text", nil, "#44FF44", -0.2, x, y, amount, player, format_heal_hp)
end

local function format_hp_loot(amount)
	return string.format("+%.1f HP", amount)
end

--- Factory: Creates or updates floating HP loot text (e.g. "+0.5 HP")
--- Accumulates fractional HP gains from loot drops.
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number HP amount to add
---@param player table Player to follow
---@return nil
function Effects.create_hp_loot_text(x, y, amount, player)
	create_accumulating_text("active_hp_loot_text", nil, "#FF4466", 0.1, x, y, amount, player, format_hp_loot)
end

local function format_energy_loot(amount)
	return string.format("+%.1f Energy", amount)
end

--- Factory: Creates or updates floating energy loot text (e.g. "+0.5 Energy")
--- Accumulates fractional energy gains from loot drops.
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param amount number Energy amount to add
---@param player table Player to follow
---@return nil
function Effects.create_energy_loot_text(x, y, amount, player)
	create_accumulating_text("active_energy_loot_text", nil, "#4488FF", 0.4, x, y, amount, player, format_energy_loot)
end

--- Factory: Creates "Locked" text above the player
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param player table|nil Optional player to follow
---@return nil
function Effects.create_locked_text(x, y, player)
	local start_x = player and (player.x + 0.5) or (x + 0.5)
	local start_y = player and (player.y - 0.3) or y
	local text = {
		x = start_x,
		y = start_y,
		vy = -0.5,
		message = "Locked",
		color = "#FF6666",  -- Light red
		lifetime = 1.5,
		elapsed = 0,
		cached_width = 0,
		follow_player = player,
		offset_y = -0.3,
	}
	update_text_width(text)
	state.status_texts[text] = true
end

--- Factory: Creates hover text above a player that follows them
---@param player table Player to follow
---@param message string Text to display
---@param visible_duration number|nil Time to stay fully visible (default 3)
---@param fade_duration number|nil Time to fade out after visible duration (default 0)
---@param tag string|nil Optional tag to identify this text (removes existing text with same tag)
---@param typewriter_duration number|nil Time for text to appear letter by letter (default 0, instant)
---@return nil
function Effects.create_hover_text(player, message, visible_duration, fade_duration, tag, typewriter_duration)
	visible_duration = visible_duration or 3
	fade_duration = fade_duration or 0

	-- Remove existing text with same tag
	if tag then
		local text = next(state.status_texts)
		while text do
			local next_text = next(state.status_texts, text)
			if text.tag == tag then
				state.status_texts[text] = nil
			end
			text = next_text
		end
	end

	local text = {
		x = player.x + 0.5,
		y = player.y - 0.5,
		vy = 0,
		message = message,
		color = "#FFFFFF",
		lifetime = visible_duration + fade_duration,
		fade_delay = fade_duration > 0 and visible_duration or nil,
		elapsed = 0,
		cached_width = 0,
		follow_player = player,
		offset_y = -0.5,
		tag = tag,
		typewriter_duration = typewriter_duration and typewriter_duration > 0 and typewriter_duration or nil,
	}
	update_text_width(text)
	state.status_texts[text] = true
end

--- Factory: Creates a sweat droplet that drips from the player
---@param x number X position in tile coordinates (player center)
---@param y number Y position in tile coordinates (player center)
---@return nil
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

local heal_colors = { "#FF6688", "#FF4466", "#FF8899", "#FFAABB", "#FF5577" }

--- Factory: Creates a healing particle that converges toward the player center
---@param cx number Center X in tile coordinates (player center)
---@param cy number Center Y in tile coordinates (player center)
---@return nil
function Effects.create_heal_particle(cx, cy)
	local angle = math.random() * math.pi * 2
	local dist = 0.5 + math.random() * 1.0  -- 0.5-1.5 tiles from center
	local cos_a = math.cos(angle)
	local sin_a = math.sin(angle)
	local speed = dist * 1.8
	local particle = {
		x = cx + cos_a * dist,
		y = cy + sin_a * dist,
		vx = -cos_a * speed,
		vy = -sin_a * speed,
		color = heal_colors[math.random(#heal_colors)],
		size = 4 + math.random() * 3,  -- 4-7 pixels
		lifetime = 0.35 + dist * 0.2,  -- ~0.4-0.65s, longer for farther particles
		elapsed = 0,
	}
	state.heal_particles[particle] = true
end

-- Gold/yellow color palette for collect particles
local collect_colors = { "#FFD700", "#FFEC8B", "#FFF8DC", "#FFE4B5" }

--- Helper: Spawns a ring of particles around a point
---@param x number Center X in tile coordinates
---@param y number Center Y in tile coordinates
---@param cfg table Particle layer configuration
local function spawn_particle_ring(x, y, cfg)
	local count = cfg.base_count + math.random(cfg.count_variance)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * cfg.angle_jitter
		local speed = cfg.speed_min + math.random() * cfg.speed_range
		local particle = {
			x = x + (math.random() - 0.5) * cfg.spawn_spread,
			y = y + (math.random() - 0.5) * cfg.spawn_spread,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed + (cfg.vy_offset or 0),
			color = cfg.color or collect_colors[math.random(#collect_colors)],
			size = cfg.size_min + math.random() * cfg.size_range,
			lifetime = cfg.lifetime_min + math.random() * cfg.lifetime_range,
			elapsed = 0,
		}
		state.collect_particles[particle] = true
	end
end

-- Particle layer configurations for collect effect
local collect_layers = {
	{ -- Outer burst - large particles
		base_count = 32, count_variance = 6, angle_jitter = 0.4,
		speed_min = 1.2, speed_range = 0.8, spawn_spread = 0.15,
		size_min = 5, size_range = 4, lifetime_min = 0.2, lifetime_range = 0.15,
	},
	{ -- Middle layer - medium particles
		base_count = 32, count_variance = 6, angle_jitter = 0.5,
		speed_min = 0.6, speed_range = 0.6, spawn_spread = 0.1, vy_offset = -0.2,
		size_min = 4, size_range = 3, lifetime_min = 0.25, lifetime_range = 0.15,
	},
	{ -- Inner sparkles - small white particles
		base_count = 28, count_variance = 4, angle_jitter = 0.6,
		speed_min = 0.3, speed_range = 0.4, spawn_spread = 0.05, vy_offset = -0.3,
		size_min = 2, size_range = 3, lifetime_min = 0.3, lifetime_range = 0.2,
		color = "#FFFFFF",
	},
}

--- Factory: Creates sparkle/burst particles when collecting an item
---@param x number X position in tile coordinates (item center)
---@param y number Y position in tile coordinates (item center)
---@return nil
function Effects.create_collect_particles(x, y)
	for i = 1, #collect_layers do
		spawn_particle_ring(x, y, collect_layers[i])
	end
end

--- Factory: Creates a flying object effect for boss defeat sequences.
--- The object flies from start to target position with optional spin.
---@param start_x number Start X position in tile coordinates
---@param start_y number Start Y position in tile coordinates
---@param target_x number Target X position in tile coordinates
---@param target_y number Target Y position in tile coordinates
---@param opts table Options: sprite (required), sprite_size (default 16), flight_duration (default 1.5), rotations (default 3), on_complete (callback)
---@return table Flying object instance
function Effects.create_flying_object(start_x, start_y, target_x, target_y, opts)
	local rotations = opts.rotations or 3
	local two_pi = math.pi * 2
	local end_rotation = rotations * two_pi

	local obj = {
		x = start_x,
		y = start_y,
		start_x = start_x,
		start_y = start_y,
		target_x = target_x,
		target_y = target_y,
		rotation = 0,
		start_rotation = 0,
		end_rotation = end_rotation,
		elapsed = 0,
		phase = "flying",
		sprite = opts.sprite,
		sprite_size = opts.sprite_size or 16,
		flight_duration = opts.flight_duration or 1.5,
		on_complete = opts.on_complete,
	}

	state.flying_objects[obj] = true
	return obj
end

--- Factory: Creates a flying axe effect for boss defeat sequences.
--- Convenience wrapper around create_flying_object for the gnomo boss.
---@param start_x number Start X position in tile coordinates
---@param start_y number Start Y position in tile coordinates
---@param target_x number Target X position in tile coordinates
---@param target_y number Target Y position in tile coordinates
---@param on_complete function|nil Callback when axe arrives
---@return table Flying object instance
function Effects.create_flying_axe(start_x, start_y, target_x, target_y, on_complete)
	return Effects.create_flying_object(start_x, start_y, target_x, target_y, {
		sprite = sprites_items.axe_icon,
		on_complete = on_complete,
	})
end

--- Clears all effects (for level reloading)
---@return nil
function Effects.clear()
	for k in pairs(state.all) do state.all[k] = nil end
	for k in pairs(state.damage_texts) do state.damage_texts[k] = nil end
	for k in pairs(state.status_texts) do state.status_texts[k] = nil end
	for k in pairs(state.fatigue_particles) do state.fatigue_particles[k] = nil end
	for k in pairs(state.collect_particles) do state.collect_particles[k] = nil end
	for k in pairs(state.heal_particles) do state.heal_particles[k] = nil end
	for k in pairs(state.flying_objects) do state.flying_objects[k] = nil end
	state.active_xp_text = nil
	state.active_gold_text = nil
	state.active_heal_text = nil
	state.active_hp_loot_text = nil
	state.active_energy_loot_text = nil
end

return Effects
