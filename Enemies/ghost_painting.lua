local Animation = require('Animation')
local sprites = require('sprites')
local canvas = require('canvas')
local common = require('Enemies/common')
local audio = require('audio')

--- Ghost Painting enemy: A haunted painting that attacks when player looks away.
--- States: idle (wait for player), wait (player in range), prep_attack (wind up),
---         attack (fly toward player), reappear (teleport and fade in), hit, death
--- Flying enemy (no gravity). Health: 4 HP. Damage: 2 (only in prep_attack/attack).
local ghost_painting = {}

local DETECTION_RANGE = 3           -- Tiles
local PREP_DURATION = 1.0           -- Seconds
local SHAKE_FREQUENCY = 30          -- Hz
local SHAKE_AMPLITUDE = 0.4         -- Tiles
local FLOAT_SPEED = 1.5             -- Tiles/sec upward
local ATTACK_ACCELERATION = 40      -- Tiles/sec^2
local MAX_ATTACK_SPEED = 25         -- Tiles/sec
local MAX_ATTACK_SPEED_SQ = MAX_ATTACK_SPEED * MAX_ATTACK_SPEED  -- Pre-computed for perf
local OFFSCREEN_MARGIN = 2          -- Tiles beyond camera
local REAPPEAR_DISTANCE = 6         -- Tiles from player
local FADE_IN_DURATION = 1.5        -- Seconds
local FADE_OUT_DURATION = 0.75      -- Seconds (faster than fade in)
local FADE_OUT_SPEED = 2            -- Tiles/sec (slow drift while fading)

ghost_painting.animations = {
	STATIC = Animation.create_definition(sprites.enemies.ghost_painting.static, 1, {
		width = 16, height = 24, loop = false
	}),
	FLY = Animation.create_definition(sprites.enemies.ghost_painting.fly, 10, {
		ms_per_frame = 80, width = 16, height = 24, loop = true
	}),
	HIT = Animation.create_definition(sprites.enemies.ghost_painting.hit, 2, {
		ms_per_frame = 100, width = 16, height = 24, loop = false
	}),
	DEATH = Animation.create_definition(sprites.enemies.ghost_painting.death, 6, {
		ms_per_frame = 100, width = 16, height = 24, loop = false
	}),
}

--- Check if player is facing toward the enemy
---@param enemy table The ghost_painting enemy
---@return boolean True if player is looking at enemy
local function player_facing_enemy(enemy)
	if not enemy.target_player then return false end
	local dx = enemy.x - enemy.target_player.x
	return dx * enemy.target_player.direction > 0
end

--- Check if enemy is off-screen by the specified margin
---@param enemy table The ghost_painting enemy
---@return boolean True if enemy is off-screen
local function is_offscreen(enemy)
	if not enemy.camera then return false end
	local min_x, min_y, max_x, max_y = enemy.camera:get_visible_bounds(sprites.tile_size, 0)
	local ex = enemy.x + enemy.box.x + enemy.box.w / 2
	local ey = enemy.y + enemy.box.y + enemy.box.h / 2
	return ex < min_x - OFFSCREEN_MARGIN or ex > max_x + OFFSCREEN_MARGIN or
	       ey < min_y - OFFSCREEN_MARGIN or ey > max_y + OFFSCREEN_MARGIN
end

--- Draw with alpha support for fade-in effect
---@param enemy table The ghost_painting enemy
local function draw_with_alpha(enemy)
	if not enemy.animation then return end

	local alpha = enemy.alpha or 1
	canvas.set_global_alpha(alpha)
	common.draw(enemy)
	canvas.set_global_alpha(1)
end

--- Draw function for prep_attack state with shake effect
---@param enemy table The ghost_painting enemy
local function draw_prep_attack(enemy)
	if not enemy.animation then return end

	local shake_offset = enemy.shake_offset or 0
	local original_x = enemy.x
	enemy.x = enemy.x + shake_offset
	common.draw(enemy)
	enemy.x = original_x
end

ghost_painting.states = {}

ghost_painting.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.STATIC)
		enemy.vx = 0
		enemy.vy = 0
		enemy.damage = 0
		enemy.alpha = 1
	end,
	update = function(enemy, _dt)
		if common.player_in_range(enemy, DETECTION_RANGE) then
			enemy:set_state(ghost_painting.states.wait)
		end
	end,
	draw = common.draw,
}

ghost_painting.states.wait = {
	name = "wait",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.STATIC)
		enemy.vx = 0
		enemy.vy = 0
		enemy.damage = 0
	end,
	update = function(enemy, _dt)
		-- Stay in wait state while player is within detection range
		if common.player_in_range(enemy, DETECTION_RANGE) then return end

		-- Player left detection range - attack if they're not looking, otherwise return to idle
		if not player_facing_enemy(enemy) then
			enemy:set_state(ghost_painting.states.prep_attack)
		else
			enemy:set_state(ghost_painting.states.idle)
		end
	end,
	draw = common.draw,
}

ghost_painting.states.prep_attack = {
	name = "prep_attack",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.STATIC)
		enemy.prep_timer = 0
		enemy.vx = 0
		enemy.vy = -FLOAT_SPEED
		enemy.damage = 1
	end,
	update = function(enemy, dt)
		enemy.prep_timer = enemy.prep_timer + dt
		enemy.shake_offset = math.sin(enemy.prep_timer * SHAKE_FREQUENCY * 2 * math.pi) * SHAKE_AMPLITUDE

		if enemy.prep_timer >= PREP_DURATION then
			enemy:set_state(ghost_painting.states.attack)
		end
	end,
	draw = draw_prep_attack,
}

