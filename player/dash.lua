local Animation = require('Animation')
local audio = require('audio')
local common = require('player.common')
local controls = require('controls')
local weapon_sync = require('player.weapon_sync')

--- Dash state: Player performs a quick horizontal burst of speed.
--- Ignores gravity during dash. Can be cancelled by jumping or changing direction.
--- Uses the charge system on dash_amulet for cooldown (recharges over time).
local dash = { name = "dash" }

local DASH_DURATION = 12 / 60

--- Called when entering dash state. Locks direction, cancels vertical velocity, consumes charge.
--- @param player table The player object
function dash.start(player)
	player.dash_state.direction = player.direction
	player.dash_state.elapsed_time = 0
	player.vy = 0
	weapon_sync.consume_charge(player)
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

	-- Direction change cancels dash
	if player.dash_state.direction ~= player.direction then
		player.dash_state.elapsed_time = DASH_DURATION
	end

	-- Jump cancels dash (ground or air)
	if player.is_grounded then
		if common.handle_jump(player) then
			player.dash_state.elapsed_time = DASH_DURATION
		end
	elseif common.handle_air_jump(player) then
		player.dash_state.elapsed_time = DASH_DURATION
	end

	-- Attack cancels dash
	if common.handle_attack(player) then
		player.dash_state.elapsed_time = DASH_DURATION
	end
end

--- Updates dash state. Moves at dash speed until duration expires.
--- @param player table The player object
--- @param dt number Delta time
function dash.update(player, dt)
	player.vx = player.direction * player.dash_speed

	if player.dash_state.elapsed_time < DASH_DURATION then
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

	player.dash_state.elapsed_time = player.dash_state.elapsed_time + dt

	if player.dash_state.elapsed_time >= DASH_DURATION then
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
	common.draw(player)
end

return dash
