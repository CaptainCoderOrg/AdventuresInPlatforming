--- Worm enemy: A simple patrol enemy that reverses on obstacles.
--- States: run (patrol), death
--- Health: 1 HP. Contact damage: 1.
local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

local worm = {}

local anim_opts = { flipped = 1 }  -- Reused to avoid allocation

--- Sets up enemy animation, reusing existing instance when possible.
---@param enemy table The enemy instance
---@param definition table Animation definition to use
local function set_animation(enemy, definition)
	anim_opts.flipped = enemy.direction
	if enemy.animation then
		enemy.animation:reinit(definition, anim_opts)
	else
		enemy.animation = Animation.new(definition, anim_opts)
	end
end

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
		set_animation(enemy, worm.animations.RUN)
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
	loot = { xp = 1 },
	states = worm.states,
	animations = worm.animations,
	initial_state = "run",
	-- rotate_to_slope = true,
}
