local Animation = require('Animation')
local sprites = require('sprites')
local canvas = require('canvas')
local config = require('config')
local common = require('Enemies/common')
local world = require('world')

--- Bat Eye enemy: A flying enemy that patrols between two waypoints.
--- States: idle (pause at waypoint), patrol (fly toward waypoint), alert, attack, hit, death
--- No gravity (flying). Health: 3 HP. Contact damage: 1.
local bat_eye = {}

local PATROL_SPEED = 4
local IDLE_DURATION = 1.0
local ATTACK_SPEED = 12           -- 4x patrol speed
local DETECTION_RANGE_X = 5      -- horizontal detection range (tiles)
local DETECTION_RANGE_Y = 12      -- vertical detection range (tiles)
local ATTACK_ARRIVAL_THRESHOLD_SQ = 0.3 * 0.3  -- squared tiles for perf
local LOS_CHECK_INTERVAL = 0.1  -- seconds between LOS checks
local STUN_DURATION = 1.0        -- seconds to remain stunned after perfect block
local STUN_GRAVITY = 1.5         -- gravity while falling during stun
local STUN_MAX_FALL_SPEED = 20   -- max fall speed while stunned

bat_eye.animations = {
	IDLE = Animation.create_definition(sprites.enemies.bat_eye.idle, 6),
	ALERT = Animation.create_definition(sprites.enemies.bat_eye.alert, 4, {
		ms_per_frame = 160,
		loop = false
	}),
	ATTACK_START = Animation.create_definition(sprites.enemies.bat_eye.attack_start, 4, { loop = false }),
	ATTACK = Animation.create_definition(sprites.enemies.bat_eye.attack, 3),
	ATTACK_RECOVERY = Animation.create_definition(sprites.enemies.bat_eye.attack_recovery, 3, { loop = false }),
	HIT = Animation.create_definition(sprites.enemies.bat_eye.hit, 3, { loop = false }),
	DEATH = Animation.create_definition(sprites.enemies.bat_eye.death, 6, { loop = false }),
}

--- Check if player can be detected for attack.
--- Player must be: in range, below the bat, in facing direction, and have clear LOS.
--- LOS check is throttled for performance.
---@param enemy table The bat_eye enemy
---@param dt number Delta time for throttling
---@return boolean True if player should trigger alert
local function can_detect_player(enemy, dt)
	if not enemy.target_player then return false end

	local player = enemy.target_player

	-- Check horizontal distance (cheap check first)
	local dx = math.abs(player.x - enemy.x)
	if dx > DETECTION_RANGE_X then return false end

	-- Player must be below the bat and within vertical range
	local dy = player.y - enemy.y
	if dy <= 0 or dy > DETECTION_RANGE_Y then return false end

	-- Player must be in the direction the bat is facing
	local player_dir = player.x > enemy.x and 1 or -1
	if player_dir ~= enemy.direction then return false end

	-- Throttled LOS check (expensive raycast)
	enemy.los_timer = (enemy.los_timer or 0) - dt
	if enemy.los_timer <= 0 then
		enemy.los_timer = LOS_CHECK_INTERVAL
		enemy.cached_los = common.has_line_of_sight(enemy)
	end

	return enemy.cached_los or false
end

