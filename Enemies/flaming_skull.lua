local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')
local canvas = require('canvas')
local common = require('Enemies/common')
local world = require('world')
local Effects = require('Effects')
local audio = require('audio')

--- Flaming Skull enemy: A bouncing flying skull that deals damage and drains energy on contact.
--- States: float (bounces off walls/floors/bridges), hit (stunned briefly), death
--- Flying enemy (no gravity). Health: 40 HP. Contact damage: 1 + 1 energy drain.
local flaming_skull = {}

local DEFAULT_SPEED = 2
local BOUNCE_NUDGE = 0.05  -- Escape collision zone to prevent stuck-in-surface

-- Pre-calculate scaled dimensions for manual canvas transforms (custom flip behavior)
local SPRITE_RAW_WIDTH = 18
local SPRITE_RAW_HEIGHT = 26
local SPRITE_WIDTH = SPRITE_RAW_WIDTH * config.ui.SCALE
local SPRITE_HEIGHT = SPRITE_RAW_HEIGHT * config.ui.SCALE

flaming_skull.animations = {
	FLOAT = Animation.create_definition(sprites.enemies.flaming_skull.float, 8, {
		ms_per_frame = 100, width = 18, height = 26, loop = true
	}),
	HIT = Animation.create_definition(sprites.enemies.flaming_skull.hit, 4, {
		ms_per_frame = 100, width = 18, height = 26, loop = false
	}),
	DEATH = Animation.create_definition(sprites.enemies.flaming_skull.death, 7, {
		ms_per_frame = 100, width = 18, height = 26, loop = false
	}),
}

--- Custom draw function to handle 18px sprite alignment when flipped.
--- Uses manual canvas transforms like guardian.lua for precise control.
---@param enemy table The flaming_skull enemy
local function draw(enemy)
	if not enemy.animation then return end

	local definition = enemy.animation.definition
	local frame = enemy.animation.frame
	local x = sprites.px(enemy.x)
	local y = sprites.stable_y(enemy, enemy.y, 0)

	canvas.save()

	if enemy.direction == 1 then
		-- Facing right: flip sprite around its right edge so character stays at x
		canvas.translate(x + SPRITE_WIDTH, y)
		canvas.scale(-1, 1)
	else
		-- Facing left: draw normally at position
		canvas.translate(x, y)
	end

	canvas.draw_image(definition.name, 0, 0,
		SPRITE_WIDTH, SPRITE_HEIGHT,
		frame * definition.width, 0,
		definition.width, definition.height)
	canvas.restore()
end

-- Direction lookup: maps direction string to {horizontal, vertical} multipliers
-- Negative Y is up in screen coordinates
local DIRECTION_VECTORS = {
	NE = { h = 1, v = -1 },
	SE = { h = 1, v = 1 },
	SW = { h = -1, v = 1 },
	NW = { h = -1, v = -1 },
}

--- Initialize velocity based on direction property or default (NE).
--- Vertical speed is half of horizontal speed for a flatter trajectory.
---@param enemy table The flaming_skull enemy
local function init_velocity(enemy)
	local speed = enemy.speed or DEFAULT_SPEED
	local dir_key = enemy.start_direction or "NE"
	local dir = DIRECTION_VECTORS[dir_key] or DIRECTION_VECTORS.NE

	enemy.vx = dir.h * speed
	enemy.vy = dir.v * speed * 0.5
	enemy.direction = dir.h
end

flaming_skull.states = {}

