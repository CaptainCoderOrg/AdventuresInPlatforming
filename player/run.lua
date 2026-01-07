local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')

--- Run state: Player is moving horizontally on the ground.
--- Transitions to idle when stopping, or dash/jump when triggered.
local run = { name = "run" }

local footstep_cooldown = 0
local FOOTSTEP_COOLDOWN_TIME = (common.animations.RUN.frame_count * common.animations.RUN.speed) / 2

-- Turn animation state
local is_turning = false
local turn_remaining_frames = 0
local previous_direction = nil
local turn_visual_direction = nil

--- Called when entering run state. Resets animation and footstep timer.
--- @param player table The player object
function run.start(player)
	common.animations.RUN.frame = 0
	player.animation = common.animations.RUN
	footstep_cooldown = 0
	is_turning = false
	turn_remaining_frames = 0
	previous_direction = player.direction
	turn_visual_direction = nil
end

--- Handles input while running. Updates direction or transitions to idle.
--- @param player table The player object
function run.input(player)
	local new_direction = nil
	if controls.left_down() then
		new_direction = -1
	elseif controls.right_down() then
		new_direction = 1
	else
		player.set_state(player.states.idle)
		return
	end

	-- Check for direction change (only when not already turning)
	if not is_turning and previous_direction and new_direction ~= previous_direction then
		is_turning = true
		turn_remaining_frames = common.animations.TURN.frame_count * common.animations.TURN.speed
		common.animations.TURN.frame = 0
		player.animation = common.animations.TURN
		turn_visual_direction = previous_direction
	end

	player.direction = new_direction
	previous_direction = new_direction

	common.handle_attack(player)
	common.handle_dash(player)
	common.handle_jump(player)
end

--- Updates run state. Applies movement, gravity, and triggers footstep sounds.
--- @param player table The player object
--- @param dt number Delta time
function run.update(player, dt)
	-- Handle turn animation countdown
	if is_turning then
		turn_remaining_frames = turn_remaining_frames - 1
		if turn_remaining_frames <= 0 then
			is_turning = false
			turn_visual_direction = nil
			common.animations.RUN.frame = 0
			player.animation = common.animations.RUN
		end
	end

	player.vx = player.direction * player.speed

	-- Only apply slope logic when grounded and not jumping
	if player.vy >= 0 and player.is_grounded then
		local is_slope = math.abs(player.ground_normal.x) > 0.01
		if is_slope then
			local tangent = common.get_ground_tangent(player)
			player.vy = player.direction * player.speed * (tangent.y / tangent.x)
		else
			common.handle_gravity(player)
		end
	else
		common.handle_gravity(player)
	end

	if footstep_cooldown <= 0 then
		audio.play_footstep()
		footstep_cooldown = FOOTSTEP_COOLDOWN_TIME * dt
	else
		footstep_cooldown = footstep_cooldown - dt
	end
end

--- Renders the player in running animation.
--- @param player table The player object
function run.draw(player)
	local anim = is_turning and common.animations.TURN or common.animations.RUN
	local visual_dir = turn_visual_direction or player.direction
	anim.flipped = visual_dir
	sprites.draw_animation(anim, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return run
