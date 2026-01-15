local Animation = require('Animation')
local sprites = require('sprites')

local ratto = {}

ratto.animations = {
	IDLE = Animation.create_definition("ratto_idle", 6, {
		ms_per_frame = 200,
		width = 16,
		height = 8,
		loop = true
	}),
	RUN = Animation.create_definition("ratto_run", 4, {
		ms_per_frame = 100,
		width = 16,
		height = 8,
		loop = true
	}),
	HIT = Animation.create_definition("ratto_hit", 5, {
		ms_per_frame = 80,
		width = 16,
		height = 8,
		loop = false
	}),
	DEATH = Animation.create_definition("ratto_death", 13, {
		ms_per_frame = 100,
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
		enemy.animation = Animation.new(ratto.animations.IDLE, {
			flipped = enemy.direction
		})
		enemy.vx = 0
		enemy.idle_timer = 2.0  -- Wait 2 seconds before running
	end,

	update = function(enemy, dt)
		-- Check for player in range
		if player_in_range(enemy, 5) then
			enemy:set_state(ratto.states.chase)
			return
		end

		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			-- Pick random direction and switch to run
			enemy.direction = math.random() < 0.5 and -1 or 1
			enemy:set_state(ratto.states.run)
		end
	end,

	draw = function(enemy)
		if enemy.animation then
			enemy.animation:draw(
				enemy.x * sprites.tile_size,
				enemy.y * sprites.tile_size
			)
		end
	end,
}

ratto.states.run = {
	name = "run",

	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.RUN, {
			flipped = enemy.direction
		})
		enemy.run_timer = 2.0  -- Run for 2 seconds
		enemy.run_speed = 3    -- Movement speed
	end,

	update = function(enemy, dt)
		-- Check for player in range
		if player_in_range(enemy, 5) then
			enemy:set_state(ratto.states.chase)
			return
		end

		-- Move in current direction
		enemy.vx = enemy.direction * enemy.run_speed

		-- Check for wall collision and turn around
		if (enemy.direction == -1 and enemy.wall_left) or
		   (enemy.direction == 1 and enemy.wall_right) then
			enemy.direction = -enemy.direction
			enemy.animation.flipped = enemy.direction
		end

		-- Timer countdown
		enemy.run_timer = enemy.run_timer - dt
		if enemy.run_timer <= 0 then
			enemy:set_state(ratto.states.idle)
		end
	end,

	draw = function(enemy)
		if enemy.animation then
			enemy.animation:draw(
				enemy.x * sprites.tile_size,
				enemy.y * sprites.tile_size
			)
		end
	end,
}

ratto.states.chase = {
	name = "chase",

	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.RUN, {
			flipped = enemy.direction
		})
		enemy.chase_speed = 6  -- Faster than normal run
		enemy.overshoot_timer = nil  -- Set when we pass the player
		-- Face toward player
		enemy.direction = direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction
	end,

	update = function(enemy, dt)
		-- Move in current direction
		enemy.vx = enemy.direction * enemy.chase_speed

		-- Check for wall collision - return to random search
		if (enemy.direction == -1 and enemy.wall_left) or
		   (enemy.direction == 1 and enemy.wall_right) then
			enemy.direction = -enemy.direction
			enemy:set_state(ratto.states.idle)
			return
		end

		-- Check if we're in overshoot mode
		if enemy.overshoot_timer then
			enemy.overshoot_timer = enemy.overshoot_timer - dt
			if enemy.overshoot_timer <= 0 then
				-- Stop and return to random search
				enemy:set_state(ratto.states.idle)
			end
		else
			-- Check if we passed the player (direction no longer matches)
			local dir_to_player = direction_to_player(enemy)
			if dir_to_player ~= enemy.direction then
				-- Start overshoot timer
				enemy.overshoot_timer = 1.0
			end
		end
	end,

	draw = function(enemy)
		if enemy.animation then
			enemy.animation:draw(
				enemy.x * sprites.tile_size,
				enemy.y * sprites.tile_size
			)
		end
	end,
}

ratto.states.hit = {
	name = "hit",

	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.HIT, {
			flipped = enemy.direction
		})
		-- Knockback velocity (set by on_hit before transitioning)
		-- enemy.hit_direction is set by Enemy:on_hit()
		local knockback_speed = 8
		enemy.vx = (enemy.hit_direction or -1) * knockback_speed
		enemy.vy = -5  -- Small upward pop
	end,

	update = function(enemy, dt)
		-- Apply friction to knockback
		enemy.vx = enemy.vx * 0.9

		-- Return to idle when animation finishes
		if enemy.animation:is_finished() then
			enemy:set_state(ratto.states.idle)
		end
	end,

	draw = function(enemy)
		if enemy.animation then
			enemy.animation:draw(
				enemy.x * sprites.tile_size,
				enemy.y * sprites.tile_size
			)
		end
	end,
}

ratto.states.death = {
	name = "death",

	start = function(enemy, definition)
		enemy.animation = Animation.new(ratto.animations.DEATH, {
			flipped = enemy.direction
		})
		-- Keep some knockback momentum
		enemy.vx = (enemy.hit_direction or -1) * 4
		enemy.vy = 0
		-- Disable gravity so it doesn't fall off screen
		enemy.gravity = 0
	end,

	update = function(enemy, dt)
		-- Apply friction
		enemy.vx = enemy.vx * 0.9

		-- Mark for destruction when animation finishes
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,

	draw = function(enemy)
		if enemy.animation then
			enemy.animation:draw(
				enemy.x * sprites.tile_size,
				enemy.y * sprites.tile_size
			)
		end
	end,
}

local definition = {
	-- 16x8 sprite = 1.0 x 0.5 tiles, slightly smaller hitbox
	box = { w = 0.9, h = 0.45, x = 0.05, y = 0.05 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 5,
	damage = 1,
	states = ratto.states,
	animations = ratto.animations,
}

return definition
