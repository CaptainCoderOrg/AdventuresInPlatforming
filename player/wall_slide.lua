local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')

--- Wall slide state: Player is sliding down a wall at reduced speed.
--- Transitions to wall_jump on jump, air if releasing wall, or idle on landing.
local wall_slide = { name = "wall_slide" }

local WALL_SLIDE_SPEED = 2
local WALL_SLIDE_GRACE_TIME = 5 / 60  -- 0.0833 seconds (5 frames at 60 FPS)
local WALL_SLIDE_DELAY = 0.2  -- 0.2 seconds before starting to slide down

--- Called when entering wall slide. Faces away from wall and resets grace time.
--- @param player table The player object
function wall_slide.start(player)
	player.animation = Animation.new(common.animations.WALL_SLIDE)
	player.direction = -player.wall_direction
	player.wall_slide_state.grace_time = 0
	player.wall_slide_state.slide_delay_timer = 0
	audio.play_footstep()
end

--- Handles input during wall slide. Jump triggers wall jump, releasing wall starts grace period.
--- @param player table The player object
function wall_slide.input(player)
	if controls.jump_pressed() then
		player.wall_jump_dir = player.wall_direction
		player:set_state(player.states.wall_jump)
		return
	end

	if common.is_pressing_into_wall(player) then
		player.wall_slide_state.holding_wall = true
	else
		player.wall_slide_state.holding_wall = false
	end

	common.handle_dash(player)
end

--- Updates wall slide. Limits fall speed while sliding, normal gravity during grace period.
--- @param player table The player object
--- @param dt number Delta time
function wall_slide.update(player, dt)
	if player.wall_slide_state.holding_wall then
		player.wall_slide_state.grace_time = 0
	else
		player.wall_slide_state.grace_time = player.wall_slide_state.grace_time + dt
		if player.wall_slide_state.grace_time >= WALL_SLIDE_GRACE_TIME then
			player:set_state(player.states.air)
			return
		end
	end

	player.wall_slide_state.slide_delay_timer = player.wall_slide_state.slide_delay_timer + dt

	local in_grace = player.wall_slide_state.grace_time > 0
	local in_slide_delay = player.wall_slide_state.slide_delay_timer < WALL_SLIDE_DELAY

	if in_grace then
		common.apply_gravity(player, dt)
		if player.animation.definition ~= common.animations.FALL then
			player.animation = Animation.new(common.animations.FALL)
		end
	elseif in_slide_delay then
		-- Stick to wall during delay (no sliding)
		player.vy = 0
	else
		-- Slide down at reduced speed after delay
		common.apply_gravity(player, dt, WALL_SLIDE_SPEED)
	end

	player.vx = -player.wall_direction * player.speed

	if player.is_grounded then
		player:set_state(player.states.idle)
	elseif player.wall_direction == 0 then
		player:set_state(player.states.air)
	end
end

--- Renders the player with wall slide or fall animation.
--- @param player table The player object
function wall_slide.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return wall_slide
