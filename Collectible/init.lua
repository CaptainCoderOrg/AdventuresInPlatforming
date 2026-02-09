local canvas = require('canvas')
local sprites = require('sprites')
local state = require('Collectible/state')
local Effects = require('Effects')

local Collectible = {}

-- Physics constants
local FRICTION = 0.92  -- velocity multiplier per frame

-- Collection constants (in tiles)
local COLLECT_RANGE = 0.3  -- tiles
local COLLECT_RANGE_SQ = COLLECT_RANGE * COLLECT_RANGE  -- squared for fast comparison
local HOMING_DELAY = 1.0  -- seconds before particles home to player
local HOMING_SPEED_MIN = 5  -- tiles/second
local HOMING_SPEED_MAX = 16  -- tiles/second
local ACCELERATION = 5

-- Visual constants
local LIFETIME = 10  -- seconds
local FADE_START = 8  -- seconds (fade out in last 2 seconds)
local SIZE = 4  -- pixels

-- Colors
local COLORS = {
	xp = "#FFFFFF",      -- white
	gold = "#FFD700",    -- gold
	health = "#FF4466",  -- red
	energy = "#4488FF",  -- blue
}

local HEALTH_VALUE = 0.1
local ENERGY_VALUE = 0.1

-- Module-level table to avoid allocation each frame
local to_remove = {}

--- Spawns a single collectible particle.
---@param type string "xp" or "gold"
---@param x number X position in tiles
---@param y number Y position in tiles
---@param value number Value of this collectible (usually 1)
---@param velocity table Optional {vx, vy} initial velocity in tiles/second
---@return table The created collectible
function Collectible.spawn(type, x, y, value, velocity)
	velocity = velocity or {}

	local collectible = {
		id = type .. "_" .. state.next_id,
		type = type,
		x = x,
		y = y,
		w = SIZE / sprites.tile_size,  -- Convert to tiles
		h = SIZE / sprites.tile_size,
		vx = velocity.vx or 0,
		vy = velocity.vy or 0,
		value = value or (type == "health" and HEALTH_VALUE or (type == "energy" and ENERGY_VALUE or 1)),
		color = COLORS[type] or COLORS.xp,
		size = SIZE,
		lifetime = LIFETIME,
		elapsed = 0,
		homing_speed = HOMING_SPEED_MIN + math.random() * (HOMING_SPEED_MAX - HOMING_SPEED_MIN)
	}

	state.next_id = state.next_id + 1
	state.all[collectible] = true

	return collectible
end

