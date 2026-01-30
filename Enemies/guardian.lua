local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')
local canvas = require('canvas')
local combat = require('combat')
local common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')
local Projectile = require('Projectile')
local world = require('world')

--- Guardian enemy: Stationary enemy with spiked club.
--- Two damage zones: body (1 damage, hittable) and club (3 damage, not hittable).
--- Watches in facing direction, becomes alert when player detected, then attacks.
--- Attack has frame-based hitboxes for club swing animation.
--- States: idle, alert, attack, hit, death
local guardian = {}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

-- Club hitbox (in tiles)
local CLUB_WIDTH = 0.9375     -- 15px / 16 (reduced 25% from 20px)
local CLUB_HEIGHT = 0.75      -- 12px / 16
local CLUB_Y_OFFSET = 0.0625  -- 1px / 16
local CLUB_DAMAGE = 3

-- Body hitbox edges (for club adjacency calculation)
local BODY_LEFT = 0.125       -- box.x
local BODY_RIGHT = 0.75       -- box.x + box.w
local CHARACTER_WIDTH = 1     -- Width in tiles for hitbox mirroring

-- Detection
local DETECTION_RANGE = 12    -- Horizontal range in tiles
local DETECTION_HEIGHT = 1.5  -- Vertical range in tiles

-- Jump physics
local JUMP_VELOCITY = -18
local JUMP_GRAVITY = 1.5

-- Projectile dodging
local PROJECTILE_DODGE_RANGE = 4        -- Tiles: default dodge range
local PROJECTILE_DODGE_RANGE_BACK = 3   -- Tiles: dodge range while backing away
local PROJECTILE_VERTICAL_TOLERANCE = 0.25  -- Tiles: vertical range for projectile detection

-- Movement speeds (tiles per second)
local CHARGE_SPEED = 6
local BACK_AWAY_SPEED = 4
local DEATH_KNOCKBACK_SPEED = 4

-- Jump away randomization
local JUMP_AWAY_SPEED_BASE = 10
local JUMP_AWAY_SPEED_VARIANCE = 5

-- Jump toward constants
local JUMP_TOWARD_TARGET_OFFSET = 1.35  -- Distance from player to target landing
local JUMP_TOWARD_DISTANCE_MULT = 2.5   -- Multiplier for distance to velocity
local JUMP_TOWARD_MAX_VELOCITY = 12     -- Max horizontal jump velocity
local JUMP_TOWARD_FALLBACK_SPEED = 10   -- Speed when no player target

-- Jump over constants (higher arc to pass over player)
local JUMP_OVER_VELOCITY = -24          -- Higher jump than normal (-18)
local JUMP_OVER_SPEED = 11              -- Horizontal speed to clear player
local JUMP_OVER_DISTANCE_MIN = 3        -- Minimum trigger distance
local JUMP_OVER_DISTANCE_VARIANCE = 2   -- Variance for 3-5 range

-- Distance thresholds (in tiles)
local ATTACK_RANGE = 1.25             -- Distance to trigger attack while charging
local ATTACK_RANGE_REASSESS = 2       -- Distance to attack from reassess state
local JUMP_TOWARD_RANGE = 6           -- Distance to trigger jump toward player
local JUMP_DISTANCE_MIN = 4           -- Minimum jump trigger distance (charge_and_jump)
local JUMP_DISTANCE_VARIANCE = 4      -- Random variance for jump trigger distance

-- Timers (in seconds)
local BACK_AWAY_TIME_MIN = 0.5
local BACK_AWAY_TIME_VARIANCE = 1.0

-- Physics
local DEATH_FRICTION = 0.9

-- Animation frame indices
local FRAME_CLUB_RAISED = 1
local FRAME_MAX_ATTACK = 7

-- Sprite dimensions (in pixels, pre-scaled)
local SPRITE_RAW_WIDTH = 48
local SPRITE_RAW_HEIGHT = 32
local SPRITE_BASE_SIZE = 16           -- Base tile size in pixels

-- Cached sprite dimensions (avoid per-frame multiplication)
local SPRITE_WIDTH = SPRITE_RAW_WIDTH * config.ui.SCALE   -- 144
local SPRITE_HEIGHT = SPRITE_RAW_HEIGHT * config.ui.SCALE -- 96
local BASE_WIDTH = SPRITE_BASE_SIZE * config.ui.SCALE     -- 48
local EXTRA_HEIGHT = SPRITE_BASE_SIZE * config.ui.SCALE   -- 48

