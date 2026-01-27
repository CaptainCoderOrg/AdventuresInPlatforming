local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')
local canvas = require('canvas')
local audio = require('audio')
local combat = require('combat')
local common = require('Enemies/common')

--- Zombie enemy: A slow, shambling undead that patrols within bounded area.
--- States: idle (pause), move (patrol), chase (pursue), attack, hit, death
--- Detects player within patrol path in facing direction (AABB check).
--- Attacks when within 0.75 tiles, dealing damage on frames 6-7.
--- Patrol bounded by waypoint_a and waypoint_b. Health: 6 HP. Contact damage: 3.
local zombie = {}

local MOVE_SPEED = 1.5
local CHASE_SPEED = 6.0
local IDLE_MIN = 1.5
local IDLE_MAX = 3.0
local MOVE_MIN = 2.0
local MOVE_MAX = 4.0
local DETECTION_HEIGHT = 1.5  -- Vertical detection range in tiles
local ATTACK_RANGE = 1.5      -- Distance to trigger attack (stops before contact)
local ATTACK_HITBOX = 1.5     -- Attack hitbox reach
local ATTACK_COOLDOWN = 0.3   -- Brief cooldown after attack
local OVERSHOOT_DURATION = 0.5  -- Time to idle after player passes behind

-- Reusable table and filter for attack hitbox queries (avoids per-frame allocation)
local attack_hits = {}
local player_filter = function(entity) return entity.is_player end

-- Precomputed box offsets (box dimensions are constant: w=0.8, h=0.9, x=0.1, y=0.1)
local BOX_X = 0.1
local BOX_Y = 0.1
local BOX_CENTER_X = BOX_X + 0.8 / 2  -- box.x + box.w / 2
local BOX_CENTER_Y = BOX_Y + 0.9 / 2  -- box.y + box.h / 2

--- Check if enemy is at patrol boundary in current movement direction.
---@param enemy table The zombie enemy
---@return boolean True if at boundary and moving toward it
local function is_at_patrol_boundary(enemy)
	if not enemy.waypoint_a or not enemy.waypoint_b then
		return false
	end
	local margin = 0.1
	-- Only trigger when moving toward the boundary
	local at_left = enemy.direction == -1 and enemy.x <= enemy.waypoint_a + margin
	local at_right = enemy.direction == 1 and enemy.x >= enemy.waypoint_b - margin
	return at_left or at_right
end

--- Pick patrol direction with bias toward center.
---@param enemy table The zombie enemy
local function pick_patrol_direction(enemy)
	if not enemy.waypoint_a or not enemy.waypoint_b then
		enemy.direction = math.random() < 0.5 and -1 or 1
		return
	end

	local center = (enemy.waypoint_a + enemy.waypoint_b) / 2
	local to_center = center - enemy.x

	-- 70% chance to move toward center
	if math.random() < 0.7 then
		enemy.direction = to_center > 0 and 1 or -1
	else
		enemy.direction = math.random() < 0.5 and -1 or 1
	end
end

--- Check if player is within attack range in facing direction.
---@param enemy table The zombie enemy
---@return boolean True if player in attack range
local function is_player_in_attack_range(enemy)
	if not enemy.target_player then return false end

	local player = enemy.target_player
	local pbox = player.box
	local px = player.x + pbox.x + pbox.w / 2
	local ex = enemy.x + BOX_CENTER_X
	local dx = px - ex

	-- Must be in facing direction and within range
	local signed_dist = dx * enemy.direction
	return signed_dist > 0 and signed_dist <= ATTACK_RANGE
end

--- Calculate attack hitbox coordinates in tile space.
---@param enemy table The zombie enemy
---@return number x, number y, number w, number h Hitbox bounds in tiles
local function get_attack_hitbox(enemy)
	local ex = enemy.x + BOX_CENTER_X
	local ey = enemy.y + BOX_Y
	local hitbox_x = enemy.direction == 1 and ex or (ex - ATTACK_HITBOX)
	return hitbox_x, ey, ATTACK_HITBOX, 1
end

