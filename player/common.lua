local audio = require('audio')
local sprites = require('sprites')
local controls = require('controls')

local common = {}

-- Constants
common.GRAVITY = 1.5
common.JUMP_VELOCITY = common.GRAVITY * 14
common.AIR_JUMP_VELOCITY = common.GRAVITY * 11
common.MAX_COYOTE = 4
common.MAX_FALL_SPEED = 20

-- Animations
common.animations = {
	IDLE = sprites.create_animation("player_idle", 6, 12),
    BLOCK = sprites.create_animation("player_block", 1, 1, 1, false),
	RUN = sprites.create_animation("player_run", 8, 7),
	DASH = sprites.create_animation("player_dash", 4, 3),
	FALL = sprites.create_animation("player_fall", 3, 6),
	JUMP = sprites.create_animation("player_jump_up", 3, 6, 1, false),
	AIR_JUMP = sprites.create_animation("player_double_jump", 4, 4),
	WALL_SLIDE = sprites.create_animation("player_wall_slide", 3, 6, 1, false),
	TURN = sprites.create_animation("player_turn", 4, 3, 1, false),
	

	CLIMB_UP = sprites.create_animation("player_climb_up", 6, 6),
	CLIMB_DOWN = sprites.create_animation("player_climb_down", 6, 6),

	ATTACK_0 = sprites.create_animation("player_attack_0", 5, 3, 2, false),
	ATTACK_1 = sprites.create_animation("player_attack_1", 5, 4, 2, false),
	ATTACK_2 = sprites.create_animation("player_attack_2", 5, 5, 2, false),
    HAMMER = sprites.create_animation("player_attack_hammer", 7, 9, 2, false),

    HIT = sprites.create_animation("player_hit", 3, 4, 1, false),
}

-- Helper functions
function common.handle_hammer(player)
    if controls.hammer_pressed() then
        player:set_state(player.states.hammer)
    end
end

function common.handle_attack(player)
	if controls.attack_pressed() and player.attack_cooldown <= 0 then
		player:set_state(player.states.attack)
	end
end

function common.handle_block(player)
    if controls.block_down() then
		player:set_state(player.states.block)
	end
end

--- Applies gravity to the player and transitions to air state if not grounded.
--- @param player table The player object
--- @param max_speed number|nil Maximum fall speed (defaults to MAX_FALL_SPEED)
function common.handle_gravity(player, max_speed)
	max_speed = max_speed or common.MAX_FALL_SPEED
	player.vy = math.min(max_speed, player.vy + common.GRAVITY)
	if not player.is_grounded and 
           player.state ~= player.states.block and
           player.state ~= player.states.hit then
		player:set_state(player.states.air)
	end
end

--- Checks for ladder climb entry conditions and transitions to climb state.
--- Entry points: standing on ladder top + down, grounded + up, in air + down/up.
--- @param player table The player object
function common.handle_climb(player)
	-- Entry from top of ladder (down while standing on ladder top)
	if player.standing_on_ladder_top and player.is_grounded then
		if controls.down_down() then
			player:set_state(player.states.climb)
		end
		return  -- Don't allow up to enter climb from top
	end
	-- Entry from middle of ladder (up or down while overlapping ladder)
	-- Grounded + UP = start climbing from bottom
	-- In air + DOWN = grab ladder while falling
	-- In air + UP = grab ladder while jumping (but not at top, to prevent flicker)
	local up_pressed_on_ground = controls.up_down() and player.is_grounded
	local down_pressed_in_air = controls.down_down() and not player.is_grounded
	local up_pressed_in_air = controls.up_down() and not player.is_grounded and not player.on_ladder_top
	if (up_pressed_on_ground or down_pressed_in_air or up_pressed_in_air) and player.can_climb then
		player:set_state(player.states.climb)
	end
end

function common.check_hit(player, cols)
    local canvas = require('canvas')
    if canvas.is_key_pressed(canvas.keys.Y) then
        player:set_state(player.states.hit)
    end
end