--- Draw debug detection zone and raycast line to player.
---@param enemy table The bat_eye enemy
local function draw_debug(enemy)
	local ts = sprites.tile_size
	local box_cx = enemy.box.x + enemy.box.w / 2
	local box_cy = enemy.box.y + enemy.box.h / 2
	local cx = (enemy.x + box_cx) * ts
	local cy = (enemy.y + box_cy) * ts
	local range_x = DETECTION_RANGE_X * ts
	local range_y = DETECTION_RANGE_Y * ts

	-- Draw detection rectangle (below + facing direction)
	local rect_x = enemy.direction == 1 and cx or (cx - range_x)

	canvas.set_color("#FFFF0066")
	canvas.draw_rect(rect_x, cy, range_x, range_y)

	-- Draw boundary lines from center
	canvas.set_color("#FFFF00")
	canvas.draw_line(cx, cy, cx, cy + range_y)
	canvas.draw_line(cx, cy, cx + enemy.direction * range_x, cy)

	-- Draw raycast line to player if in detection zone
	if enemy.target_player then
		local player = enemy.target_player
		local dx = player.x - enemy.x
		local dy = player.y - enemy.y
		local player_dir = dx > 0 and 1 or -1
		local in_facing_dir = player_dir == enemy.direction
		local in_range = math.abs(dx) <= DETECTION_RANGE_X and dy > 0 and dy <= DETECTION_RANGE_Y

		if in_range and in_facing_dir then
			local px = (player.x + player.box.x + player.box.w / 2) * ts
			local py = (player.y + player.box.y + player.box.h / 2) * ts
			canvas.set_color(enemy.cached_los and "#00FF00" or "#FF0000")
			canvas.draw_line(cx, cy, px, py)
		end
	end

	-- Draw attack target during attack states
	if enemy.attack_target_x and enemy.attack_target_y then
		local state_name = enemy.state.name
		if state_name == "attack" or state_name == "attack_start" then
			canvas.set_color("#FF0000")
			local tx = (enemy.attack_target_x + box_cx) * ts
			local ty = (enemy.attack_target_y + box_cy) * ts
			canvas.draw_line(cx, cy, tx, ty)
			local size = 8
			canvas.draw_line(tx - size, ty - size, tx + size, ty + size)
			canvas.draw_line(tx - size, ty + size, tx + size, ty - size)
		end
	end
end

--- Standard draw function with debug overlay when enabled.
---@param enemy table The bat_eye enemy
local function draw(enemy)
	common.draw(enemy)
	if config.bounding_boxes then
		draw_debug(enemy)
	end
end

--- Returns enemy to patrol height at 3x patrol speed.
---@param enemy table The bat_eye enemy
local function return_to_patrol_height(enemy)
	if not enemy.patrol_y then return end
	local dy = enemy.patrol_y - enemy.y
	if math.abs(dy) < 0.1 then
		enemy.vy = 0
	else
		enemy.vy = (dy > 0 and 1 or -1) * PATROL_SPEED * 3
	end
end

bat_eye.states = {}

bat_eye.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.IDLE)
		enemy.vx = 0
		enemy.idle_timer = IDLE_DURATION
		-- Swap target waypoint for next patrol
		local wp_a, wp_b = enemy.waypoint_a, enemy.waypoint_b
		if wp_a and wp_b then
			enemy.target_waypoint = enemy.target_waypoint == wp_a and wp_b or wp_a
		end
	end,
	update = function(enemy, dt)
		if can_detect_player(enemy, dt) then
			enemy:set_state(bat_eye.states.alert)
			return
		end

		return_to_patrol_height(enemy)

		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			enemy:set_state(bat_eye.states.patrol)
		end
	end,
	draw = draw,
}

bat_eye.states.patrol = {
	name = "patrol",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.IDLE)
		enemy.arrived_at_waypoint = false
		enemy.last_anim_frame = 0
		-- Store patrol height on first patrol (spawn height)
		if not enemy.patrol_y then
			enemy.patrol_y = enemy.y
		end
	end,
	update = function(enemy, dt)
		if can_detect_player(enemy, dt) then
			enemy:set_state(bat_eye.states.alert)
			return
		end

		if not enemy.target_waypoint then
			enemy:set_state(bat_eye.states.idle)
			return
		end

		return_to_patrol_height(enemy)

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
	draw = draw,
}

bat_eye.states.alert = {
	name = "alert",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.ALERT)
		enemy.vx = 0
		enemy.vy = 0
		enemy.direction = common.direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction
	end,
	update = function(enemy, _dt)
		if not enemy.animation:is_finished() then return end

		-- Lost sight: return to patrol
		if not common.has_line_of_sight(enemy) or not enemy.target_player then
			enemy:set_state(bat_eye.states.patrol)
			return
		end

		-- Save player position as attack target (doesn't track during attack)
		enemy.attack_target_x = enemy.target_player.x
		enemy.attack_target_y = enemy.target_player.y
		enemy:set_state(bat_eye.states.attack_start)
	end,
	draw = draw,
}

bat_eye.states.attack_start = {
	name = "attack_start",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.ATTACK_START)
		enemy.vx = 0
		enemy.vy = 0
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy:set_state(bat_eye.states.attack)
		end
	end,
	draw = draw,
}