--- Draw function for attack state (32x16 sprite needs x-offset).
--- Sprite has body on left, attack extending right. Must offset when facing left.
---@param enemy table The zombie enemy
local function draw_attack(enemy)
	if not enemy.animation then return end

	local definition = enemy.animation.definition
	local frame = enemy.animation.frame
	local direction = enemy.direction

	local scale = config.ui.SCALE
	local sprite_width = definition.width * scale   -- 32 * 3 = 96
	local base_width = 16 * scale                   -- 16 * 3 = 48
	local extra_width = sprite_width - base_width   -- 48

	local x = sprites.px(enemy.x)
	local y = sprites.stable_y(enemy, enemy.y)

	canvas.save()

	if direction == 1 then
		-- Facing right: attack extends right, flip sprite, body stays at x
		canvas.translate(x + sprite_width, y)
		canvas.scale(-1, 1)
	else
		-- Facing left: attack extends left, offset left by extra width
		canvas.translate(x - extra_width, y)
	end

	canvas.draw_image(definition.name, 0, 0,
		sprite_width, definition.height * scale,
		frame * definition.width, 0,
		definition.width, definition.height)
	canvas.restore()

	-- Debug: draw attack hitbox on active frames
	if config.bounding_boxes and (frame == 5 or frame == 6) then
		local ts = sprites.tile_size
		local hx, hy, hw, hh = get_attack_hitbox(enemy)
		canvas.set_color("#FF000088")
		canvas.draw_rect(hx * ts, hy * ts, hw * ts, hh * ts)
	end
end

--- Check if player is within patrol path in facing direction (AABB check).
---@param enemy table The zombie enemy
---@return boolean True if player detected
local function can_detect_player(enemy)
	if not enemy.target_player then return false end
	if not enemy.waypoint_a or not enemy.waypoint_b then return false end

	local player = enemy.target_player
	local pbox = player.box
	local py = player.y + pbox.y + pbox.h / 2  -- Player center Y
	local ey = enemy.y + BOX_CENTER_Y          -- Enemy center Y

	-- Check vertical range (same ground level)
	if math.abs(py - ey) > DETECTION_HEIGHT then return false end

	local px = player.x + pbox.x + pbox.w / 2  -- Player center X
	local ex = enemy.x + BOX_CENTER_X          -- Enemy center X

	-- Check if player is in facing direction within patrol bounds
	if enemy.direction == 1 then
		return px > ex and px <= enemy.waypoint_b + 1
	else
		return px < ex and px >= enemy.waypoint_a - 1
	end
end

zombie.animations = {
	IDLE = Animation.create_definition(sprites.enemies.zombie.idle, 6, {
		ms_per_frame = 200,
		width = 16,
		height = 16,
		loop = true
	}),
	MOVE = Animation.create_definition(sprites.enemies.zombie.run, 6, {
		ms_per_frame = 150,
		width = 16,
		height = 16,
		loop = true
	}),
	ATTACK = Animation.create_definition(sprites.enemies.zombie.attack, 8, {
		ms_per_frame = 80,
		width = 32,
		height = 16,
		loop = false
	}),
	HIT = Animation.create_definition(sprites.enemies.zombie.hit, 5, {
		ms_per_frame = 60,
		width = 16,
		height = 16,
		loop = false
	}),
	DEATH = Animation.create_definition(sprites.enemies.zombie.death, 6, {
		ms_per_frame = 120,
		width = 16,
		height = 16,
		loop = false
	}),
}

zombie.states = {}

zombie.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, zombie.animations.IDLE)
		enemy.vx = 0
		enemy.idle_timer = IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN)
	end,
	update = function(enemy, dt)
		if can_detect_player(enemy) then
			enemy:set_state(zombie.states.chase)
			return
		end

		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			pick_patrol_direction(enemy)
			enemy:set_state(zombie.states.move)
		end
	end,
	draw = common.draw,
}