-- Animation timing (milliseconds per frame)
local ANIM_MS_IDLE = 150
local ANIM_MS_ALERT = 100
local ANIM_MS_ATTACK = 100
local ANIM_MS_HIT = 80
local ANIM_MS_DEATH = 120
local ANIM_MS_JUMP = 100
local ANIM_MS_LAND = 100
local ANIM_MS_CHARGE = 100

-- Animation frame counts
local ANIM_FRAMES_IDLE = 6
local ANIM_FRAMES_ALERT = 4
local ANIM_FRAMES_ATTACK = 8
local ANIM_FRAMES_HIT = 5
local ANIM_FRAMES_DEATH = 6
local ANIM_FRAMES_JUMP = 2
local ANIM_FRAMES_LAND = 7
local ANIM_FRAMES_CHARGE = 4

-- Entity stats
local MAX_HEALTH = 6
local ARMOR = 1
local BODY_DAMAGE = 1
local GRAVITY = 1.5
local MAX_FALL_SPEED = 20

-- Loot
local LOOT_XP = 12
local LOOT_GOLD_MIN = 5
local LOOT_GOLD_MAX = 15

-- Body hitbox dimensions (in tiles)
local BOX_WIDTH = 0.625
local BOX_HEIGHT = 1
local BOX_X = 0.125
local BOX_Y = 0

---------------------------------------------------------------------------
-- Reusable tables for allocation avoidance
---------------------------------------------------------------------------
local club_hits = {}
local NO_HITBOXES = {}  -- Shared empty table for recovery frames

--- Combat filter that matches only the player entity.
---@param entity table Entity to check
---@return boolean True if entity is the player
local function player_filter(entity) return entity.is_player end

--- Check if player is behind the enemy (opposite of facing direction).
---@param enemy table The guardian enemy
---@param dx number Horizontal distance to player (player.x - enemy.x)
---@return boolean True if player is behind
local function player_is_behind(enemy, dx)
	return (enemy.direction == 1 and dx < 0) or (enemy.direction == -1 and dx > 0)
end

--- Check if there's a player projectile within specified horizontal range and at same height.
---@param enemy table The guardian enemy
---@param range number|nil Horizontal detection range in tiles (defaults to PROJECTILE_DODGE_RANGE)
---@return boolean True if projectile detected nearby
local function is_projectile_nearby(enemy, range)
	local r = range or PROJECTILE_DODGE_RANGE
	for projectile, _ in pairs(Projectile.all) do
		local dy = math.abs(projectile.y - enemy.y)
		if dy <= PROJECTILE_VERTICAL_TOLERANCE then
			local dx = math.abs(projectile.x - enemy.x)
			if dx <= r then
				return true
			end
		end
	end
	return false
end

--- Check if player is visible in facing direction.
---@param enemy table The guardian enemy
---@return boolean True if player detected
local function can_detect_player(enemy)
	if not enemy.target_player then return false end

	local player = enemy.target_player
	local pbox = player.box
	local py = player.y + pbox.y + pbox.h / 2  -- Player center Y
	local ey = enemy.y + enemy.box.y + enemy.box.h / 2  -- Enemy center Y

	-- Check vertical range (same ground level)
	if math.abs(py - ey) > DETECTION_HEIGHT then return false end

	local px = player.x + pbox.x + pbox.w / 2  -- Player center X
	local ex = enemy.x + enemy.box.x + enemy.box.w / 2  -- Enemy center X
	local dx = px - ex

	-- Check if player is in facing direction and within range
	if enemy.direction == 1 then
		return dx > 0 and dx <= DETECTION_RANGE
	else
		return dx < 0 and -dx <= DETECTION_RANGE
	end
end

--- Calculate club hitbox coordinates in tile space.
--- Club extends opposite to facing direction (behind the body).
--- Club is directly adjacent to body hitbox.
---@param enemy table The guardian enemy
---@return number x, number y, number w, number h Hitbox bounds in tiles
local function get_club_hitbox(enemy)
	-- Facing left: club on right side; facing right: club on left side
	local club_x
	if enemy.direction == -1 then
		club_x = enemy.x + BODY_RIGHT
	else
		club_x = enemy.x + BODY_LEFT - CLUB_WIDTH
	end
	return club_x, enemy.y + CLUB_Y_OFFSET, CLUB_WIDTH, CLUB_HEIGHT
