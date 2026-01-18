local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local Animation = require('Animation')

--- Block state: Player is in a defensive stance.
--- Stops horizontal movement when grounded. Exits when block button is released.
local block = { name = "block" }

--- Called when entering block state. Sets block animation.
--- @param player table The player object
function block.start(player)
	player.animation = Animation.new(common.animations.BLOCK)
end

--- Updates block state. Applies gravity and stops movement when grounded.
--- @param player table The player object
--- @param dt number Delta time
function block.update(player, dt)
	common.handle_gravity(player, dt)
	if player.is_grounded then
		player.vx = 0
	end
end

--- Handles input while blocking. Allows direction change, exits on block release.
--- @param player table The player object
function block.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if not controls.block_down() then
		player:set_state(player.states.idle)
	end
end

--- Renders the player in block animation.
--- @param player table The player object
function block.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return block
