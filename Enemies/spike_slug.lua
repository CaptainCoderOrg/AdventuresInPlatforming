local Animation = require('Animation')
local common = require('Enemies/common')

local spike_slug = {}

spike_slug.animations = {
	RUN = Animation.create_definition("spikeslug_run", 4, { width = 16, height = 16, loop = true }),
	HIT = Animation.create_definition("spikeslug_hit", 5, { width = 16, height = 16, loop = false }),
	DEFENSE = Animation.create_definition("spikeslug_defense", 6, { width = 16, height = 16, loop = false }),
	STOP_DEFEND = Animation.create_definition("spikeslug_stop_defend", 6, { width = 16, height = 16, loop = false }),
	DEATH = Animation.create_definition("spikeslug_death", 6, { width = 16, height = 16, loop = false }),
}

spike_slug.states = {}

spike_slug.states.run = {
	name = "run",
	start = function(enemy, def)
		enemy.animation = Animation.new(spike_slug.animations.RUN, { flipped = enemy.direction })
		enemy.run_speed = 1.5
		enemy.is_defending = false
	end,
	update = function(enemy, dt)
		if common.player_in_range(enemy, 6) then
			enemy:set_state(spike_slug.states.defend)
			return
		end
		enemy.vx = enemy.direction * enemy.run_speed
		if common.is_blocked(enemy) then
			common.reverse_direction(enemy)
		end
	end,
	draw = common.draw
}

spike_slug.states.defend = {
	name = "defend",
	start = function(enemy, def)
		enemy.animation = Animation.new(spike_slug.animations.DEFENSE, { flipped = enemy.direction })
		enemy.vx = 0
		enemy.is_defending = true
	end,
	update = function(enemy, dt)
		if not common.player_in_range(enemy, 6) then
			enemy:set_state(spike_slug.states.stop_defend)
		end
	end,
	draw = common.draw
}

spike_slug.states.stop_defend = {
	name = "stop_defend",
	start = function(enemy, def)
		enemy.animation = Animation.new(spike_slug.animations.STOP_DEFEND, { flipped = enemy.direction })
		enemy.vx = 0
		enemy.is_defending = false
	end,
	update = function(enemy, dt)
		if enemy.animation:is_finished() then
			enemy:set_state(spike_slug.states.run)
		end
	end,
	draw = common.draw
}

spike_slug.states.hit = {
	name = "hit",
	start = function(enemy, def)
		enemy.animation = Animation.new(spike_slug.animations.HIT, { flipped = enemy.direction })
		enemy.vx = (enemy.hit_direction or -1) * 8
		enemy.vy = -3
		enemy.is_defending = false
	end,
	update = function(enemy, dt)
		enemy.vx = enemy.vx * 0.9
		if enemy.animation:is_finished() then
			enemy:set_state(spike_slug.states.run)
		end
	end,
	draw = common.draw
}

spike_slug.states.death = common.create_death_state(spike_slug.animations.DEATH)

return {
	box = { w = 0.9, h = 0.9, x = 0.05, y = 0.05 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 3,
	damage = 1,
	states = spike_slug.states,
	animations = spike_slug.animations,
	initial_state = "run",
}
