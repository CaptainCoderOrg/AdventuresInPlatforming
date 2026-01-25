local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

--- Spike Slug enemy: A defensive enemy that curls up when player approaches.
--- States: run (patrol), defend (invincible stance), stop_defend (exit stance), hit, death
--- Detection range: 6 tiles. Health: 3 HP. Contact damage: 1.
--- Special: is_defending flag blocks all damage while in defend state.
local spike_slug = {}

spike_slug.animations = {
	RUN = Animation.create_definition(sprites.enemies.spikeslug.run, 4, { ms_per_frame = 200, width = 16, height = 16, loop = true }),
	HIT = Animation.create_definition(sprites.enemies.spikeslug.hit, 5, { ms_per_frame = 200, width = 16, height = 16, loop = false }),
	DEFENSE = Animation.create_definition(sprites.enemies.spikeslug.defense, 6, { ms_per_frame = 200, width = 16, height = 16, loop = false }),
	STOP_DEFEND = Animation.create_definition(sprites.enemies.spikeslug.stop_defend, 6, { ms_per_frame = 200, width = 16, height = 16, loop = false }),
	DEATH = Animation.create_definition(sprites.enemies.spikeslug.death, 6, { width = 16, height = 16, loop = false }),
}

spike_slug.states = {}

spike_slug.states.run = {
	name = "run",
	start = function(enemy, def)
		enemy.animation = Animation.new(spike_slug.animations.RUN, { flipped = enemy.direction })
		enemy.run_speed = 1
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
		enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
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
	death_sound = "spike_slug",
	loot = { xp = 5, gold = { min = 0, max = 5 } },
	get_armor = function(self)
		return self.is_defending and 4 or 0
	end,
	states = spike_slug.states,
	animations = spike_slug.animations,
	initial_state = "run",
	rotate_to_slope = true,
}
