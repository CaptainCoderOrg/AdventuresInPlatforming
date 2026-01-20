local Animation = require('Animation')
local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')

--- Idle state: Player is standing still on the ground.
--- Transitions to run on movement input, or dash/jump when triggered.
local idle = { name = "idle" }

--- Called when entering idle state. Resets animation to idle.
--- @param player table The player object
function idle.start(player)
	player.animation = Animation.new(common.animations.IDLE)
end

--- Handles input while idle. Movement transitions to run state.
--- @param player table The player object
function idle.input(player)
	if common.check_cooldown_queues(player) then return end

	-- Check rest before attack (down+attack combo)
	if common.handle_rest(player) then return end

	if controls.left_down() then
		player.direction = -1
		player:set_state(player.states.run)
	elseif controls.right_down() then
		player.direction = 1
		player:set_state(player.states.run)
	end
	common.handle_throw(player)
	common.handle_hammer(player)
	common.handle_block(player)
	common.handle_attack(player)
	common.handle_dash(player)
	common.handle_jump(player)
	common.handle_climb(player)
end

--- Updates idle state. Stops horizontal movement and applies gravity.
--- @param player table The player object
--- @param dt number Delta time
function idle.update(player, dt)
	player.vx = 0
	common.handle_gravity(player, dt)
end

--- Renders the player in idle pose.
--- @param player table The player object
function idle.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return idle
