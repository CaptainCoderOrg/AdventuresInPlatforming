local Animation = require('Animation')
local audio = require('audio')
local common = require('player.common')
local controls = require('controls')

--- Air state: Player is airborne (jumping or falling).
--- Transitions to idle on landing, wall_slide when pressing into wall, or allows air jump/dash.
local air = { name = "air" }

--- Called when entering air state.
--- @param player table The player object
function air.start(player)
end

--- Returns the appropriate air animation based on player state.
---@param player table The player object
---@return table|nil Animation definition, or nil if no change needed
local function get_target_animation(player)
	if player.vy > 0 then
		return common.animations.FALL
	elseif player.vy < 0 then
		return player.is_air_jumping and common.animations.AIR_JUMP or common.animations.JUMP
	end
	return nil
end

--- Updates air state. Applies gravity and manages animation based on vertical velocity.
--- @param player table The player object
--- @param dt number Delta time
function air.update(player, dt)
	common.handle_gravity(player, dt)

	if player.is_grounded then
		player:set_state(player.states.idle)
		audio.play_landing_sound()
		return
	end

	-- Check for wall slide entry
	if player.has_wall_slide and player.vy > 0 and player.wall_direction ~= 0 then
		if common.is_pressing_into_wall(player) then
			player:set_state(player.states.wall_slide)
			return
		end
	end

	-- Update animation based on vertical velocity
	local target = get_target_animation(player)
	if target and player.animation.definition ~= target then
		player.animation = Animation.new(target)
		if player.vy > 0 then
			player.is_air_jumping = false
		end
	end
end

--- Handles input while airborne. Allows horizontal movement, dash, and air jump.
--- @param player table The player object
function air.input(player)
	if common.check_cooldown_queues(player) then return end

	if controls.left_down() then
		player.direction = -1
		player.vx = player.direction * player:get_speed()
	elseif controls.right_down() then
		player.direction = 1
		player.vx = player.direction * player:get_speed()
	else
		player.vx = 0
	end
	common.handle_weapon_swap(player)
	common.handle_throw(player)
	common.handle_block(player)
	common.handle_attack(player)
	common.handle_dash(player)
	if not common.handle_jump(player) then
		common.handle_air_jump(player)
	end
	common.handle_climb(player)
end

--- Renders the player with current air animation (jump, air jump, or fall).
--- @param player table The player object
function air.draw(player)
	common.draw(player)
end

return air