end

--- Check club collision with player and apply damage.
---@param enemy table The guardian enemy
local function check_club_collision(enemy)
	local hx, hy, hw, hh = get_club_hitbox(enemy)
	local hits = combat.query_rect(hx, hy, hw, hh, player_filter, club_hits)

	if #hits > 0 and hits[1].take_damage then
		hits[1]:take_damage(CLUB_DAMAGE, enemy.x, enemy)
	end
end

-- Attack hitbox definitions per frame (0-indexed)
-- Positions are offsets from enemy position in tiles (relative to character at sprite center-bottom)
-- offset_x is positive = right when facing left, mirrored when facing right
-- nil = use default club hitbox (behind guardian)
-- NO_HITBOXES = no damage hitbox at all
local ATTACK_HITBOXES = {
	-- Frame 0: Idle stance, uses default club hitbox behind guardian
	[0] = nil,
	-- Frame 1: Club raised overhead, small hitbox above guardian
	[1] = {
		{ offset_x = 0.6875, offset_y = -0.6875, w = 0.625, h = 0.625 },
	},
	-- Frame 2: Club mid-swing, wide arc with vertical reach
	[2] = {
		{ offset_x = -1, offset_y = -0.625, w = 1, h = 1.5 },
		{ offset_x = -1, offset_y = -0.625, w = 2, h = 0.625 },
	},
	-- Frame 3: Club slammed down in front
	[3] = {
		{ offset_x = -1, offset_y = 0, w = 1, h = 1 },
	},
	-- Frame 4: Club held down (same coverage as frame 3)
	[4] = {
		{ offset_x = -1, offset_y = 0, w = 1, h = 1 },
	},
	-- Frames 5-6: Recovery, no damage hitbox
	[5] = NO_HITBOXES,
	[6] = NO_HITBOXES,
	-- Frame 7: Last frame, club returns to behind guardian
	[7] = nil,
}

--- Calculate attack hitbox world position based on sprite offset and direction.
--- Offsets are defined for facing-left; mirrored around character (1 tile wide) for facing-right.
---@param enemy table The guardian enemy
---@param hitbox table Hitbox definition with offset_x, offset_y, w, h
---@return number x, number y, number w, number h World hitbox bounds in tiles
local function get_attack_hitbox_world(enemy, hitbox)
	local hx
	if enemy.direction == -1 then
		-- Facing left: use offset directly
		hx = enemy.x + hitbox.offset_x
	else
		-- Facing right: mirror offset and width around character center
		hx = enemy.x + CHARACTER_WIDTH - hitbox.offset_x - hitbox.w
	end
	local hy = enemy.y + hitbox.offset_y
	return hx, hy, hitbox.w, hitbox.h
end

--- Get the current shield hitbox position based on state and animation.
--- Shield follows the club through all animations.
--- Returns nil when club is not in a blocking position (recovery frames).
---@param enemy table The guardian enemy
---@return number|nil x, number y, number w, number h Hitbox bounds in tiles, or nil if no hitbox
local function get_shield_hitbox(enemy)
	local state_name = enemy.state and enemy.state.name

	-- States using CHARGE animation have club raised (ATTACK_HITBOXES[FRAME_CLUB_RAISED])
	if state_name == "charge" or state_name == "charge_and_jump"
	   or state_name == "charge_and_jump_over" or state_name == "jump_over"
	   or state_name == "jump_away" or state_name == "jump_toward"
	   or state_name == "back_away" or state_name == "reassess" then
		local hitbox = ATTACK_HITBOXES[FRAME_CLUB_RAISED][1]
		return get_attack_hitbox_world(enemy, hitbox)
	end

	-- Attack state uses frame-based hitboxes
	if state_name == "attack" and enemy.animation then
		local frame = enemy.animation.frame
		local hitboxes = ATTACK_HITBOXES[frame]
		if hitboxes and #hitboxes > 0 then
			return get_attack_hitbox_world(enemy, hitboxes[1])
		end
		-- Frame 0: default club position
		if frame == 0 then
			return get_club_hitbox(enemy)
		end
		-- Last frame: returning to default club position
		if frame == FRAME_MAX_ATTACK then
			return get_club_hitbox(enemy)
		end
		-- Recovery frames: no hitbox
		return nil
	end

	-- Land state uses frame+1 based hitboxes (land starts with club raised like attack frame 1)
	if state_name == "land" and enemy.animation then
		local frame = math.min(enemy.animation.frame + 1, FRAME_MAX_ATTACK)
		local hitboxes = ATTACK_HITBOXES[frame]
		if hitboxes and #hitboxes > 0 then
			return get_attack_hitbox_world(enemy, hitboxes[1])
		end
		-- nil = club behind (last frame returning to idle)
		if hitboxes == nil then
			return get_club_hitbox(enemy)
		end
		-- NO_HITBOXES (empty table) = recovery frames, no shield
		return nil
	end

	-- Default: use club hitbox (behind guardian)
	return get_club_hitbox(enemy)
