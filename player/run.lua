local Animation = require('Animation')
local common = require('player.common')
local controls = require('controls')

--- Run state: Player is moving horizontally on the ground.
--- Transitions to idle when stopping, or dash/jump when triggered.
local run = { name = "run" }

--- Called when entering run state. Resets animation and footstep timer.
---@param player table The player object
function run.start(player)
	player.animation = Animation.new(common.animations.RUN)
	common.reset_footsteps(player)
	player.run_state.is_turning = false
	player.run_state.turn_remaining_frames = 0
	player.run_state.previous_direction = player.direction
	player.run_state.turn_visual_direction = nil
end

--- Handles input while running. Updates direction or transitions to idle.
---@param player table The player object
function run.input(player)
	if common.check_cooldown_queues(player) then return end

	-- Check interactions first (before direction check may transition to idle)
	if common.handle_interact(player) then return end

	local new_direction = nil
	if controls.left_down() then
		new_direction = -1
	elseif controls.right_down() then
		new_direction = 1
	else
		player:set_state(player.states.idle)
		return
	end

	-- Check for direction change (only when not already turning)
	if not player.run_state.is_turning and player.run_state.previous_direction and new_direction ~= player.run_state.previous_direction then
		player.run_state.is_turning = true
		player.run_state.turn_remaining_time = (common.animations.TURN.frame_count * common.animations.TURN.ms_per_frame) / 1000
		player.animation = Animation.new(common.animations.TURN)
		player.run_state.turn_visual_direction = player.run_state.previous_direction
	end

	player.direction = new_direction
	player.run_state.previous_direction = new_direction

	common.handle_weapon_swap(player)
	common.handle_ability(player)
	common.handle_block(player)
	common.handle_attack(player)
	common.handle_dash(player)
	common.handle_jump(player)
end

--- Updates run state. Applies movement, gravity, and triggers footstep sounds.
---@param player table The player object
---@param dt number Delta time
function run.update(player, dt)
	-- Handle turn animation countdown
	if player.run_state.is_turning then
		player.run_state.turn_remaining_time = player.run_state.turn_remaining_time - dt
		if player.run_state.turn_remaining_time <= 0 then
			player.run_state.is_turning = false
			player.run_state.turn_visual_direction = nil
			player.animation = Animation.new(common.animations.RUN)
		end
	end

	player.vx = player.direction * player:get_speed()

	-- Only apply slope logic when grounded and not jumping
	if player.vy >= 0 and player.is_grounded then
		local is_slope = math.abs(player.ground_normal.x) > 0.01
		if is_slope then
			local tangent = common.get_ground_tangent(player)
			player.vy = player.direction * player:get_speed() * (tangent.y / tangent.x)
		else
			common.handle_gravity(player, dt)
		end
	else
		common.handle_gravity(player, dt)
	end

	common.update_footsteps(player, dt)
end

--- Renders the player in running animation.
---@param player table The player object
function run.draw(player)
	local visual_dir = player.run_state.turn_visual_direction or player.direction
	player.animation.flipped = visual_dir
	common.draw(player)
end

return run
