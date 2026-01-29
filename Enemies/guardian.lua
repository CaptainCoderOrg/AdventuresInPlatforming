local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')
local canvas = require('canvas')
local combat = require('combat')
local common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')

--- Guardian enemy: Stationary enemy with spiked club.
--- Two damage zones: body (1 damage, hittable) and club (3 damage, not hittable).
--- Watches in facing direction, becomes alert when player detected, then attacks.
--- Attack has frame-based hitboxes for club swing animation.
--- States: idle, alert, attack, hit, death
local guardian = {}

-- Club hitbox constants (in tiles)
local CLUB_WIDTH = 0.9375     -- 15px / 16 (reduced 25% from 20px)
local CLUB_HEIGHT = 0.75      -- 12px / 16
local CLUB_Y_OFFSET = 0.0625  -- 1px / 16
local CLUB_DAMAGE = 3

-- Body hitbox edges (for club adjacency calculation)
local BODY_LEFT = 0.125       -- box.x
local BODY_RIGHT = 0.75       -- box.x + box.w

local DETECTION_RANGE = 12    -- Tiles
local DETECTION_HEIGHT = 1.5  -- Vertical range in tiles

local JUMP_VELOCITY = -18
local JUMP_GRAVITY = 1.5

-- Cached sprite dimensions (avoid per-frame multiplication)
local SPRITE_WIDTH = 48 * config.ui.SCALE   -- 144
local SPRITE_HEIGHT = 32 * config.ui.SCALE  -- 96
local BASE_WIDTH = 16 * config.ui.SCALE     -- 48
local EXTRA_HEIGHT = 16 * config.ui.SCALE   -- 48

-- Reusable tables for allocation avoidance
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
		hits[1]:take_damage(CLUB_DAMAGE, enemy.x)
	end
end

-- Attack hitbox definitions per frame (0-indexed)
-- Positions are offsets from enemy position in tiles (relative to character at sprite center-bottom)
-- offset_x is positive = right when facing left, mirrored when facing right
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
	-- Frames 5-7: Recovery, no active hitbox
	[5] = NO_HITBOXES,
	[6] = NO_HITBOXES,
	[7] = NO_HITBOXES,
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
		hx = enemy.x + 1 - hitbox.offset_x - hitbox.w
	end
	local hy = enemy.y + hitbox.offset_y
	return hx, hy, hitbox.w, hitbox.h
end

--- Check for player damage using attack hitboxes.
--- Falls back to default club hitbox if hitboxes are empty or nil.
---@param enemy table The guardian enemy
---@param hitboxes table|nil The hitbox definitions to use (nil or empty = use default club)
---@return boolean True if player was hit
local function check_attack_hitboxes(enemy, hitboxes)
	-- Use default club hitbox for nil or empty hitbox lists
	if not hitboxes or #hitboxes == 0 then
		check_club_collision(enemy)
		return false
	end

	-- Check each frame-specific hitbox
	for i = 1, #hitboxes do
		local hx, hy, hw, hh = get_attack_hitbox_world(enemy, hitboxes[i])
		local hits = combat.query_rect(hx, hy, hw, hh, player_filter, club_hits)
		if #hits > 0 and hits[1].take_damage then
			hits[1]:take_damage(CLUB_DAMAGE, enemy.x)
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
--- Handles nil (default club hitbox), empty tables, and hitbox arrays.
---@param enemy table The guardian enemy
---@param hitboxes table|nil The hitbox definitions (nil or empty = default club)
local function draw_hitboxes(enemy, hitboxes)
	if not config.bounding_boxes then return end

	canvas.set_color("#FFA50088")

	-- Nil or empty hitbox list: draw default club hitbox
	if not hitboxes or #hitboxes == 0 then
		draw_club_hitbox_rect(enemy)
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

--- Draw function for guardian with club hitbox and detection range visualization.
---@param enemy table The guardian enemy
local function draw_guardian(enemy)
	draw_sprite(enemy)

	if config.bounding_boxes then
		local ts = sprites.tile_size

		-- Draw club hitbox (orange)
		canvas.set_color("#FFA50088")
		draw_club_hitbox_rect(enemy)

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
		draw_hitboxes(enemy, ATTACK_HITBOXES[enemy.animation.frame])
	end
end

--- Draw function for jump/charge states (always frame 1 hitboxes - club raised).
---@param enemy table The guardian enemy
local function draw_club_raised(enemy)
	draw_sprite(enemy)
	draw_hitboxes(enemy, ATTACK_HITBOXES[1])
end

--- Draw function for land state (animation frame + 2 maps to attack hitboxes).
---@param enemy table The guardian enemy
local function draw_land(enemy)
	draw_sprite(enemy)
	if enemy.animation then
		draw_hitboxes(enemy, ATTACK_HITBOXES[math.min(enemy.animation.frame + 2, 7)])
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
	check_attack_hitboxes(enemy, ATTACK_HITBOXES[1])

	-- Hold animation on frame 1 (club raised) while airborne
	enemy.animation.frame = math.min(enemy.animation.frame, 1)

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
		width = 48,
		height = 32,
		loop = loop
	})