end

--- Update shield colliders to follow the club position.
--- Shield blocks both projectiles (via world.projectile_collider) and
--- player weapons (via combat.shield).
--- Removes shield during recovery frames when club is not blocking.
---@param enemy table The guardian enemy
local function update_shield(enemy)
	local hx, hy, hw, hh = get_shield_hitbox(enemy)

	-- No hitbox during recovery frames - remove shield
	if not hx then
		if enemy.combat_shield then
			combat.remove_shield(enemy)
			world.remove_projectile_collider(enemy)
			enemy.combat_shield = nil
		end
		return
	end

	if enemy.combat_shield then
		combat.update_shield(enemy, hx, hy, hw, hh)
		world.update_projectile_collider(enemy, hx, hy, hw, hh)
	else
		combat.add_shield(enemy, hx, hy, hw, hh)
		world.add_projectile_collider(enemy, hx, hy, hw, hh)
		enemy.combat_shield = true
	end
end

--- Remove shield colliders when guardian is destroyed.
---@param enemy table The guardian enemy
local function remove_shield(enemy)
	if enemy.combat_shield then
		combat.remove_shield(enemy)
		world.remove_projectile_collider(enemy)
		enemy.combat_shield = nil
	end
end

--- Check for player damage using attack hitboxes.
--- nil = use default club hitbox (behind guardian)
--- Empty table (NO_HITBOXES) = no damage hitbox
--- Table with hitboxes = use those specific hitboxes
---@param enemy table The guardian enemy
---@param hitboxes table|nil The hitbox definitions to use
---@return boolean True if player was hit
local function check_attack_hitboxes(enemy, hitboxes)
	-- nil = use default club hitbox behind guardian
	if hitboxes == nil then
		check_club_collision(enemy)
		return false
	end

	-- Empty table (NO_HITBOXES) = no damage this frame
	if #hitboxes == 0 then
		return false
	end

	-- Check each frame-specific hitbox
	for i = 1, #hitboxes do
		local hx, hy, hw, hh = get_attack_hitbox_world(enemy, hitboxes[i])
		local hits = combat.query_rect(hx, hy, hw, hh, player_filter, club_hits)
		if #hits > 0 and hits[1].take_damage then
			hits[1]:take_damage(CLUB_DAMAGE, enemy.x, enemy)
			return true
		end
	end

	return false
end

--- Draw club hitbox rectangle in pixel space (for debug visualization).
---@param enemy table The guardian enemy
local function draw_club_hitbox_rect(enemy)
	local ts = sprites.tile_size
	local hx, hy, hw, hh = get_club_hitbox(enemy)
	canvas.draw_rect(hx * ts, hy * ts, hw * ts, hh * ts)
end

--- Draw hitboxes for a given frame definition.
--- nil = draw default club hitbox (behind guardian)
--- Empty table (NO_HITBOXES) = draw nothing
--- Table with hitboxes = draw those specific hitboxes
---@param enemy table The guardian enemy
---@param hitboxes table|nil The hitbox definitions
local function draw_hitboxes(enemy, hitboxes)
	if not config.bounding_boxes then return end

	canvas.set_color("#FFA50088")

	-- nil = draw default club hitbox behind guardian
	if hitboxes == nil then
		draw_club_hitbox_rect(enemy)
		return
	end

	-- Empty table (NO_HITBOXES) = no hitbox to draw
	if #hitboxes == 0 then
		return
	end

	-- Draw frame-specific hitboxes
	local ts = sprites.tile_size
	for i = 1, #hitboxes do
		local hx, hy, hw, hh = get_attack_hitbox_world(enemy, hitboxes[i])
		canvas.draw_rect(hx * ts, hy * ts, hw * ts, hh * ts)
	end
end

