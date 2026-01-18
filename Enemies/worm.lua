local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

local worm = {}

worm.animations = {
	RUN = Animation.create_definition(sprites.enemies.worm.run, 5, {
		ms_per_frame = 200,
		width = 16,
		height = 8,
		loop = true
	}),
	DEATH = Animation.create_definition(sprites.enemies.worm.death, 6, {
		width = 16,
		height = 8,
		loop = false
	}),
}

worm.states = {}

worm.states.run = {
	name = "run",
	start = function(enemy, definition)
		enemy.animation = Animation.new(worm.animations.RUN, { flipped = enemy.direction })
		enemy.run_speed = 0.5
	end,
	update = function(enemy, dt)
		enemy.vx = enemy.direction * enemy.run_speed
		if common.is_blocked(enemy) then
			common.reverse_direction(enemy)
		end
	end,
	draw = common.draw
}

worm.states.death = common.create_death_state(worm.animations.DEATH)

return {
	box = { w = 0.9, h = 0.45, x = 0.05, y = 0.05 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 1,
	damage = 1,
	states = worm.states,
	animations = worm.animations,
	initial_state = "run",
	-- rotate_to_slope = true,
}