--- Rotates a 2D vector by an angle (radians)
---@param vx number X component of vector
---@param vy number Y component of vector
---@param angle number Rotation angle in radians
---@return number, number Rotated x and y components
local function rotate_vector(vx, vy, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return vx * c - vy * s, vx * s + vy * c
end

--- Helper: Spawns multiple collectibles with explosion velocity in a cone.
---@param type string "xp" or "gold"
---@param x number X position in tiles
---@param y number Y position in tiles
---@param count number Number of particles to spawn
---@param away_x number Normalized X direction away from player
---@param away_y number Normalized Y direction away from player
local function spawn_explosion(type, x, y, count, away_x, away_y)
	for _ = 1, count do
		local spread = (math.random() - 0.5) * 2.1  -- ~120 degree cone
		local dir_x, dir_y = rotate_vector(away_x, away_y, spread)
		local speed = 4 + math.random() * 2
		Collectible.spawn(type, x, y, nil, {
			vx = dir_x * speed,
			vy = dir_y * speed - 2  -- Slight upward bias
		})
	end
end

--- Spawns loot explosion from enemy death.
--- Particles explode away from the player, then home back after a delay.
---@param x number X position in tiles (enemy center)
---@param y number Y position in tiles (enemy center)
---@param loot_def table Loot definition {xp = number, gold = {min, max}}
---@param player table The player object (for explosion direction)
function Collectible.spawn_loot(x, y, loot_def, player)
	if not loot_def then return end

	-- Calculate direction away from player
	local px, py = player.x + 0.5, player.y + 0.5
	local dx, dy = x - px, y - py
	local dist = math.sqrt(dx * dx + dy * dy)
	local away_x, away_y = 0, -1  -- Default: up if player is exactly on enemy
	if dist > 0.01 then
		away_x, away_y = dx / dist, dy / dist
	end

	-- Spawn XP particles
	local xp_count = loot_def.xp or 0
	if xp_count > 0 then
		spawn_explosion("xp", x, y, xp_count, away_x, away_y)
	end

	-- Spawn gold particles (random amount in range)
	local gold_def = loot_def.gold
	if gold_def then
		local gold_count = math.random(gold_def.min, gold_def.max)
		if gold_count > 0 then
			spawn_explosion("gold", x, y, gold_count, away_x, away_y)
		end
	end

	-- Spawn health particles (only if player has taken damage)
	local health_def = loot_def.health
	if health_def and player.damage and player.damage > 0 then
		local health_count = math.random(health_def.min, health_def.max)
		if health_count > 0 then
			spawn_explosion("health", x, y, health_count, away_x, away_y)
		end
	end

	-- Spawn energy particles (only if player has spent energy)
	local energy_def = loot_def.energy
	if energy_def and player.energy_used and player.energy_used > 0 then
		local energy_count = math.random(energy_def.min, energy_def.max)
		if energy_count > 0 then
			spawn_explosion("energy", x, y, energy_count, away_x, away_y)
		end
	end
end

--- Spawns gold particles exploding upward from a source (chests, etc).
---@param x number X position in tiles (source center)
---@param y number Y position in tiles (source center)
---@param amount number Total gold amount to spawn as particles
function Collectible.spawn_gold_burst(x, y, amount)
	if not amount or amount <= 0 then return end

	for _ = 1, amount do
		-- Spread in upward arc (roughly 180 degree cone pointing up)
		local spread = (math.random() - 0.5) * 3.14  -- -1.57 to 1.57 radians
		local dir_x, dir_y = rotate_vector(0, -1, spread)  -- Base direction: up
		local speed = 3 + math.random() * 3
		local vx = dir_x * speed
		local vy = dir_y * speed - 1  -- Extra upward boost
		Collectible.spawn("gold", x, y, 1, { vx = vx, vy = vy })
	end
end

--- Spawns XP particles in a burst around the player (quest rewards).
--- Particles spawn in all directions for a celebratory effect.
---@param x number Center X position in tiles
---@param y number Center Y position in tiles
---@param amount number Total XP to award (1 particle per XP)
function Collectible.spawn_xp_burst(x, y, amount)
	if not amount or amount <= 0 then return end

	for i = 1, amount do
		-- Spread particles evenly in all directions (360 degree burst)
		local angle = (i / amount) * math.pi * 2
		local speed = 3 + math.random() * 2
		local vx = math.cos(angle) * speed
		local vy = math.sin(angle) * speed - 1  -- Slight upward bias
		Collectible.spawn("xp", x, y, 1, { vx = vx, vy = vy })
	end
end

--- Updates all collectibles: physics, homing, collection.
---@param dt number Delta time in seconds
---@param player table The player object (for collection)
function Collectible.update(dt, player)
	-- Clear module-level table instead of allocating new one
	for i = 1, #to_remove do to_remove[i] = nil end

	local px, py = player.x + 0.5, player.y + 0.5  -- Player center

	local collectible = next(state.all)
	while collectible do
		-- Update elapsed time
		collectible.elapsed = collectible.elapsed + dt

		-- Check lifetime expiry
		if collectible.elapsed >= collectible.lifetime then
			to_remove[#to_remove + 1] = collectible
			collectible = next(state.all, collectible)
			goto continue
		end

		-- Calculate distance to player (squared to avoid sqrt in hot path)
		local cx, cy = collectible.x + collectible.w / 2, collectible.y + collectible.h / 2
		local dx, dy = px - cx, py - cy
		local dist_sq = dx * dx + dy * dy

		-- Collection check (using squared distance)
		-- Only collect after homing phase starts, so explosion animation is always visible
		if collectible.elapsed >= HOMING_DELAY and dist_sq < COLLECT_RANGE_SQ then
			-- Award stats to player
			if collectible.type == "xp" then
				player.experience = (player.experience or 0) + collectible.value
				Effects.create_xp_text(collectible.x, collectible.y, collectible.value, player)
			elseif collectible.type == "gold" then
				player.gold = (player.gold or 0) + collectible.value
				Effects.create_gold_text(collectible.x, collectible.y, collectible.value, player)
			elseif collectible.type == "health" then
				player.damage = math.max(0, player.damage - collectible.value)
				Effects.create_hp_loot_text(collectible.x, collectible.y, collectible.value, player)
			elseif collectible.type == "energy" then
				player.energy_used = math.max(0, player.energy_used - collectible.value)
				Effects.create_energy_loot_text(collectible.x, collectible.y, collectible.value, player)
			end
			to_remove[#to_remove + 1] = collectible
			collectible = next(state.all, collectible)
			goto continue
		end

		-- After delay: move directly toward player
		if collectible.elapsed >= HOMING_DELAY then
			if dist_sq > 0 then
				if collectible.homing_speed < HOMING_SPEED_MAX then
					collectible.homing_speed = collectible.homing_speed + ACCELERATION * dt
				end
				-- Only calculate sqrt when needed for direction normalization
				local dist = math.sqrt(dist_sq)
				local nx, ny = dx / dist, dy / dist
				collectible.x = collectible.x + nx * collectible.homing_speed * dt
				collectible.y = collectible.y + ny * collectible.homing_speed * dt
			end
		else
			-- Explosion phase: apply friction
			collectible.vx = collectible.vx * (FRICTION ^ (dt * 60))
			collectible.vy = collectible.vy * (FRICTION ^ (dt * 60))
			collectible.x = collectible.x + collectible.vx * dt
			collectible.y = collectible.y + collectible.vy * dt
		end

		collectible = next(state.all, collectible)
		::continue::
	end

	-- Remove collected/expired collectibles
	for i = 1, #to_remove do
		state.all[to_remove[i]] = nil
	end
end

--- Draws all collectibles.
function Collectible.draw()
	canvas.save()

	local collectible = next(state.all)
	while collectible do
		local alpha = 1
		if collectible.elapsed > FADE_START then
			alpha = 1 - (collectible.elapsed - FADE_START) / (collectible.lifetime - FADE_START)
		end

		canvas.set_global_alpha(alpha * 0.9)
		canvas.set_fill_style(collectible.color)

		local px = collectible.x * sprites.tile_size
		local py = collectible.y * sprites.tile_size
		canvas.fill_rect(px, py, collectible.size, collectible.size)

		collectible = next(state.all, collectible)
	end

	canvas.set_global_alpha(1)
	canvas.restore()
end

--- Clears all collectibles (for level reloading).
function Collectible.clear()
	for k in pairs(state.all) do state.all[k] = nil end
end

return Collectible
