local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')

--- Idle state: Player is standing still on the ground.
--- Transitions to run on movement input, or dash/jump when triggered.
local idle = { name = "idle" }

--- Called when entering idle state. Resets animation to idle.
--- @param player table The player object
function idle.start(player)
	common.animations.IDLE.frame = 0
	player.animation = common.animations.IDLE
end

--- Handles input while idle. Movement transitions to run state.
--- @param player table The player object
function idle.input(player)
	if controls.left_down() then
		player.direction = -1
		player.set_state(player.states.run)
	elseif controls.right_down() then
		player.direction = 1
		player.set_state(player.states.run)
	end
	common.handle_attack(player)
	common.handle_dash(player)
	common.handle_jump(player)
end

--- Updates idle state. Stops horizontal movement and applies gravity.
--- @param player table The player object
--- @param dt number Delta time
function idle.update(player, dt)
	player.vx = 0
	common.handle_gravity(player)
end

--- Renders the player in idle pose.
--- @param player table The player object
function idle.draw(player)
	sprites.draw_animation(common.animations.IDLE, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return idle
