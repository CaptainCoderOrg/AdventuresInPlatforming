local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local Animation = require('Animation')
local world = require('world')
local canvas = require('canvas')
local config = require('config')

--- Block state: Player is in a defensive stance.
--- Stops horizontal movement when grounded. Exits when block button is released.
--- Creates a shield collider that blocks projectiles from the front.
local block = { name = "block" }

-- Shield: 4px (0.25 tiles) wide, matches player height
local SHIELD_BOX = { w = 0.25, h = 0.85 }

--- Exits block state: removes shield, clears knockback, transitions to idle.
---@param player table The player object
local function exit_block(player)
	world.remove_shield(player)
	player.block_state.knockback_velocity = 0
	player:set_state(player.states.idle)
end

--- Called when entering block state. Sets block animation and creates shield.
---@param player table The player object
function block.start(player)
	player.animation = Animation.new(common.animations.BLOCK)
	player.block_state.knockback_velocity = 0
	world.add_shield(player, SHIELD_BOX)
end

--- Updates block state. Applies gravity, knockback physics, and updates shield position.
---@param player table The player object
---@param dt number Delta time
function block.update(player, dt)
	common.handle_gravity(player, dt)

	-- Apply knockback velocity (decays when grounded, maintains when airborne)
	local kb = player.block_state.knockback_velocity
	if kb ~= 0 then
		player.vx = kb
		-- Decay knockback when grounded (frame-rate independent)
		if player.is_grounded then
			kb = kb * (0.85 ^ (dt * 60))
			if math.abs(kb) < 0.1 then
				kb = 0
			end
			player.block_state.knockback_velocity = kb
		end
	elseif player.is_grounded then
		player.vx = 0
	end

	world.update_shield(player, SHIELD_BOX)
end

--- Handles input while blocking. Allows direction change, exits on block release or guard break.
---@param player table The player object
function block.input(player)
	-- Guard break: exit if fatigued (stamina < 0)
	if player:is_fatigued() then
		exit_block(player)
		return
	end

	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end

	if not controls.block_down() then
		exit_block(player)
	end
end

--- Renders the player in block animation.
---@param player table The player object
function block.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)

	-- Debug: draw shield bounding box (blue)
	if config.bounding_boxes then
		local x_offset
		if player.direction == 1 then
			x_offset = player.box.x + player.box.w
		else
			x_offset = player.box.x - SHIELD_BOX.w
		end
		local sx = (player.x + x_offset) * sprites.tile_size
		local sy = (player.y + player.box.y) * sprites.tile_size
		canvas.set_color("#0088FF")
		canvas.draw_rect(sx, sy, SHIELD_BOX.w * sprites.tile_size, SHIELD_BOX.h * sprites.tile_size)
	end
end

return block