bat_eye.states.attack = {
	name = "attack",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.ATTACK)
		local dx = enemy.attack_target_x - enemy.x
		local dy = enemy.attack_target_y - enemy.y
		local distance = math.sqrt(dx * dx + dy * dy)

		if distance > 0 then
			local speed_factor = ATTACK_SPEED / distance
			enemy.vx = dx * speed_factor
			enemy.vy = dy * speed_factor
		else
			enemy.vx = 0
			enemy.vy = 0
		end

		if dx ~= 0 then
			enemy.direction = dx > 0 and 1 or -1
			enemy.animation.flipped = enemy.direction
		end
	end,
	update = function(enemy, _dt)
		if enemy.hit_shield then
			enemy.hit_shield = false
			enemy:set_state(bat_eye.states.attack_recovery)
			return
		end

		local dx = enemy.attack_target_x - enemy.x
		local dy = enemy.attack_target_y - enemy.y
		if dx * dx + dy * dy < ATTACK_ARRIVAL_THRESHOLD_SQ then
			enemy:set_state(bat_eye.states.attack_recovery)
		end
	end,
	draw = draw,
}

bat_eye.states.attack_recovery = {
	name = "attack_recovery",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.ATTACK_RECOVERY)
		enemy.vx = 0
		enemy.vy = 0
	end,
	update = function(enemy, _dt)
		if not enemy.animation:is_finished() then return end

		-- Face the player and select waypoint in that direction
		enemy.direction = common.direction_to_player(enemy)
		enemy.animation.flipped = enemy.direction

		local wp_a, wp_b = enemy.waypoint_a, enemy.waypoint_b
		if wp_a and wp_b then
			local selector = enemy.direction == 1 and math.max or math.min
			enemy.target_waypoint = selector(wp_a, wp_b)
		end

		enemy:set_state(bat_eye.states.patrol)
	end,
	draw = draw,
}

bat_eye.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.HIT)
		enemy.vx = 0
		enemy.vy = 0
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy:set_state(bat_eye.states.patrol)
		end
	end,
	draw = draw,
}

bat_eye.states.death = {
	name = "death",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.DEATH)
		enemy.vx = 0
		enemy.vy = 0
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,
	draw = draw,
}

bat_eye.states.stun = {
	name = "stun",
	start = function(enemy, _)
		common.set_animation(enemy, bat_eye.animations.HIT)
		enemy.vx = 0
		enemy.vy = 0
		enemy.stun_timer = STUN_DURATION
	end,
	update = function(enemy, dt)
		-- Apply gravity until grounded
		-- Note: Position is already updated by update_flying_enemy, so only add gravity
		-- and check for ground collision without calling world.move (which would double-apply movement)
		if not enemy.is_grounded then
			enemy.vy = math.min(STUN_MAX_FALL_SPEED, enemy.vy + STUN_GRAVITY * dt * 60)
			-- Check for ground using point query (position already synced by flying enemy update)
			local ground_y = enemy.y + enemy.box.y + enemy.box.h
			if world.point_has_ground(enemy.x + enemy.box.x + enemy.box.w / 2, ground_y + 0.1) then
				enemy.is_grounded = true
				enemy.vy = 0
			end
		end

		enemy.stun_timer = enemy.stun_timer - dt
		if enemy.stun_timer <= 0 then
			enemy.is_grounded = false  -- Reset flying state before returning to patrol
			enemy:set_state(bat_eye.states.patrol)
		end
	end,
	draw = draw,
}

--- Called when player performs a perfect block against bat_eye's attack.
--- Bat_eye becomes stunned, falling to the ground and disabled for ~1 second.
---@param enemy table The bat_eye enemy
---@param _player table The player who perfect blocked
local function on_perfect_blocked(enemy, _player)
	enemy:set_state(bat_eye.states.stun)
end

return {
	on_perfect_blocked = on_perfect_blocked,
	box = { w = 0.5, h = 0.5, x = 0.25, y = 0.25 },  -- 8x8 centered hitbox
	gravity = 0,  -- Flying enemy
	max_fall_speed = 0,
	max_health = 2,
	damage = 2,
	damages_shield = true,
	death_sound = "ratto",  -- Reuse ratto death sound for now
	loot = { xp = 5, gold = { min = 0, max = 5 } },
	states = bat_eye.states,
	animations = bat_eye.animations,
	initial_state = "patrol",
}
