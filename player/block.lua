local common = require('player.common')
local controls = require('controls')
local shield = require('player.shield')

--- Block state: Player is in a defensive stance.
--- Stops horizontal movement when grounded. Exits when block button is released.
--- Creates a shield collider that blocks projectiles from the front.
local block = { name = "block" }

--- Called when entering block state. Sets block animation and creates shield.
---@param player table The player object
function block.start(player)
	shield.init_state(player, common.animations.BLOCK)
end

--- Updates block state. Applies gravity, knockback physics, and updates shield position.
--- Decrements perfect block window each frame.
---@param player table The player object
---@param dt number Delta time
function block.update(player, dt)
	common.handle_gravity(player, dt)
	shield.update_perfect_window(player, dt)

	local kb = shield.decay_knockback(player, dt)
	if kb ~= 0 then
		player.vx = kb
	elseif player.is_grounded then
		player.vx = 0
	end

	shield.update(player)
end

--- Handles input while blocking. Allows direction change, exits on block release or guard break.
--- Transitions to block_move when moving while grounded. Allows attacking from block.
---@param player table The player object
function block.input(player)
	if shield.check_guard_break(player) then return end
	if not controls.block_down() then
		shield.exit_state(player)
		return
	end

	-- Allow attacking from block (shield removed on state transition)
	if common.handle_attack(player) then return end

	-- Update direction from input
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end

	-- Transition to block_move when grounded and moving
	if player.is_grounded and (controls.left_down() or controls.right_down()) then
		shield.clear_perfect_window(player)
		player:set_state(player.states.block_move)
	end
end

--- Renders the player in block animation.
---@param player table The player object
function block.draw(player)
	common.draw_blocking(player)
end

return block