zombie.states.move = {
	name = "move",
	start = function(enemy, _)
		common.set_animation(enemy, zombie.animations.MOVE)
		enemy.move_timer = MOVE_MIN + math.random() * (MOVE_MAX - MOVE_MIN)
	end,
	update = function(enemy, dt)
		if can_detect_player(enemy) then
			enemy:set_state(zombie.states.chase)
			return
		end

		enemy.vx = enemy.direction * MOVE_SPEED

		-- Reverse at patrol boundaries or obstacles (updates flipped automatically)
		if is_at_patrol_boundary(enemy) or common.is_blocked(enemy) then
			common.reverse_direction(enemy)
		end

		enemy.move_timer = enemy.move_timer - dt
		if enemy.move_timer <= 0 then
			enemy:set_state(zombie.states.idle)
		end
	end,
	draw = common.draw,
}

zombie.states.chase = {
	name = "chase",
	start = function(enemy, _)
		enemy.direction = common.direction_to_player(enemy)
		common.set_animation(enemy, zombie.animations.MOVE)
		enemy.overshoot_timer = 0
		enemy.attack_cooldown = enemy.attack_cooldown or 0
	end,
	update = function(enemy, dt)
		-- Attack if in range and cooldown expired
		if is_player_in_attack_range(enemy) and enemy.attack_cooldown <= 0 then
			enemy:set_state(zombie.states.attack)
			return
		end

		enemy.vx = enemy.direction * CHASE_SPEED

		-- Stop at patrol boundaries or obstacles
		if is_at_patrol_boundary(enemy) or common.is_blocked(enemy) then
			enemy.vx = 0
			enemy:set_state(zombie.states.idle)
			return
		end

		-- Track time since player passed behind (overshoot detection)
		if common.direction_to_player(enemy) ~= enemy.direction then
			enemy.overshoot_timer = enemy.overshoot_timer + dt
			if enemy.overshoot_timer >= OVERSHOOT_DURATION then
				enemy:set_state(zombie.states.idle)
				return
			end
		else
			enemy.overshoot_timer = 0
		end

		-- Decay attack cooldown
		enemy.attack_cooldown = math.max(0, enemy.attack_cooldown - dt)
	end,
	draw = common.draw,
}

zombie.states.attack = {
	name = "attack",
	start = function(enemy, _)
		common.set_animation(enemy, zombie.animations.ATTACK)
		enemy.vx = 0
		enemy.attack_hit_player = false
		enemy.attack_sound_played = false
	end,
	update = function(enemy, dt)
		local frame = enemy.animation.frame

		-- Play attack sound on frame 3
		if frame == 3 and not enemy.attack_sound_played then
			audio.play_sword_sound()
			enemy.attack_sound_played = true
		end

		-- Damage player on frames 6 and 7 (0-indexed: 5 and 6)
		if (frame == 5 or frame == 6) and not enemy.attack_hit_player then
			local hx, hy, hw, hh = get_attack_hitbox(enemy)
			local hits = combat.query_rect(hx, hy, hw, hh, player_filter, attack_hits)

			if #hits > 0 and hits[1].take_damage then
				hits[1]:take_damage(enemy.damage, enemy.x)
				enemy.attack_hit_player = true
			end
		end

		if enemy.animation:is_finished() then
			enemy.attack_cooldown = ATTACK_COOLDOWN
			-- Face the player after attack
			enemy.direction = common.direction_to_player(enemy)
			-- Continue chase if player still detected, else idle
			if can_detect_player(enemy) then
				enemy:set_state(zombie.states.chase)
			else
				enemy:set_state(zombie.states.idle)
			end
		end
	end,
	draw = draw_attack,
}

zombie.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, zombie.animations.HIT)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		if enemy.animation:is_finished() then
			enemy.direction = common.direction_to_player(enemy)
			enemy:set_state(zombie.states.idle)
		end
	end,
	draw = common.draw,
}

zombie.states.death = common.create_death_state(zombie.animations.DEATH)

return {
	box = { w = 0.8, h = 0.9, x = 0.1, y = 0.1 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 6,
	damage = 3,
	damages_shield = true,
	death_sound = "spike_slug",
	loot = { xp = 8, gold = { min = 2, max = 10 } },
	states = zombie.states,
	animations = zombie.animations,
	initial_state = "idle",
}
