local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')

--- Run state: Player is moving horizontally on the ground.
--- Transitions to idle when stopping, or dash/jump when triggered.
local run = { name = "run" }

local footstep_cooldown = 0
local FOOTSTEP_COOLDOWN_TIME = (common.animations.RUN.frame_count * common.animations.RUN.speed) / 2

--- Called when entering run state. Resets animation and footstep timer.
--- @param player table The player object
function run.start(player)
	common.animations.RUN.frame = 0
	player.animation = common.animations.RUN
	footstep_cooldown = 0
end

--- Handles input while running. Updates direction or transitions to idle.
--- @param player table The player object
function run.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	else
		player.set_state(player.states.idle)
	end
	common.handle_dash(player)
	common.handle_jump(player)
end

--- Updates run state. Applies movement, gravity, and triggers footstep sounds.
--- @param player table The player object
--- @param dt number Delta time
function run.update(player, dt)
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
	sprites.draw_animation(common.animations.RUN, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return run