end

guardian.animations = {
	IDLE = create_anim(sprites.enemies.guardian.idle, 6, 150, true),
	ALERT = create_anim(sprites.enemies.guardian.alert, 4, 100, false),
	ATTACK = create_anim(sprites.enemies.guardian.attack, 8, 100, false),
	HIT = create_anim(sprites.enemies.guardian.hit, 5, 80, false),  -- Stun = 5 * 80ms = 400ms
	DEATH = create_anim(sprites.enemies.guardian.death, 6, 120, false),
	JUMP_AWAY = create_anim(sprites.enemies.guardian.jump, 2, 100, false),
	LAND = create_anim(sprites.enemies.guardian.land, 7, 100, false),
	CHARGE = create_anim(sprites.enemies.guardian.run, 4, 100, true),
}

guardian.states = {}

guardian.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.IDLE)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
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
		if dx <= 6 then
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
		common.set_animation(enemy, guardian.animations.CHARGE)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = enemy.direction * -4  -- Move backwards (opposite of facing)
		-- Randomize retreat duration for behavior variety
		enemy.back_away_timer = 0.5 + math.random() * 1.0  -- Random 0.5 to 1.5 seconds
	end,
	update = function(enemy, dt)
		check_club_collision(enemy)

		enemy.back_away_timer = enemy.back_away_timer - dt
		if enemy.back_away_timer <= 0 then
			enemy:set_state(guardian.states.reassess)
		end
	end,
	draw = draw_guardian,
}

guardian.states.reassess = {
	name = "reassess",
	start = function(enemy, _)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		local player = enemy.target_player
		if not player then
			enemy:set_state(guardian.states.idle)
			return
		end

		local dx = math.abs(player.x - enemy.x)
		if dx <= 2 then
			enemy.direction = common.direction_to_player(enemy)
			enemy:set_state(guardian.states.attack)
		elseif dx <= 6 then
			enemy:set_state(guardian.states.jump_toward)
		else
			enemy:set_state(guardian.states.assess_charge)
		end
	end,
	draw = draw_guardian,
}

guardian.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.HIT)
		enemy.direction = common.direction_to_player(enemy)
		enemy.vx = 0  -- Guardian is too heavy for knockback
	end,
	update = function(enemy, _dt)
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
		local jump_speed = 10 + math.random() * 5
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
			local target_x = player.x - enemy.direction * 1.25
			local distance = target_x - enemy.x
			enemy.vx = math.max(-12, math.min(12, distance * 2.5))
		else
			enemy.vx = enemy.direction * 10
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
		-- Map animation frame to attack hitboxes: land frames 0-7 map to attack frames 2-7
		-- This allows the landing animation to connect with club swing damage
		local hitbox_frame = math.min(enemy.animation.frame + 2, 7)
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
		enemy.vx = enemy.direction * 6  -- Run toward player
	end,
	update = function(enemy, _dt)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[1])

		local player = enemy.target_player
		if not player then return end

		local dx = player.x - enemy.x
		-- Attack if within range or if passed player
		if math.abs(dx) <= 1.25 or player_is_behind(enemy, dx) then
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
		enemy.vx = enemy.direction * 6  -- Run toward player
		-- Randomize jump trigger distance for behavior variety
		enemy.jump_at_distance = 4 + math.random() * 4  -- Random 4-8 units
	end,
	update = function(enemy, _dt)
		check_attack_hitboxes(enemy, ATTACK_HITBOXES[1])

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

guardian.states.assess_charge = {
	name = "assess_charge",
	start = function(enemy, _)
		enemy.vx = 0
	end,
	update = function(enemy, _dt)
		if math.random() < 0.5 then
			enemy:set_state(guardian.states.charge)
		else
			enemy:set_state(guardian.states.charge_and_jump)
		end
	end,
	draw = draw_guardian,
}

guardian.states.death = {
	name = "death",
	start = function(enemy, _)
		common.set_animation(enemy, guardian.animations.DEATH)
		enemy.vx = (enemy.hit_direction or -1) * 4
		enemy.vy = 0
		enemy.gravity = 0
	end,
	update = function(enemy, dt)
		enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
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
		if source.vx > 0 then return 1 end
		return -1
	end
	if source and source.x then
		if source.x < self.x then return 1 end
		return -1
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

return {
	box = { w = 0.625, h = 1, x = 0.125, y = 0 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 6,
	armor = 1,
	damage = 1,  -- Body contact damage
	death_sound = "spike_slug",
	loot = { xp = 12, gold = { min = 5, max = 15 } },
	states = guardian.states,
	animations = guardian.animations,
	initial_state = "idle",
	on_hit = custom_on_hit,
}
