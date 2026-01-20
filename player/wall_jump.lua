local common = require('player.common')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')

--- Wall jump state: Player leaps away from a wall with locked horizontal direction.
--- Transitions to idle on landing, wall_slide if hitting same wall, or air when falling.
local wall_jump = { name = "wall_jump" }

local WALL_JUMP_VELOCITY = common.GRAVITY * 12

--- Called when entering wall jump. Applies upward and outward velocity away from wall.
--- @param player table The player object
function wall_jump.start(player)
	local wall_dir = player.wall_jump_dir
	player.vy = -WALL_JUMP_VELOCITY
	player.vx = wall_dir * player:get_speed()
	player.direction = wall_dir
	player.wall_jump_state.locked_direction = -wall_dir
	player.animation = Animation.new(common.animations.JUMP)
	audio.play_wall_jump_sound()
end

--- Handles input during wall jump. Allows dash and air jump.
--- @param player table The player object
function wall_jump.input(player)
	common.handle_dash(player)
	common.handle_air_jump(player)
	common.handle_attack(player)
end

--- Updates wall jump. Applies gravity while maintaining locked horizontal direction.
--- @param player table The player object
--- @param dt number Delta time
function wall_jump.update(player, dt)
	common.apply_gravity(player, dt)

	player.vx = -player.wall_jump_state.locked_direction * player:get_speed()

	if player.is_grounded then
		player:set_state(player.states.idle)
	elseif player.wall_direction == player.wall_jump_state.locked_direction then
		player:set_state(player.states.wall_slide)
	elseif player.vy > 0 then
		player:set_state(player.states.air)
	end
end

--- Renders the player with jump animation.
--- @param player table The player object
function wall_jump.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return wall_jump
