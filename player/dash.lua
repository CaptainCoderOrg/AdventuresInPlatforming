local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')

--- Dash state: Player performs a quick horizontal burst of speed.
--- Ignores gravity during dash. Can be cancelled by jumping or changing direction.
local dash = { name = "dash" }

local DASH_FRAMES = 8
local DASH_COOLDOWN_FRAMES = (DASH_FRAMES * 2)/60

--- Called when entering dash state. Locks direction and cancels vertical velocity.
--- @param player table The player object
function dash.start(player)
	player.dash_state.direction = player.direction
	player.dash_state.duration = DASH_FRAMES
	player.vy = 0
	player.has_dash = false
	player.animation = Animation.new(common.animations.DASH)
	audio.play_sfx(audio.dash, 0.15)
end

--- Handles input during dash. Direction change or jump cancels the dash.
--- @param player table The player object
function dash.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if player.dash_state.direction ~= player.direction then player.dash_state.duration = 0 end
	if player.is_grounded then
		if common.handle_jump(player) then player.dash_state.duration = 0 end
	else
		if common.handle_air_jump(player) then player.dash_state.duration = 0 end
	end

	if common.handle_attack(player) then
		player.dash_state.duration = 0
	end
end

--- Updates dash state. Moves at dash speed until duration expires.
--- @param player table The player object
--- @param dt number Delta time
function dash.update(player, dt)
	player.vx = player.direction * player.dash_speed

	if player.dash_state.duration > 0 then
		if player.is_grounded then
			local is_slope = math.abs(player.ground_normal.x) > 0.01
			if is_slope then
				local tangent = common.get_ground_tangent(player)
				player.vy = player.direction * player.dash_speed * (tangent.y / tangent.x)
			else
				player.vy = common.GRAVITY
			end
		else
			-- Air/ceiling: horizontal only, collision handles vertical positioning
			player.vy = 0
		end
	end

	player.dash_state.duration = player.dash_state.duration - 1

	if player.dash_state.duration < 0 then
		player.dash_cooldown = DASH_COOLDOWN_FRAMES
		if not player.is_grounded then
			player:set_state(player.states.air)
		elseif controls.left_down() or controls.right_down() then
			player:set_state(player.states.run)
		else
			player:set_state(player.states.idle)
		end
	end
end

--- Renders the player in dash animation.
--- @param player table The player object
function dash.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return dash
