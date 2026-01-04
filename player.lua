local audio = require('audio')
local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local controls = require('controls')
local player = {}
local idle_state = {}
local run_state = {}
local dash_state = {}
local air_state = {}

local GRAVITY = 1.5
local JUMP_VELOCITY = GRAVITY*14
local AIR_JUMP_VELOCITY = GRAVITY*12.25
local MAX_COYOTE = 4

player.x = 2
player.vx = 0
player.vy = 0
player.y = 2
player.is_grounded = true
player.box = { w = 0.7, h = 0.9, x = 0.15, y = 0.05 }
player.speed = 6
player.air_speed = player.speed * 1
player.coyote_frames = 0
player.direction = 1
player.jumps = 2
player.max_jumps = 2
player.is_air_jumping = false
player.state = idle_state

world.add_collider(player)

local t = 0

local DASH_FRAMES = 8
local DASH_COOLDOWN_FRAMES = DASH_FRAMES * 2
player.dash_cooldown = 0
player.dash_speed = player.speed * 3

local animations = { 
	IDLE = sprites.create_animation("player_idle", 6, 12), 
	RUN = sprites.create_animation("player_run", 8, 7),
	DASH = sprites.create_animation("player_dash", 4, 3),
	FALL = sprites.create_animation("player_fall", 3, 6),
	JUMP = sprites.create_animation("player_jump_up", 3, 6),
	AIR_JUMP = sprites.create_animation("player_double_jump", 4, 4)
}

player.animation = animations.IDLE
player.animation.flipped = 1

local function handle_gravity()
	player.vy = math.min(20, player.vy + GRAVITY)
	if not player.is_grounded then
		player.set_state(air_state)
	end
end

local function check_ground(cols)
	local on_ground = false
	for _, col in pairs(cols) do
		if col.normal.y < 0 then
			on_ground = true
			player.is_grounded = true
			player.coyote_frames = 0
			player.jumps = player.max_jumps
			player.vy = 0
			player.is_air_jumping = false
			break
		elseif col.normal.y > 0 then
			player.vy = 0
		end
	end

	if not on_ground then
		player.coyote_frames = player.coyote_frames + 1
		if player.is_grounded and player.coyote_frames > MAX_COYOTE then
			player.is_grounded = false
			player.jumps = player.max_jumps - 1
		end
	end
end

local function handle_jump()
	if controls.jump_pressed() and player.is_grounded then
		player.vy = -JUMP_VELOCITY
		player.jumps = player.jumps - 1
		return true
	end
	return false
end

local function handle_air_jump()
	if controls.jump_pressed() and player.jumps > 0 then
		player.vy = -AIR_JUMP_VELOCITY
		player.jumps = player.jumps - 1
		player.is_air_jumping = true
		return true
	end
	return false
end

local function handle_dash()
	if player.dash_cooldown > 0 then return false end
	if controls.dash_pressed() then
		player.set_state(dash_state)
		return true
	end
	return false
end

function player.set_position(x, y)
	player.x = x
	player.y = y
	world.grid:update(player, player.x, player.y)
end

function player.draw() 
	player.state.draw()

  if config.bounding_boxes == true then
  	canvas.set_color("#FF0000")
  	canvas.draw_rect((player.x + player.box.x) * sprites.tile_size, (player.y + player.box.y) * sprites.tile_size, 
        player.box.w * sprites.tile_size, player.box.h * sprites.tile_size)
  end
end

function player.input()
	player.state.input()
end

function player.update()
	local dt = canvas.get_delta()
	player.state.update(dt)

	player.animation.flipped = player.direction
	player.dash_cooldown = player.dash_cooldown - 1
	
	player.x = player.x + (player.vx * dt)
	player.y = player.y + (player.vy * dt)

	-- Check for collisions
	local cols = world.move(player)
	check_ground(cols)

	t = t + 1
	if t % player.animation.speed == 0 then
		player.animation.frame = (player.animation.frame + 1) % player.animation.frame_count
	end
end

function player.set_state(state)
	if player.state == state then return end
	player.state = state
	player.state.start()
	t = 0
end

function idle_state.start()
	animations.IDLE.frame = 0
	player.animation = animations.IDLE
end

function idle_state.input()

	if controls.left_down() then
		player.direction = -1
		player.set_state(run_state)
	elseif controls.right_down() then
		player.direction = 1
		player.set_state(run_state)
	end
	handle_dash()
	handle_jump()

end

function idle_state.update(dt)
	player.vx = 0
	handle_gravity()
end

function idle_state.draw()
  sprites.draw_animation(animations.IDLE, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

function run_state.start()
	animations.RUN.frame = 0
	player.animation = animations.RUN
	footstep_cooldown = 0
end

function run_state.input()
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	else
		player.set_state(idle_state)
	end
	handle_dash()
	handle_jump()
end

local footstep_cooldown = 0
local FOOTSTEP_COOLDOWN_TIME = (animations.RUN.frame_count * animations.RUN.speed)/2
function run_state.update(dt)
	handle_gravity()
	player.vx = player.direction * player.speed
	if footstep_cooldown <= 0 then
		audio.play_footstep()
		footstep_cooldown = FOOTSTEP_COOLDOWN_TIME * dt
	else
		footstep_cooldown = footstep_cooldown - dt
	end	
end

function run_state.draw()
	sprites.draw_animation(animations.RUN, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

function dash_state.start()
	animations.DASH.frame = 0
	dash_state.direction = player.direction
	dash_state.duration = DASH_FRAMES
	player.vy = 0
	player.animation = animations.DASH
	audio.play_sfx(audio.dash)
end

function dash_state.input()
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if dash_state.direction ~= player.direction then dash_state.duration = 0 end
	if player.is_grounded then
		if handle_jump() then dash_state.duration = 0 end
	else
		if handle_air_jump() then dash_state.duration = 0 end
	end
end

function dash_state.update(dt)
	if dash_state.duration > 0 then
		player.vy = player.is_grounded and GRAVITY or 0
	end
	player.vx = player.direction * player.dash_speed
	dash_state.duration = dash_state.duration - 1

	if dash_state.duration < 0 then
		player.dash_cooldown = DASH_COOLDOWN_FRAMES
		if not player.is_grounded then
			player.set_state(air_state)
		elseif controls.left_down() or controls.right_down() then
			player.set_state(run_state)
		else
			player.set_state(idle_state)
		end
	end
end

function dash_state.draw()
	sprites.draw_animation(animations.DASH, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

function air_state.start()
	
end

function air_state.update(dt)
	handle_gravity()
	if player.is_grounded then
		player.set_state(idle_state)
	elseif player.vy > 0 and player.animation ~= animations.FALL then
		player.animation = animations.FALL
		animations.FALL.frame = 0
		player.is_air_jumping = false
	elseif player.vy < 0 then
		if player.is_air_jumping and player.animation ~= animations.AIR_JUMP then
			player.animation = animations.AIR_JUMP
			animations.AIR_JUMP.frame = 0
		elseif not player.is_air_jumping and player.animation ~= animations.JUMP then
			player.animation = animations.JUMP
			animations.JUMP.frame = 0
		end
	end
end

function air_state.input() 
	if controls.left_down() then
		player.direction = -1
		player.vx = player.direction * player.air_speed
	elseif controls.right_down() then
		player.direction = 1
		player.vx = player.direction * player.air_speed
	else
		player.vx = 0
	end
	handle_dash()
	handle_air_jump()
end

function air_state.draw()
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return player