--- Draw guardian sprite (48x32 sprite with character at bottom center).
---@param enemy table The guardian enemy
local function draw_sprite(enemy)
	if not enemy.animation then return end

	local definition = enemy.animation.definition
	local frame = enemy.animation.frame
	local x = sprites.px(enemy.x)
	local y = sprites.stable_y(enemy, enemy.y)

	canvas.save()

	if enemy.direction == 1 then
		-- Facing right: flip sprite, character stays at x
		canvas.translate(x + SPRITE_WIDTH - BASE_WIDTH, y - EXTRA_HEIGHT)
		canvas.scale(-1, 1)
	else
		-- Facing left: character at bottom center, offset sprite left and up
		canvas.translate(x - BASE_WIDTH, y - EXTRA_HEIGHT)
	end

	canvas.draw_image(definition.name, 0, 0,
		SPRITE_WIDTH, SPRITE_HEIGHT,
		frame * definition.width, 0,
		definition.width, definition.height)
	canvas.restore()
end

--- Draw shield hitbox when shield is active.
---@param enemy table The guardian enemy
local function draw_shield_hitbox(enemy)
	if not config.bounding_boxes or not enemy.combat_shield then return end

	local hx, hy, hw, hh = get_shield_hitbox(enemy)
	if not hx then return end  -- No hitbox during recovery

	local ts = sprites.tile_size
	canvas.set_color("#00FF0088")  -- Green for shield
	canvas.draw_rect(hx * ts, hy * ts, hw * ts, hh * ts)
end

--- Draw function for guardian with club hitbox and detection range visualization.
---@param enemy table The guardian enemy
local function draw_guardian(enemy)
	draw_sprite(enemy)

	if config.bounding_boxes then
		local ts = sprites.tile_size

		-- Draw club damage hitbox (orange)
		canvas.set_color("#FFA50088")
		draw_club_hitbox_rect(enemy)

		-- Draw shield hitbox (green) on top when active
		draw_shield_hitbox(enemy)

		-- Draw detection range (yellow, semi-transparent)
		local ex = enemy.x + enemy.box.x + enemy.box.w / 2
		local ey = enemy.y + enemy.box.y + enemy.box.h / 2

		local detect_x
		if enemy.direction == -1 then
			detect_x = ex - DETECTION_RANGE
		else
			detect_x = ex
		end

		canvas.set_color("#FFFF0044")
		canvas.draw_rect(detect_x * ts, (ey - DETECTION_HEIGHT) * ts, DETECTION_RANGE * ts, DETECTION_HEIGHT * 2 * ts)
	end
end

--- Draw function for attack state with frame-based hitbox visualization.
---@param enemy table The guardian enemy
local function draw_attack(enemy)
	draw_sprite(enemy)
	if enemy.animation then
		-- Draw damage hitboxes (orange)
		draw_hitboxes(enemy, ATTACK_HITBOXES[enemy.animation.frame])
		-- Draw shield hitbox (green) on top
		draw_shield_hitbox(enemy)
	end
end

--- Draw function for jump/charge states (always frame 1 hitboxes - club raised).
---@param enemy table The guardian enemy
local function draw_club_raised(enemy)
	draw_sprite(enemy)
	-- Draw damage hitboxes (orange)
	draw_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])
	-- Draw shield hitbox (green) on top
	draw_shield_hitbox(enemy)
end

--- Draw function for land state.
---@param enemy table The guardian enemy
local function draw_land(enemy)
	draw_sprite(enemy)
	if enemy.animation then
		-- Draw damage hitboxes (orange)
		local hitbox_frame = math.min(enemy.animation.frame + 1, FRAME_MAX_ATTACK)
		draw_hitboxes(enemy, ATTACK_HITBOXES[hitbox_frame])
		-- Draw shield hitbox (green) on top
		draw_shield_hitbox(enemy)
	end
end

--- Initialize jump physics for a guardian.
--- Sets up animation, direction toward player, and jump velocity.
---@param enemy table The guardian enemy
local function start_jump(enemy)
	common.set_animation(enemy, guardian.animations.JUMP_AWAY)
	enemy.direction = common.direction_to_player(enemy)
	enemy.vy = JUMP_VELOCITY
	enemy.gravity = JUMP_GRAVITY
end

--- Shared update logic for airborne jump states.
--- Holds animation on frame 1 and transitions to land when grounded.
---@param enemy table The guardian enemy
local function update_airborne(enemy)
	update_shield(enemy)
	check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

	-- Hold animation on club raised frame while airborne
	enemy.animation.frame = math.min(enemy.animation.frame, FRAME_CLUB_RAISED)

	if enemy.is_grounded then
		enemy:set_state(guardian.states.land)
	end
