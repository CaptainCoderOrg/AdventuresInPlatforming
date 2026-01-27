local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

--- Ratto enemy: A rat that patrols and chases the player.
--- States: idle (wait), run (patrol), chase (pursue player), hit, death
--- Detection range: 5 tiles. Health: 3 HP. Contact damage: 1.
local ratto = {}

local DETECTION_RANGE = 5
local IDLE_DURATION = 2.0
local RUN_DURATION = 2.0
local RUN_SPEED = 3
local CHASE_SPEED = 6
local RETREAT_DURATION = 1.0
local OVERSHOOT_DURATION = 1.0
local HIT_KNOCKBACK = 12
local HIT_JUMP = -5

ratto.animations = {
	IDLE = Animation.create_definition(sprites.enemies.ratto.idle, 6, {
		ms_per_frame = 200,
		width = 16,
		height = 8,
		loop = true
	}),
	RUN = Animation.create_definition(sprites.enemies.ratto.run, 4, {
		width = 16,
		height = 8,
		loop = true
	}),
	HIT = Animation.create_definition(sprites.enemies.ratto.hit, 5, {
		width = 16,
		height = 8,
		loop = false
	}),
	DEATH = Animation.create_definition(sprites.enemies.ratto.death, 13, {
		width = 16,
		height = 8,
		loop = false
	}),
}

ratto.states = {}

ratto.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, ratto.animations.IDLE)
		enemy.vx = 0
		enemy.idle_timer = IDLE_DURATION
	end,
	update = function(enemy, dt)
		if common.player_in_range(enemy, DETECTION_RANGE) then
			enemy:set_state(ratto.states.chase)
			return
		end

		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			enemy.direction = math.random() < 0.5 and -1 or 1
			enemy:set_state(ratto.states.run)
		end
	end,
	draw = common.draw,
}

ratto.states.run = {
	name = "run",
	start = function(enemy, _)
		common.set_animation(enemy, ratto.animations.RUN)
		enemy.run_timer = RUN_DURATION
	end,
	update = function(enemy, dt)
		if common.player_in_range(enemy, DETECTION_RANGE) then
			enemy:set_state(ratto.states.chase)
			return
		end

		enemy.vx = enemy.direction * RUN_SPEED

		if common.is_blocked(enemy) then
			common.reverse_direction(enemy)
		end

		enemy.run_timer = enemy.run_timer - dt
		if enemy.run_timer <= 0 then
			enemy:set_state(ratto.states.idle)
		end
	end,
	draw = common.draw,
}

ratto.states.chase = {
	name = "chase",
	start = function(enemy, _)
		common.set_animation(enemy, ratto.animations.RUN)
		enemy.overshoot_timer = nil
		enemy.retreat_timer = nil
		enemy.direction = common.direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction
	end,
	update = function(enemy, dt)
		enemy.vx = enemy.direction * CHASE_SPEED

		if common.is_blocked(enemy) then
			common.reverse_direction(enemy)
			enemy.retreat_timer = RETREAT_DURATION
		end

		if enemy.retreat_timer then
			enemy.retreat_timer = enemy.retreat_timer - dt
			if enemy.retreat_timer <= 0 then
				enemy.retreat_timer = nil
				enemy:set_state(ratto.states.idle)
			end
			return
		end

		if enemy.overshoot_timer then
			enemy.overshoot_timer = enemy.overshoot_timer - dt
			if enemy.overshoot_timer <= 0 then
				enemy:set_state(ratto.states.idle)
			end
		else
			local dir_to_player = common.direction_to_player(enemy)
			if dir_to_player ~= enemy.direction then
				enemy.overshoot_timer = OVERSHOOT_DURATION
			end
		end
	end,
	draw = common.draw,
}

ratto.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, ratto.animations.HIT)
		enemy.vx = (enemy.hit_direction or -1) * HIT_KNOCKBACK
		enemy.vy = HIT_JUMP
	end,
	update = function(enemy, dt)
		enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
		if enemy.animation:is_finished() then
			enemy:set_state(ratto.states.idle)
		end
	end,
	draw = common.draw,
}

ratto.states.death = common.create_death_state(ratto.animations.DEATH)

return {
	box = { w = 0.9, h = 0.45, x = 0.05, y = 0.05 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 3,
	damage = 1,
	damages_shield = true,  -- Contact damage triggers shield stamina drain
	death_sound = "ratto",
	loot = { xp = 3, gold = { min = 0, max = 5 } },
	states = ratto.states,
	animations = ratto.animations,
	initial_state = "idle",
}