flaming_skull.states.float = {
	name = "float",
	--- Initialize float state; sets animation and velocity if not already moving.
	---@param enemy table The flaming_skull enemy instance
	---@param _definition table Unused definition parameter
	start = function(enemy, _definition)
		common.set_animation(enemy, flaming_skull.animations.FLOAT)
		-- Only initialize velocity if not already moving (preserves velocity after hit state)
		if enemy.vx == 0 and enemy.vy == 0 then
			init_velocity(enemy)
		end
		enemy.animation.flipped = enemy.direction
	end,
	--- Move enemy and handle wall/floor/ceiling bouncing.
	---@param enemy table The flaming_skull enemy instance
	---@param dt number Delta time in seconds
	update = function(enemy, dt)
		-- Move and check for collisions
		enemy.x = enemy.x + enemy.vx * dt
		enemy.y = enemy.y + enemy.vy * dt
		local cols = world.move(enemy, enemy._cols)

		-- Bounce on horizontal collision (only if moving into the wall)
		if cols.wall_left and enemy.vx < 0 then
			enemy.vx = -enemy.vx
			enemy.direction = 1
			enemy.animation.flipped = 1
		elseif cols.wall_right and enemy.vx > 0 then
			enemy.vx = -enemy.vx
			enemy.direction = -1
			enemy.animation.flipped = -1
		end

		-- Bounce on vertical collision (only if moving into the surface)
		if (cols.ground or cols.is_bridge) and enemy.vy > 0 then
			enemy.vy = -enemy.vy
			enemy.y = enemy.y - BOUNCE_NUDGE
		elseif cols.ceiling and enemy.vy < 0 then
			enemy.vy = -enemy.vy
			enemy.y = enemy.y + BOUNCE_NUDGE
		end
	end,
	draw = draw,
}

flaming_skull.states.hit = {
	name = "hit",
	---@param enemy table The flaming_skull enemy instance
	---@param _definition table Unused definition parameter
	start = function(enemy, _definition)
		common.set_animation(enemy, flaming_skull.animations.HIT)
		-- Preserve velocity direction but stop movement during stun
		enemy.saved_vx = enemy.vx
		enemy.saved_vy = enemy.vy
		enemy.vx = 0
		enemy.vy = 0
	end,
	---@param enemy table The flaming_skull enemy instance
	---@param _dt number Unused delta time
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			-- Restore velocity and return to float state
			enemy.vx = enemy.saved_vx or 0
			enemy.vy = enemy.saved_vy or 0
			enemy:set_state(flaming_skull.states.float)
		end
	end,
	draw = draw,
}

flaming_skull.states.death = {
	name = "death",
	---@param enemy table The flaming_skull enemy instance
	---@param _definition table Unused definition parameter
	start = function(enemy, _definition)
		common.set_animation(enemy, flaming_skull.animations.DEATH)
		enemy.vx = 0
		enemy.vy = 0
	end,
	---@param enemy table The flaming_skull enemy instance
	---@param _dt number Unused delta time
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,
	draw = draw,
}

--- Custom on_hit handler: enter hit state without knockback.
---@param enemy table The flaming_skull enemy
---@param source_type string "player", "weapon", or "projectile"
---@param source table Hit source
local function on_hit(enemy, source_type, source)
	if enemy.invulnerable then return end

	local damage = (source and source.damage) or 1
	local is_crit = source and source.is_crit

	-- Apply armor reduction, then crit multiplier (minimum 0 damage)
	damage = math.max(0, damage - enemy:get_armor())
	if is_crit then
		damage = damage * 2
	end

	-- Create floating damage text (centered on enemy hitbox)
	Effects.create_damage_text(enemy.x + enemy.box.x + enemy.box.w / 2, enemy.y, damage, is_crit)

	if damage <= 0 then
		audio.play_solid_sound()
		return
	end

	enemy.health = enemy.health - damage
	audio.play_squish_sound()

	if enemy.health <= 0 then
		enemy:die()
	elseif (source_type == "projectile" or source_type == "weapon") and enemy.states.hit then
		enemy:set_state(enemy.states.hit)
	end
end

return {
	on_hit = on_hit,
	-- Hitbox: 11x11 pixels = 0.6875 x 0.6875 tiles
	-- Sprite: 18x26 pixels = 1.125 x 1.625 tiles
	-- X offset: (18-11)/2 = 3.5px = 0.21875 tiles
	-- Y offset: 26-11-4 = 11px from top = 0.6875 tiles
	box = { w = 0.6875, h = 0.6875, x = 0.21875, y = 0.6875 },
	gravity = 0,
	max_fall_speed = 0,
	max_health = 40,
	damage = 1,
	energy_drain = 1,  -- Drains 1 energy on contact
	damages_shield = true,
	death_sound = "ratto",
	loot = { xp = 50 },
	states = flaming_skull.states,
	animations = flaming_skull.animations,
	initial_state = "float",
}