end

--- Create animation definition with standard guardian sprite dimensions (48x32).
---@param sprite string Sprite resource path
---@param frames number Number of animation frames
---@param ms_per_frame number Milliseconds per frame
---@param loop boolean Whether animation should loop
---@return table Animation definition
local function create_anim(sprite, frames, ms_per_frame, loop)
	return Animation.create_definition(sprite, frames, {
		ms_per_frame = ms_per_frame,
		width = SPRITE_RAW_WIDTH,
		height = SPRITE_RAW_HEIGHT,
		loop = loop
	})
end

guardian.animations = {
	IDLE = create_anim(sprites.enemies.guardian.idle, ANIM_FRAMES_IDLE, ANIM_MS_IDLE, true),
	ALERT = create_anim(sprites.enemies.guardian.alert, ANIM_FRAMES_ALERT, ANIM_MS_ALERT, false),
	ATTACK = create_anim(sprites.enemies.guardian.attack, ANIM_FRAMES_ATTACK, ANIM_MS_ATTACK, false),
	HIT = create_anim(sprites.enemies.guardian.hit, ANIM_FRAMES_HIT, ANIM_MS_HIT, false),
	DEATH = create_anim(sprites.enemies.guardian.death, ANIM_FRAMES_DEATH, ANIM_MS_DEATH, false),
	JUMP_AWAY = create_anim(sprites.enemies.guardian.jump, ANIM_FRAMES_JUMP, ANIM_MS_JUMP, false),
	LAND = create_anim(sprites.enemies.guardian.land, ANIM_FRAMES_LAND, ANIM_MS_LAND, false),
	CHARGE = create_anim(sprites.enemies.guardian.run, ANIM_FRAMES_CHARGE, ANIM_MS_CHARGE, true),
}

guardian.states = {}

guardian.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.IDLE)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		if can_detect_player(enemy) then
			enemy:set_state(guardian.states.alert)
		else
			check_club_collision(enemy)
		end
	end,
	draw = draw_guardian,
}

guardian.states.alert = {
	name = "alert",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.ALERT)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		check_club_collision(enemy)

		-- Wait for alert animation to finish before transitioning
		if not enemy.animation:is_finished() then return end

		local player = enemy.target_player
		if not player then
			-- No player: transition to attack (will hit nothing)
			enemy:set_state(guardian.states.attack)
			return
		end

		-- Decide action based on distance
		local dx = math.abs(player.x - enemy.x)
		if dx <= JUMP_TOWARD_RANGE then
			enemy:set_state(guardian.states.jump_toward)
		else
			enemy:set_state(guardian.states.assess_charge)
		end
	end,
	draw = draw_guardian,
}

guardian.states.attack = {
	name = "attack",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.ATTACK)
		enemy.vx = 0
		enemy.attack_hit_player = false  -- Track hit to allow only one damage per attack
	end,
	update = function(enemy, _dt)
		update_shield(enemy)

		-- Check hitboxes only once per attack (avoid multiple hits)
		if not enemy.attack_hit_player then
			local hitboxes = ATTACK_HITBOXES[enemy.animation.frame]
			if check_attack_hitboxes(enemy, hitboxes) then
				enemy.attack_hit_player = true
			end
		end

		if enemy.animation:is_finished() then
			enemy:set_state(guardian.states.back_away)
		end
	end,
	draw = draw_attack,
}

