local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')

--- Air state: Player is airborne (jumping or falling).
--- Transitions to idle on landing, wall_slide when pressing into wall, or allows air jump/dash.
local air = { name = "air" }

--- Called when entering air state.
--- @param player table The player object
function air.start(player)
end

--- Updates air state. Applies gravity and manages animation based on vertical velocity.
--- @param player table The player object
--- @param dt number Delta time
function air.update(player, dt)
	common.handle_gravity(player)
	if player.is_grounded then
		player.set_state(player.states.idle)
		audio.play_landing_sound()
	elseif player.has_wall_slide and player.vy > 0 and player.wall_direction ~= 0 then
		if common.is_pressing_into_wall(player) then
			player.set_state(player.states.wall_slide)
		end
	elseif player.vy > 0 and player.animation ~= common.animations.FALL then
		player.animation = common.animations.FALL
		common.animations.FALL.frame = 0
		player.is_air_jumping = false
	elseif player.vy < 0 then
		if player.is_air_jumping and player.animation ~= common.animations.AIR_JUMP then
			player.animation = common.animations.AIR_JUMP
			common.animations.AIR_JUMP.frame = 0
		elseif not player.is_air_jumping and player.animation ~= common.animations.JUMP then
			player.animation = common.animations.JUMP
			common.animations.JUMP.frame = 0
		end
	end
end

--- Handles input while airborne. Allows horizontal movement, dash, and air jump.
--- @param player table The player object
function air.input(player)
	if controls.left_down() then
		player.direction = -1
		player.vx = player.direction * player.air_speed
	elseif controls.right_down() then
		player.direction = 1
		player.vx = player.direction * player.air_speed
	else
		player.vx = 0
	end
	common.handle_block(player)
	common.handle_attack(player)
	common.handle_dash(player)
	common.handle_air_jump(player)
	common.handle_climb(player)
end

--- Renders the player with current air animation (jump, air jump, or fall).
--- @param player table The player object
function air.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return air
