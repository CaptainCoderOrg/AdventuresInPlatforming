local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

--- Bat Eye enemy: A flying enemy that patrols between two waypoints.
--- States: idle (pause at waypoint), patrol (fly toward waypoint), hit, death
--- No gravity (flying). Health: 3 HP. Contact damage: 1.
local bat_eye = {}

local PATROL_SPEED = 2
local IDLE_DURATION = 1.0

local anim_opts = { flipped = 1 }  -- Reused to avoid allocation

bat_eye.animations = {
	IDLE = Animation.create_definition(sprites.enemies.bat_eye.idle, 6, {
		ms_per_frame = 100
	}),
	HIT = Animation.create_definition(sprites.enemies.bat_eye.hit, 3, {
		ms_per_frame = 100,
		loop = false
	}),
}

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

bat_eye.states = {}

bat_eye.states.idle = {
	name = "idle",
	start = function(enemy, _definition)
		set_animation(enemy, bat_eye.animations.IDLE)
		enemy.vx = 0
		enemy.idle_timer = IDLE_DURATION
		-- Swap target waypoint for next patrol
		if enemy.waypoint_a and enemy.waypoint_b then
			if enemy.target_waypoint == enemy.waypoint_a then
				enemy.target_waypoint = enemy.waypoint_b
			else
				enemy.target_waypoint = enemy.waypoint_a
			end
		end
	end,
	update = function(enemy, dt)
		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			enemy:set_state(bat_eye.states.patrol)
		end
	end,
	draw = common.draw,
}

bat_eye.states.patrol = {
	name = "patrol",
	start = function(enemy, _definition)
		set_animation(enemy, bat_eye.animations.IDLE)
		enemy.arrived_at_waypoint = false
		enemy.last_anim_frame = 0
	end,
	update = function(enemy, _dt)
		if not enemy.target_waypoint then
			enemy:set_state(bat_eye.states.idle)
			return
		end

		-- Wait for animation cycle to complete after arriving
		if enemy.arrived_at_waypoint then
			local current_frame = enemy.animation.frame
			if current_frame < enemy.last_anim_frame then
				enemy:set_state(bat_eye.states.idle)
				return
			end
			enemy.last_anim_frame = current_frame
			return
		end

		local dx = enemy.target_waypoint - enemy.x
		if math.abs(dx) < 0.1 then
			enemy.vx = 0
			enemy.arrived_at_waypoint = true
			enemy.last_anim_frame = enemy.animation.frame
			return
		end

		enemy.direction = dx > 0 and 1 or -1
		enemy.vx = enemy.direction * PATROL_SPEED
		enemy.animation.flipped = enemy.direction
	end,
	draw = common.draw,
}

bat_eye.states.hit = {
	name = "hit",
	start = function(enemy, _definition)
		set_animation(enemy, bat_eye.animations.HIT)
		enemy.vx = 0
		enemy.vy = 0
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy:set_state(bat_eye.states.patrol)
		end
	end,
	draw = common.draw,
}

bat_eye.states.death = {
	name = "death",
	start = function(enemy, _definition)
		set_animation(enemy, bat_eye.animations.HIT)
		enemy.vx = (enemy.hit_direction or -1) * 4
		enemy.gravity = 0.5
		enemy.max_fall_speed = 20  -- Enable falling during death (normally 0 for flying)
	end,
	update = function(enemy, dt)
		enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,
	draw = common.draw,
}

---@return table Enemy definition with box, gravity, states, animations, etc.
return {
	box = { w = 0.5, h = 0.5, x = 0.25, y = 0.25 },  -- 8x8 centered hitbox
	gravity = 0,  -- Flying enemy
	max_fall_speed = 0,
	max_health = 3,
	damage = 1,
	damages_shield = true,
	death_sound = "ratto",  -- Reuse ratto death sound for now
	loot = { xp = 5, gold = { min = 0, max = 5 } },
	states = bat_eye.states,
	animations = bat_eye.animations,
	initial_state = "patrol",
}