guardian.states.back_away = {
	name = "back_away",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.CHARGE, { reverse = true })
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = enemy.direction * -BACK_AWAY_SPEED  -- Move backwards (opposite of facing)
		-- Randomize retreat duration for behavior variety
		enemy.back_away_timer = BACK_AWAY_TIME_MIN + math.random() * BACK_AWAY_TIME_VARIANCE
	end,
	update = function(enemy, dt)
		update_shield(enemy)
		-- Club is raised in CHARGE animation, use raised hitbox
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

		-- Dodge incoming projectiles by jumping
		if is_projectile_nearby(enemy, PROJECTILE_DODGE_RANGE_BACK) then
			enemy:set_state(guardian.states.jump_away)
			return
		end

		enemy.back_away_timer = enemy.back_away_timer - dt
		if enemy.back_away_timer <= 0 then
			enemy:set_state(guardian.states.reassess)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.reassess = {
	name = "reassess",
	start = function(enemy, _)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		-- Decision state - immediately transitions, no damage check
		-- Shield still updated for blocking during this frame
		update_shield(enemy)

		local player = enemy.target_player
		if not player then
			enemy:set_state(guardian.states.idle)
			return
		end

		local dx = math.abs(player.x - enemy.x)
		if dx <= ATTACK_RANGE_REASSESS then
			enemy.direction = common.direction_to_player(enemy)
			enemy:set_state(guardian.states.attack)
		elseif dx <= JUMP_TOWARD_RANGE then
			enemy:set_state(guardian.states.jump_toward)
		else
			enemy:set_state(guardian.states.assess_charge)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.HIT)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = 0  -- Guardian is too heavy for knockback
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		-- Club remains dangerous during hit stun
		check_club_collision(enemy)

		if enemy.animation:is_finished() then
			enemy:set_state(guardian.states.jump_away)
		end
	end,
	draw = draw_guardian,
}

guardian.states.jump_away = {
	name = "jump_away",
	start = function(enemy, _)
		start_jump(enemy)
		local jump_speed = JUMP_AWAY_SPEED_BASE + math.random() * JUMP_AWAY_SPEED_VARIANCE
		enemy.vx = enemy.direction * -jump_speed  -- Jump away (opposite of facing)
	end,
	update = update_airborne,
	draw = draw_club_raised,
}

guardian.states.jump_toward = {
	name = "jump_toward",
	start = function(enemy, _)
		start_jump(enemy)
		local player = enemy.target_player
		if player then
			local target_x = player.x - enemy.direction * JUMP_TOWARD_TARGET_OFFSET
			local distance = target_x - enemy.x
			enemy.vx = math.max(-JUMP_TOWARD_MAX_VELOCITY, math.min(JUMP_TOWARD_MAX_VELOCITY, distance * JUMP_TOWARD_DISTANCE_MULT))
		else
			enemy.vx = enemy.direction * JUMP_TOWARD_FALLBACK_SPEED
		end
	end,
	update = update_airborne,
	draw = draw_club_raised,
}

guardian.states.land = {
	name = "land",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.LAND)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		update_shield(enemy)

		-- Map animation frame to attack hitboxes: land starts with club raised (attack frame 1)
		local hitbox_frame = math.min(enemy.animation.frame + 1, FRAME_MAX_ATTACK)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[hitbox_frame])

		if enemy.animation:is_finished() then
			enemy:set_state(guardian.states.back_away)
		end
	end,
	draw = draw_land,
}

guardian.states.charge = {
	name = "charge",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.CHARGE)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = enemy.direction * CHARGE_SPEED
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

		-- Dodge incoming projectiles by jumping
		if is_projectile_nearby(enemy) then
			enemy:set_state(guardian.states.jump_toward)
			return
		end

		local player = enemy.target_player
		if not player then return end

		local dx = player.x - enemy.x
		-- Attack if within range or if passed player
		if math.abs(dx) <= ATTACK_RANGE or player_is_behind(enemy, dx) then
			enemy:set_state(guardian.states.attack)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.charge_and_jump = {
	name = "charge_and_jump",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.CHARGE)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = enemy.direction * CHARGE_SPEED
		-- Randomize jump trigger distance for behavior variety
		enemy.jump_at_distance = JUMP_DISTANCE_MIN + math.random() * JUMP_DISTANCE_VARIANCE
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

		local player = enemy.target_player
		if not player then return end

		local dx = player.x - enemy.x
		if math.abs(dx) <= enemy.jump_at_distance then
			enemy:set_state(guardian.states.jump_toward)
		elseif player_is_behind(enemy, dx) then
			enemy:set_state(guardian.states.attack)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.charge_and_jump_over = {
	name = "charge_and_jump_over",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.CHARGE)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = enemy.direction * CHARGE_SPEED
		-- Randomize jump trigger distance (3-5 units)
		enemy.jump_at_distance = JUMP_OVER_DISTANCE_MIN + math.random() * JUMP_OVER_DISTANCE_VARIANCE
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

		local player = enemy.target_player
		if not player then return end

		local dx = player.x - enemy.x
		if math.abs(dx) <= enemy.jump_at_distance then
			enemy:set_state(guardian.states.jump_over)
		elseif player_is_behind(enemy, dx) then
			enemy:set_state(guardian.states.attack)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.jump_over = {
	name = "jump_over",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.JUMP_AWAY)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vy = JUMP_OVER_VELOCITY
		enemy.vx = enemy.direction * JUMP_OVER_SPEED
		enemy.gravity = JUMP_GRAVITY
		enemy.has_passed_player = false
	end,
	update = function(enemy, _dt)
		update_shield(enemy)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[FRAME_CLUB_RAISED])

		-- Hold animation on club raised frame while airborne
		enemy.animation.frame = math.min(enemy.animation.frame, FRAME_CLUB_RAISED)

		-- Check if passed player and turn to face them
		if not enemy.has_passed_player then
			local player = enemy.target_player
			if player then
				local dx = player.x - enemy.x
				if player_is_behind(enemy, dx) then
					enemy.direction = -enemy.direction
					enemy.has_passed_player = true
				end
			end
		end

		if enemy.is_grounded then
			enemy:set_state(guardian.states.land)
		end
	end,
	draw = draw_club_raised,
}

