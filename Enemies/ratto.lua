local Animation = require('Animation')
local common = require('Enemies/common')

local ratto = {}

ratto.animations = {
	IDLE = Animation.create_definition("ratto_idle", 6, {
		ms_per_frame = 200,
		width = 16,
		height = 8,
		loop = true
	}),
	RUN = Animation.create_definition("ratto_run", 4, {
		width = 16,
		height = 8,
		loop = true
	}),
	HIT = Animation.create_definition("ratto_hit", 5, {
		width = 16,
		height = 8,
		loop = false
	}),
	DEATH = Animation.create_definition("ratto_death", 13, {
		width = 16,
		height = 8,
		loop = false
	}),
}

local function player_in_range(enemy, range)
	if not enemy.target_player then return false end
	local dx = enemy.target_player.x - enemy.x
	local dy = enemy.target_player.y - enemy.y
	local dist = math.sqrt(dx * dx + dy * dy)
	return dist <= range
end

local function direction_to_player(enemy)
	if not enemy.target_player then return enemy.direction end
	return enemy.target_player.x < enemy.x and -1 or 1
end

ratto.states = {}

ratto.states.idle = {
	name = "idle",
	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.IDLE, { flipped = enemy.direction })
		enemy.vx = 0
		enemy.idle_timer = 2.0
	end,
	update = function(enemy, dt)
		if player_in_range(enemy, 5) then
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
	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.RUN, { flipped = enemy.direction })
		enemy.run_timer = 2.0
		enemy.run_speed = 3
	end,
	update = function(enemy, dt)
		if player_in_range(enemy, 5) then
			enemy:set_state(ratto.states.chase)
			return
		end

		enemy.vx = enemy.direction * enemy.run_speed

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
	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.RUN, { flipped = enemy.direction })
		enemy.chase_speed = 6
		enemy.overshoot_timer = nil
		enemy.direction = direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction
	end,
	update = function(enemy, dt)
		enemy.vx = enemy.direction * enemy.chase_speed

		if common.is_blocked(enemy) then
			common.reverse_direction(enemy)
			enemy.retreat_timer = 1.0
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
			local dir_to_player = direction_to_player(enemy)
			if dir_to_player ~= enemy.direction then
				enemy.overshoot_timer = 1.0
			end
		end
	end,
	draw = common.draw,
}

ratto.states.hit = {
	name = "hit",
	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.HIT, { flipped = enemy.direction })
		local knockback_speed = 12
		enemy.vx = (enemy.hit_direction or -1) * knockback_speed
		enemy.vy = -5
	end,
	update = function(enemy, dt)
		enemy.vx = enemy.vx * 0.9
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
	max_health = 5,
	damage = 1,
	states = ratto.states,
	animations = ratto.animations,
}