ghost_painting.states.attack = {
	name = "attack",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.FLY)
		enemy.damage = 1
		enemy.attack_vx = 0
		enemy.attack_vy = 0
		enemy.attack_dir_x = 0
		enemy.attack_dir_y = 1  -- Default: fly downward if no target

		if not enemy.target_player then return end

		local dx = enemy.target_player.x - enemy.x
		local dy = enemy.target_player.y - enemy.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist > 0 then
			enemy.attack_dir_x = dx / dist
			enemy.attack_dir_y = dy / dist
		end
		enemy.direction = common.direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction
	end,
	update = function(enemy, dt)
		-- Blocked by shield - fade out and reappear
		if enemy.hit_shield then
			enemy:set_state(ghost_painting.states.fade_out)
			return
		end

		enemy.attack_vx = enemy.attack_vx + enemy.attack_dir_x * ATTACK_ACCELERATION * dt
		enemy.attack_vy = enemy.attack_vy + enemy.attack_dir_y * ATTACK_ACCELERATION * dt

		local speed_sq = enemy.attack_vx * enemy.attack_vx + enemy.attack_vy * enemy.attack_vy
		if speed_sq > MAX_ATTACK_SPEED_SQ then
			local scale = MAX_ATTACK_SPEED / math.sqrt(speed_sq)
			enemy.attack_vx = enemy.attack_vx * scale
			enemy.attack_vy = enemy.attack_vy * scale
		end

		enemy.vx = enemy.attack_vx
		enemy.vy = enemy.attack_vy

		if is_offscreen(enemy) then
			enemy:set_state(ghost_painting.states.reappear)
		end
	end,
	draw = common.draw,
}

ghost_painting.states.reappear = {
	name = "reappear",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.STATIC)
		enemy.vx = 0
		enemy.vy = 0
		enemy.damage = 0
		enemy.alpha = 0
		enemy.fade_timer = 0

		if enemy.target_player and enemy.camera then
			local angle = math.random() * 2 * math.pi
			local new_x = enemy.target_player.x + math.cos(angle) * REAPPEAR_DISTANCE
			local new_y = enemy.target_player.y + math.sin(angle) * REAPPEAR_DISTANCE

			-- Clamp to camera visible bounds to ensure ghost appears on screen
			local min_x, min_y, max_x, max_y = enemy.camera:get_visible_bounds(sprites.tile_size, -1)
			enemy.x = math.max(min_x + 1, math.min(max_x - 1, new_x))
			enemy.y = math.max(min_y + 1, math.min(max_y - 1, new_y))

			enemy.direction = common.direction_to_player(enemy)
			enemy.animation.flipped = enemy.direction
		end
	end,
	update = function(enemy, dt)
		enemy.fade_timer = enemy.fade_timer + dt
		enemy.alpha = math.min(1, enemy.fade_timer / FADE_IN_DURATION)

		if enemy.alpha >= 1 then
			enemy:set_state(ghost_painting.states.attack)
		end
	end,
	draw = draw_with_alpha,
}

ghost_painting.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.HIT)
		enemy.damage = 0
		enemy.alpha = 1
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy:set_state(ghost_painting.states.fade_out)
		end
	end,
	draw = common.draw,
}

ghost_painting.states.fade_out = {
	name = "fade_out",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.STATIC)
		enemy.damage = 0
		enemy.invulnerable = true
		enemy.fade_timer = 0

		-- Slow down but keep moving in same direction
		local speed = math.sqrt(enemy.vx * enemy.vx + enemy.vy * enemy.vy)
		if speed > 0 then
			enemy.vx = (enemy.vx / speed) * FADE_OUT_SPEED
			enemy.vy = (enemy.vy / speed) * FADE_OUT_SPEED
		end
	end,
	update = function(enemy, dt)
		enemy.fade_timer = enemy.fade_timer + dt
		enemy.alpha = math.max(0, 1 - enemy.fade_timer / FADE_OUT_DURATION)

		if enemy.alpha <= 0 then
			enemy.invulnerable = false
			enemy:set_state(ghost_painting.states.reappear)
		end
	end,
	draw = draw_with_alpha,
}

ghost_painting.states.death = {
	name = "death",
	start = function(enemy, _)
		common.set_animation(enemy, ghost_painting.animations.DEATH)
		enemy.vx = 0
		enemy.vy = 0
		enemy.damage = 0
		enemy.alpha = 1
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,
	draw = common.draw,
}

--- Called when ghost painting contacts the player and deals damage.
--- Ghost loses 1 HP per hit as self-damage.
---@param self table The ghost_painting enemy
local function on_damage_player(self)
	self.health = self.health - 1
	audio.play_squish_sound()
	if self.health <= 0 then
		self:die()
	end
end

--- Called when player performs a perfect block against ghost_painting's attack.
--- Ghost painting is instantly killed by perfect blocks.
---@param enemy table The ghost_painting enemy
---@param _player table The player who perfect blocked
local function on_perfect_blocked(enemy, _player)
	enemy:die()
end

return {
	on_damage_player = on_damage_player,
	on_perfect_blocked = on_perfect_blocked,
	box = { w = 0.75, h = 1.25, x = 0.125, y = 0.25 },
	spawn_offset = { y = -0.5 },  -- -8 pixels to match decoy_painting
	gravity = 0,
	max_fall_speed = 0,
	max_health = 2,
	armor = 0,
	damage = 0,
	damages_shield = true,
	directional_shield = true,  -- Uses direction-based shield check (phases through walls)
	death_sound = "ratto",
	loot = { xp = 20, gold = { min = 6, max = 24 } },
	states = ghost_painting.states,
	animations = ghost_painting.animations,
	initial_state = "idle",
}