guardian.states.assess_charge = {
	name = "assess_charge",
	start = function(enemy, _)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		update_shield(enemy)

		local roll = math.random()
		if roll < 1/3 then
			enemy:set_state(guardian.states.charge)
		elseif roll < 2/3 then
			enemy:set_state(guardian.states.charge_and_jump)
		else
			enemy:set_state(guardian.states.charge_and_jump_over)
		end
	end,
	draw = draw_guardian,
}

guardian.states.death = {
	name = "death",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.DEATH)
		enemy.vx = (enemy.hit_direction or -1) * DEATH_KNOCKBACK_SPEED
		enemy.vy = 0
		enemy.gravity = 0
		-- Clean up shield colliders on death
		remove_shield(enemy)
	end,
	update = function(enemy, dt)
		enemy.vx = common.apply_friction(enemy.vx, DEATH_FRICTION, dt)
		if enemy.animation:is_finished() then
			enemy.marked_for_destruction = true
		end
	end,
	draw = draw_guardian,
}

--- Determine hit direction from damage source.
---@param self table The guardian enemy
---@param source table|nil The source entity
---@return number Direction (-1 or 1)
local function get_hit_direction(self, source)
	if source and source.vx then
		return source.vx > 0 and 1 or -1
	end
	if source and source.x then
		return source.x < self.x and 1 or -1
	end
	return -1
end

--- Check if guardian can be interrupted into hit state.
---@param self table The guardian enemy
---@return boolean True if can be interrupted
local function can_be_interrupted(self)
	local state = self.state
	return state ~= guardian.states.hit and state ~= guardian.states.jump_away
end

--- Custom on_hit handler: applies damage and stun but no knockback velocity.
---@param self table The guardian enemy
---@param _source_type string Type of damage source (unused, part of required signature)
---@param source table The source entity
local function custom_on_hit(self, _source_type, source)
	if self.invulnerable then return end

	local damage = math.max(0, ((source and source.damage) or 1) - self:get_armor())

	Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage)

	if damage <= 0 then
		audio.play_solid_sound()
		return
	end

	self.health = self.health - damage
	audio.play_squish_sound()
	self.hit_direction = get_hit_direction(self, source)

	if self.health <= 0 then
		self:die()
	elseif can_be_interrupted(self) then
		self:set_state(guardian.states.hit)
	end
end

--- Called when player performs a perfect block against guardian's attack.
--- Guardian takes 2 damage and enters hit state (no knockback - heavy enemy).
---@param self table The guardian enemy
---@param player table The player who perfect blocked
local function custom_on_perfect_blocked(self, player)
	-- Simulate being hit by the player's counter (2 damage, weapon type for hit state)
	custom_on_hit(self, "weapon", { x = player.x, damage = 2 })
end

return {
	on_perfect_blocked = custom_on_perfect_blocked,
	box = { w = BOX_WIDTH, h = BOX_HEIGHT, x = BOX_X, y = BOX_Y },
	gravity = GRAVITY,
	max_fall_speed = MAX_FALL_SPEED,
	max_health = MAX_HEALTH,
	armor = ARMOR,
	damage = BODY_DAMAGE,
	death_sound = "spike_slug",
	loot = { xp = LOOT_XP, gold = { min = LOOT_GOLD_MIN, max = LOOT_GOLD_MAX } },
	states = guardian.states,
	animations = guardian.animations,
	initial_state = "idle",
	on_hit = custom_on_hit,
}
