local common = require('player.common')
local controls = require('controls')
local shield = require('player.shield')

--- Block move state: Player is moving slowly while blocking.
--- Maintains shield collider. Exits to block when stopping or airborne, idle when block released.
local block_move = { name = "block_move" }

--- Called when entering block_move state. Sets block_move animation and creates/updates shield.
--- Invalidates perfect block window (moving while blocking).
---@param player table The player object
function block_move.start(player)
	shield.init_state(player, common.animations.BLOCK_MOVE)
	shield.clear_perfect_window(player)
end

--- Handles input while block moving. Updates direction, exits to block or idle.
--- Allows attacking from block_move.
---@param player table The player object
function block_move.input(player)
	if shield.check_guard_break(player) then return end
	if not controls.block_down() then
		shield.exit_state(player)
		return
	end

	-- Allow attacking from block_move (shield removed on state transition)
	if common.handle_attack(player) then return end

	-- Exit to static block when airborne
	if not player.is_grounded then
		player:set_state(player.states.block)
		return
	end

	-- Update direction from input, or return to static block if no movement
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	else
		player:set_state(player.states.block)
	end
end

--- Updates block_move state. Applies slow movement, gravity, and updates shield position.
--- Movement only occurs on frames 3 and 4 (0-indexed: 2 and 3) for a deliberate stepping motion.
---@param player table The player object
---@param dt number Delta time
function block_move.update(player, dt)
	common.handle_gravity(player, dt)

	local kb = shield.decay_knockback(player, dt)
	if kb ~= 0 then
		player.vx = kb
	else
		-- Stepping motion: only apply velocity during mid-stride frames for deliberate feel
		local frame = player.animation.frame
		if frame == 2 or frame == 3 then
			local move_speed = player:get_speed() * common.BLOCK_MOVE_SPEED_MULTIPLIER
			player.vx = player.direction * move_speed

			-- Handle slopes like run state
			if player.vy >= 0 and player.is_grounded then
				local is_slope = math.abs(player.ground_normal.x) > 0.01
				if is_slope then
					local tangent = common.get_ground_tangent(player)
					player.vy = player.direction * move_speed * (tangent.y / tangent.x)
				end
			end
		else
			player.vx = 0
		end
	end

	shield.update(player)
end

--- Renders the player in block_move animation.
---@param player table The player object
function block_move.draw(player)
	common.draw_blocking(player)
end

return block_move
