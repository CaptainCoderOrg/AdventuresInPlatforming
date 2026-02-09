local Animation = require('Animation')
local common = require('Enemies/common')

--- Shared factory for slime enemy variants.
--- Creates slime definitions with configurable behavior and stats.
local slime_common = {}

-- Shared physics constants
local GRAVITY = 1.5
local MAX_FALL_SPEED = 20
local HIT_KNOCKBACK = 8

-- Shared hitbox dimensions (in tiles)
local BOX_WIDTH = 0.875   -- 14px / 16
local BOX_HEIGHT = 0.875  -- 14px / 16
local BOX_X = 0.0625      -- 1px / 16
local BOX_Y = 0.125       -- 2px / 16

--- Create a 16x16 slime animation definition
---@param sprite string Sprite sheet name
---@param frame_count number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@param loop boolean Whether animation loops
---@param frame_offset number|nil Starting frame in spritesheet (default 0)
---@return table Animation definition
local function anim(sprite, frame_count, ms_per_frame, loop, frame_offset)
	return Animation.create_definition(sprite, frame_count, {
		ms_per_frame = ms_per_frame,
		width = 16,
		height = 16,
		loop = loop,
		frame_offset = frame_offset,
	})
end

--- Create animation definitions for a slime variant
---@param sprite_set table Sprite references { idle, jump, hit, death }
---@param prep_jump_ms number Milliseconds per frame for prep_jump animation
---@return table<string, table> animations Map of state names to animation definitions
local function create_animations(sprite_set, prep_jump_ms)
	return {
		IDLE      = anim(sprite_set.idle,  5, 150, true),
		PREP_JUMP = anim(sprite_set.jump,  4, prep_jump_ms, false),
		LAUNCH    = anim(sprite_set.jump,  3, 100, false, 4),
		FALLING   = anim(sprite_set.jump,  4, 100, false, 7),
		LANDING   = anim(sprite_set.jump,  4, 100, false, 11),
		HIT       = anim(sprite_set.hit,   3, 200, false),
		DEATH     = anim(sprite_set.death, 6, 120, false),
	}
end

--- Check if player is within near range on x-axis
---@param enemy table The enemy
---@param range number Detection range in tiles
---@return boolean True if player is nearby
local function is_player_near(enemy, range)
	if not enemy.target_player then return false end
	local dx = math.abs(enemy.target_player.x - enemy.x)
	return dx <= range
end

