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
	RUN = sprites.create_animation("player_run", 8, 7),
	DASH = sprites.create_animation("player_dash", 4, 3),
	FALL = sprites.create_animation("player_fall", 3, 6),
	JUMP = sprites.create_animation("player_jump_up", 3, 6),
	AIR_JUMP = sprites.create_animation("player_double_jump", 4, 4),
	WALL_SLIDE = sprites.create_animation("player_wall_slide", 3, 6),
}

-- Helper functions

--- Applies gravity to the player and transitions to air state if not grounded.
--- @param player table The player object
--- @param max_speed number|nil Maximum fall speed (defaults to MAX_FALL_SPEED)
function common.handle_gravity(player, max_speed)
	max_speed = max_speed or common.MAX_FALL_SPEED
	player.vy = math.min(max_speed, player.vy + common.GRAVITY)
	if not player.is_grounded then
		player.set_state(player.states.air)
	end
end

--- Processes collision flags to update grounded state, wall contact, and coyote time.
--- Uses separated X/Y collision pass results from world.move().
--- @param player table The player object
--- @param cols table Collision flags {ground, ceiling, wall_left, wall_right}
function common.check_ground(player, cols)
	-- Ground detection from Y collision pass
	if cols.ground then
		player.is_grounded = true
		player.ground_normal = cols.ground_normal
		player.coyote_frames = 0
		player.jumps = player.max_jumps
		player.has_dash = true
		player.vy = 0
		player.is_air_jumping = false
	else
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
	if controls.jump_pressed() and player.is_grounded then
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
		player.set_state(player.states.dash)
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
