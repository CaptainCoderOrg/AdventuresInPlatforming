local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')

local climb = { name = "climb" }

-- Local animation state (independent of player.animation)
local animation = common.animations.CLIMB_UP
local frame_timer = 0

function climb.start(player)
	animation = common.animations.CLIMB_UP
	animation.frame = 0
	frame_timer = 0
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

function climb.input(player)
	-- Left/Right: step off ladder
	if controls.left_down() then
		player.direction = -1
		player.is_climbing = false
		player.set_state(player.states.run)
		return
	elseif controls.right_down() then
		player.direction = 1
		player.is_climbing = false
		player.set_state(player.states.run)
		return
	end

	-- Vertical movement
	if controls.up_down() then
		player.vy = -player.climb_speed
	elseif controls.down_down() then
		player.vy = player.climb_speed
	else
		player.vy = 0
	end

	-- Jump off ladder
	if controls.jump_pressed() then
		player.is_climbing = false
		common.handle_jump(player)
		player.set_state(player.states.air)
		return
	end

	-- Dash off ladder
	if common.handle_dash(player) then
		player.is_climbing = false
		return
	end
end

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

	-- Exit if player left ladder area (fell off side)
	if not player.can_climb then
		player.is_climbing = false
		player.set_state(player.states.air)
		return
	end

	-- Reached bottom: climbing down and touching ground = stand on ground
	if player.climb_touching_ground and controls.down_down() then
		player.is_climbing = false
		player.is_grounded = true
		player.set_state(player.states.idle)
		return
	end

	-- Animation switching based on velocity
	if player.vy < 0 then
		-- Moving up
		if animation ~= common.animations.CLIMB_UP then
			animation = common.animations.CLIMB_UP
			animation.frame = 0
			frame_timer = 0
		end
		-- Advance animation
		frame_timer = frame_timer + 1
		if frame_timer >= animation.speed then
			frame_timer = 0
			animation.frame = (animation.frame + 1) % animation.frame_count
		end
	elseif player.vy > 0 then
		-- Moving down
		if animation ~= common.animations.CLIMB_DOWN then
			animation = common.animations.CLIMB_DOWN
			animation.frame = 0
			frame_timer = 0
		end
		-- Advance animation
		frame_timer = frame_timer + 1
		if frame_timer >= animation.speed then
			frame_timer = 0
			animation.frame = (animation.frame + 1) % animation.frame_count
		end
	else
		-- Not moving: pause at frame 0
		animation.frame = 0
		frame_timer = 0
	end
end

function climb.draw(player)
	-- Use local animation, not player.animation
	sprites.draw_animation(animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return climb