--- Updates ladder-related player flags based on trigger collisions.
--- Sets can_climb, current_ladder, on_ladder_top from overlapping ladder triggers.
--- @param player table The player object
--- @param cols table Collision results from world.move()
function common.check_ladder(player, cols)
	player.can_climb = false
	player.current_ladder = nil
	player.on_ladder_top = false
	for _, trigger in pairs(cols.triggers) do
		if trigger.owner.is_ladder then
			player.can_climb = true
			player.current_ladder = trigger.owner
			if trigger.owner.is_top then
				player.on_ladder_top = true
			end
		end
	end
	if not player.can_climb then
		player.is_climbing = false
	end
end

--- Processes collision flags to update grounded state, wall contact, and coyote time.
--- Uses separated X/Y collision pass results from world.move().
--- @param player table The player object
--- @param cols table Collision flags {ground, ceiling, wall_left, wall_right}
function common.check_ground(player, cols)
	-- Ground detection from Y collision pass
	if cols.ground then
		if not player.is_climbing then
			player.is_grounded = true
			player.ground_normal = cols.ground_normal
			player.coyote_frames = 0
			player.jumps = player.max_jumps
			player.has_dash = true
			player.vy = 0
			player.is_air_jumping = false
			player.climb_touching_ground = false  -- Clear when not climbing
			-- Track if standing on ladder top
			player.standing_on_ladder_top = cols.is_ladder_top or false
			-- Set ladder info when standing on ladder top (for entering climb from top)
			if cols.is_ladder_top and cols.ladder_from_top then
				player.current_ladder = cols.ladder_from_top
				player.can_climb = true
			end
		else
			-- Climbing but touching ground - store for climb state to check
			player.climb_touching_ground = true
		end
	else
		player.climb_touching_ground = false
		-- Check for ladder top even when ground collision was skipped (one-way platform)
		if cols.is_ladder_top and cols.ladder_from_top then
			player.standing_on_ladder_top = true
			player.current_ladder = cols.ladder_from_top
			player.can_climb = true
		else
			player.standing_on_ladder_top = false
		end
		player.coyote_frames = player.coyote_frames + 1
		if player.is_grounded and player.coyote_frames > common.MAX_COYOTE then
			player.is_grounded = false
			player.jumps = player.max_jumps - 1
		end
	end

	-- Ceiling detection
	if cols.ceiling then
		player.ceiling_normal = cols.ceiling_normal
		if player.vy < 0 then
			player.vy = 0
		end
	else
		player.ceiling_normal = nil
	end

	-- Wall detection for wall slide/jump
	player.wall_direction = 0
	if cols.wall_left then player.wall_direction = 1 end
	if cols.wall_right then player.wall_direction = -1 end
end

--- Attempts a ground jump if the player is grounded and jump is pressed.
--- @param player table The player object
--- @return boolean True if jump was performed
function common.handle_jump(player)
	if controls.jump_pressed() and (player.is_grounded or player.is_climbing) then
		player.vy = -common.JUMP_VELOCITY
		player.jumps = player.jumps - 1
		audio.play_jump_sound()
		return true
	end
	return false
end

--- Attempts an air jump if the player has remaining jumps and jump is pressed.
--- @param player table The player object
--- @return boolean True if air jump was performed
function common.handle_air_jump(player)
	if controls.jump_pressed() and player.jumps > 0 then
		player.vy = -common.AIR_JUMP_VELOCITY
		player.jumps = player.jumps - 1
		player.is_air_jumping = true
		audio.play_air_jump_sound()
		return true
	end
	return false
end

--- Attempts to initiate a dash if off cooldown and dash is pressed.
--- @param player table The player object
--- @return boolean True if dash was initiated
function common.handle_dash(player)
	if player.dash_cooldown > 0 or not player.has_dash then return false end
	if controls.dash_pressed() then
		player:set_state(player.states.dash)
		return true
	end
	return false
end

--- Checks if the player is pressing movement input toward a wall they're touching.
--- @param player table The player object
--- @return boolean True if pressing into wall
function common.is_pressing_into_wall(player)
	return (controls.left_down() and player.wall_direction == 1) or
	       (controls.right_down() and player.wall_direction == -1)
end

--- Returns the tangent vector of the ground the player is standing on.
--- Tangent points right along the surface.
--- @param player table The player object
--- @return table Tangent vector {x, y}
function common.get_ground_tangent(player)
	local nx = player.ground_normal.x
	local ny = player.ground_normal.y
	-- Tangent perpendicular to normal, pointing right
	return { x = -ny, y = nx }
end

return common
