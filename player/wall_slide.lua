local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')

--- Wall slide state: Player is sliding down a wall at reduced speed.
--- Transitions to wall_jump on jump, air if releasing wall, or idle on landing.
local wall_slide = { name = "wall_slide" }

local WALL_SLIDE_SPEED = 2
local WALL_SLIDE_GRACE_FRAMES = 5

wall_slide.grace_frames = 0

--- Called when entering wall slide. Faces away from wall and resets grace frames.
--- @param player table The player object
function wall_slide.start(player)
	common.animations.WALL_SLIDE.frame = 0
	player.animation = common.animations.WALL_SLIDE
	player.direction = -player.wall_direction
	wall_slide.grace_frames = 0
	audio.play_footstep()
end

--- Handles input during wall slide. Jump triggers wall jump, releasing wall starts grace period.
--- @param player table The player object
function wall_slide.input(player)
	if controls.jump_pressed() then
		player.wall_jump_dir = player.wall_direction
		player.set_state(player.states.wall_jump)
		return
	end

	if common.is_pressing_into_wall(player) then
		wall_slide.grace_frames = 0
	else
		wall_slide.grace_frames = wall_slide.grace_frames + 1
		if wall_slide.grace_frames >= WALL_SLIDE_GRACE_FRAMES then
			player.set_state(player.states.air)
		end
	end

	common.handle_dash(player)
end

--- Updates wall slide. Limits fall speed while sliding, normal gravity during grace period.
--- @param player table The player object
--- @param dt number Delta time
function wall_slide.update(player, dt)
	local in_grace = wall_slide.grace_frames > 0

	if in_grace then
		player.vy = math.min(common.MAX_FALL_SPEED, player.vy + common.GRAVITY)
		if player.animation ~= common.animations.FALL then
			player.animation = common.animations.FALL
			common.animations.FALL.frame = 0
		end
	else
		player.vy = math.min(WALL_SLIDE_SPEED, player.vy + common.GRAVITY)
	end

	player.vx = -player.wall_direction * player.speed

	if player.is_grounded then
		player.set_state(player.states.idle)
	elseif player.wall_direction == 0 then
		player.set_state(player.states.air)
	end
end

--- Renders the player with wall slide or fall animation.
--- @param player table The player object
function wall_slide.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return wall_slide
