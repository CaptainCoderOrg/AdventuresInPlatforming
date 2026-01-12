local audio = require('audio')
local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local Animation = require('Animation')

local climb = { name = "climb" }

--- Initializes the climb state, setting velocity based on input direction.
--- @param player table The player object
function climb.start(player)
	player.animation = Animation.new(common.animations.CLIMB_UP)
	player.vx = 0
	player.is_climbing = true

	-- Set initial velocity based on input that triggered climb
	-- (climb.input() won't run until next frame)
	if controls.up_down() then
		player.vy = -player.climb_speed
	elseif controls.down_down() then
		player.vy = player.climb_speed
	else
		player.vy = 0
	end

	-- Lift player off ground to prevent ground collision blocking upward climb
	if player.is_grounded and player.vy < 0 then
		player.y = player.y - 0.1
		player.is_grounded = false
	end
end

--- Handles climb input: vertical movement, step off with left/right, jump, dash.
--- @param player table The player object
function climb.input(player)
	-- Vertical movement (left/right exits to run state)
	if controls.up_down() then
		player.vy = -player.climb_speed
	elseif controls.down_down() then
		player.vy = player.climb_speed
	elseif controls.left_down() then
		player.direction = -1
		player.is_climbing = false
		player:set_state(player.states.run)
		return
	elseif controls.right_down() then
		player.direction = 1
		player.is_climbing = false
		player:set_state(player.states.run)
		return
	else
		player.vy = 0
	end

	-- Jump off ladder
	if controls.jump_pressed() then
		player.is_climbing = false
		player.vy = -common.AIR_JUMP_VELOCITY
		audio.play_jump_sound()
		player:set_state(player.states.air)
		return
	end

	-- Dash off ladder
	if common.handle_dash(player) then
		player.is_climbing = false
		return
	end
end

--- Updates climb state: centering, exit conditions, and animation.
--- @param player table The player object
--- @param dt number Delta time
function climb.update(player, dt)
	player.is_grounded = false

	-- Gradually center on ladder while moving
	if player.vy ~= 0 and player.current_ladder then
		local ladder = player.current_ladder
		local target_x = ladder.x + 0.5 - (player.box.w / 2) - player.box.x
		local center_speed = 0.1

		if player.x < target_x then
			player.x = math.min(player.x + center_speed, target_x)
		elseif player.x > target_x then
			player.x = math.max(player.x - center_speed, target_x)
		end
	end

	-- Exit if player left ladder area
	if not player.can_climb then
		player.is_climbing = false
		-- If moving up, we exited at top - land on ladder top
		if player.vy < 0 and player.climb_state.last_ladder then
			player.y = player.climb_state.last_ladder.y - player.box.h - player.box.y + 0.2
			player.vy = 0
			player:set_state(player.states.idle)
		else
			player:set_state(player.states.air)
		end
		return
	end

	-- Remember ladder for when we exit at top
	player.climb_state.last_ladder = player.current_ladder

	-- Reached bottom: climbing down and touching ground = stand on ground
	if player.climb_touching_ground and controls.down_down() then
		player.is_climbing = false
		player.is_grounded = true
		player:set_state(player.states.idle)
		return
	end

	-- Animation switching based on velocity
	if player.vy < 0 then
		if player.animation.definition ~= common.animations.CLIMB_UP then
			player.animation = Animation.new(common.animations.CLIMB_UP)
		else
			player.animation:resume()
		end
	elseif player.vy > 0 then
		if player.animation.definition ~= common.animations.CLIMB_DOWN then
			player.animation = Animation.new(common.animations.CLIMB_DOWN)
		else
			player.animation:resume()
		end
	else
		-- Not moving - pause animation to freeze on current frame
		player.animation:pause()
	end
end

--- Renders the player using the climb animation.
--- @param player table The player object
function climb.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return climb