--- Create state machine for a slime variant
---@param animations table Animation definitions
---@param cfg table Behavior config: wander_speed, jump_horizontal_speed, jump_velocity_min/variance, idle_time_min/variance, move_burst_min/variance, pause_min/variance, player_near_range, near/far_move_toward_chance, near/far_jump_chance
---@return table states State machine table
local function create_states(animations, cfg)
	local states = {}

	states.idle = {
		name = "idle",
		start = function(enemy, _)
			common.set_animation(enemy, animations.IDLE)
			local player_near = is_player_near(enemy, cfg.player_near_range)

			-- Direction bias makes blue slimes evasive and red slimes aggressive
			if enemy.target_player then
				local dir_to_player = common.direction_to_player(enemy)
				if player_near then
					enemy.direction = math.random() < cfg.near_move_toward_chance and dir_to_player or -dir_to_player
				else
					enemy.direction = math.random() < cfg.far_move_toward_chance and dir_to_player or -dir_to_player
				end
			else
				enemy.direction = math.random() < 0.5 and -1 or 1
			end
			enemy.animation.flipped = enemy.direction

			-- Set up sporadic movement
			enemy.idle_timer = cfg.idle_time_min + math.random() * cfg.idle_time_variance
			enemy.is_moving = true
			enemy.move_timer = cfg.move_burst_min + math.random() * cfg.move_burst_variance
			enemy.vx = enemy.direction * cfg.wander_speed
		end,
		update = function(enemy, dt)
			-- Creates organic "hop-pause-hop" wandering behavior
			enemy.move_timer = enemy.move_timer - dt
			if enemy.move_timer <= 0 then
				enemy.is_moving = not enemy.is_moving
				if enemy.is_moving then
					enemy.move_timer = cfg.move_burst_min + math.random() * cfg.move_burst_variance
					enemy.vx = enemy.direction * cfg.wander_speed
				else
					enemy.move_timer = cfg.pause_min + math.random() * cfg.pause_variance
					enemy.vx = 0
				end
			end

			-- Reverse at walls only (slimes walk off ledges)
			local hit_wall = (enemy.direction == -1 and enemy.wall_left) or
			                 (enemy.direction == 1 and enemy.wall_right)
			if enemy.is_moving and hit_wall then
				common.reverse_direction(enemy)
				enemy.vx = enemy.direction * cfg.wander_speed
			end

			enemy.idle_timer = enemy.idle_timer - dt
			if enemy.idle_timer <= 0 then
				local player_near = is_player_near(enemy, cfg.player_near_range)
				local jump_chance = player_near and cfg.near_jump_chance or cfg.far_jump_chance

				if math.random() < jump_chance then
					enemy:set_state(states.prep_jump)
				else
					enemy:set_state(states.idle)
				end
			end
		end,
		draw = common.draw,
	}

	states.prep_jump = {
		name = "prep_jump",
		start = function(enemy, _)
			common.set_animation(enemy, animations.PREP_JUMP)
			enemy.direction = common.direction_to_player(enemy)
			enemy.animation.flipped = enemy.direction
			enemy.vx = 0
		end,
		update = function(enemy, _dt)
			if enemy.animation:is_finished() then
				enemy:set_state(states.launch)
			end
		end,
		draw = common.draw,
	}

	states.launch = {
		name = "launch",
		start = function(enemy, _)
			common.set_animation(enemy, animations.LAUNCH)
			enemy.vy = cfg.jump_velocity_min - math.random() * cfg.jump_velocity_variance
			enemy.vx = enemy.direction * cfg.jump_horizontal_speed
			enemy.gravity = GRAVITY
		end,
		update = function(enemy, _dt)
			if enemy.vy >= 0 then
				enemy:set_state(states.falling)
			end
		end,
		draw = common.draw,
	}

	states.falling = {
		name = "falling",
		start = function(enemy, _)
			common.set_animation(enemy, animations.FALLING)
		end,
		update = function(enemy, _dt)
			if enemy.is_grounded then
				enemy:set_state(states.landing)
			end
		end,
		draw = common.draw,
	}

	states.landing = {
		name = "landing",
		start = function(enemy, _)
			common.set_animation(enemy, animations.LANDING)
			enemy.vx = 0
		end,
		update = function(enemy, _dt)
			if enemy.animation:is_finished() then
				enemy:set_state(states.idle)
			end
		end,
		draw = common.draw,
	}

	states.hit = {
		name = "hit",
		start = function(enemy, _)
			common.set_animation(enemy, animations.HIT)
			enemy.vx = 0
			enemy.vy = 0
		end,
		update = function(enemy, _dt)
			if enemy.animation:is_finished() then
				enemy:set_state(states.knockback)
			end
		end,
		draw = common.draw,
	}

	states.knockback = {
		name = "knockback",
		start = function(enemy, _)
			common.set_animation(enemy, animations.IDLE)
			enemy.vx = (enemy.hit_direction or -1) * HIT_KNOCKBACK
			enemy.vy = -4
		end,
		update = function(enemy, dt)
			enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
			if enemy.is_grounded and math.abs(enemy.vx) < 0.5 then
				enemy:set_state(states.idle)
			end
		end,
		draw = common.draw,
	}

	states.death = common.create_death_state(animations.DEATH)

	return states
end

--- Called when player performs a perfect block against slime's attack.
--- Slimes are instantly killed by perfect blocks.
---@param enemy table The slime enemy
---@param _player table The player who perfect blocked
local function on_perfect_blocked(enemy, _player)
	enemy:die()
end

--- Create a slime enemy definition
---@param sprite_set table Sprite references { idle, jump, hit, death }
---@param cfg table Config: wander_speed, jump_horizontal_speed, jump_velocity_min/variance, idle_time_min/variance, move_burst_min/variance, pause_min/variance, player_near_range, near/far_move_toward_chance, near/far_jump_chance, prep_jump_ms, max_health, contact_damage, loot_xp, loot_gold_min/max
---@return table Enemy definition for registration
function slime_common.create(sprite_set, cfg)
	local animations = create_animations(sprite_set, cfg.prep_jump_ms)
	local states = create_states(animations, cfg)

	return {
		on_perfect_blocked = on_perfect_blocked,
		box = { w = BOX_WIDTH, h = BOX_HEIGHT, x = BOX_X, y = BOX_Y },
		gravity = GRAVITY,
		max_fall_speed = MAX_FALL_SPEED,
		max_health = cfg.max_health,
		damage = cfg.contact_damage,
		damages_shield = true,
		death_sound = "ratto",
		loot = {
			xp = cfg.loot_xp,
			gold = { min = cfg.loot_gold_min, max = cfg.loot_gold_max },
			health = cfg.loot_health_max and { min = cfg.loot_health_min or 0, max = cfg.loot_health_max } or nil,
			energy = cfg.loot_energy_max and { min = cfg.loot_energy_min or 0, max = cfg.loot_energy_max } or nil,
		},
		states = states,
		animations = animations,
		initial_state = "idle",
	}
end

return slime_common
