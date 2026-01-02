local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local player = {}

local GRAVITY = 1.5
local JUMP_VELOCITY = GRAVITY*14
local MAX_COYOTE = 4
local current_animation = nil


player.x = 2
player.vx = 0
player.vy = 0
player.y = 2
player.is_grounded = true
player.box = { w = 0.9, h = 0.9, x = 0.05, y = 0.05 }
player.speed = 7
player.coyote_frames = 0
player.direction = 1
player.jumps = 2
player.max_jumps = 2

world.add_collider(player)

local t = 0

local DASH_FRAMES = 12
local DASH_COOLDOWN_FRAMES = DASH_FRAMES * 3
player.dash_cooldown = 0
player.dash = 0
player.dash_speed = player.speed * 3

local animations = { 
	IDLE = sprites.create_animation("player_idle", 6, 12), 
	RUN = sprites.create_animation("player_run", 8, 7),
	DASH = sprites.create_animation("player_dash", 4, 3)
}

player.animation = animations.IDLE
player.animation.flipped = 1


function player.draw() 

  sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
  if config.bounding_boxes == true then
  	canvas.set_color("#FF0000")
  	canvas.draw_rect((player.x + player.box.x) * sprites.tile_size, (player.y + player.box.y) * sprites.tile_size, 
        player.box.w * sprites.tile_size, player.box.h * sprites.tile_size)
  end
end

function player.input()
	player.vx = 0
	player.vy = player.vy + GRAVITY

	if player.dash_cooldown <= 0 and (canvas.is_mouse_pressed(2) or canvas.is_key_pressed(canvas.keys.SHIFT)) then
		player.dash = DASH_FRAMES
		player.dash_cooldown = DASH_COOLDOWN_FRAMES
	end

	if player.dash > 0 then
		player.vx = player.direction * player.dash_speed
	elseif canvas.is_key_down(canvas.keys.A) then
		player.direction = -1
		player.vx = -player.speed
	elseif canvas.is_key_down(canvas.keys.D) then
		player.direction = 1
		player.vx = player.speed
	end

	if (canvas.is_key_pressed(canvas.keys.W) or canvas.is_mouse_pressed(0)) and player.jumps > 0 then
		player.vy = -JUMP_VELOCITY
		player.jumps = player.jumps - 1
	end

end

function player.set_position(x, y)
	player.x = x
	player.y = y
	world.grid:update(player, player.x, player.y)
end

function player.update()
	local dt = canvas.get_delta()
	player.animation.flipped = player.direction
	player.x = player.x + (player.vx * dt)
	player.y = player.y + (player.vy * dt)
	local cols = world.move(player)
	
	local on_ground = false
	for _, col in pairs(cols) do
		if col.normal.y < 0 then 
			on_ground = true
			player.is_grounded = true
			player.coyote_frames = 0
			player.jumps = player.max_jumps
			player.vy = 0
			break
		elseif col.normal.y > 0 then
			player.vy = 0
		end
	end

	if not on_ground then
		player.coyote_frames = player.coyote_frames + 1
		if player.coyote_frames > MAX_COYOTE then
			player.is_grounded = false
		end
	end

	if t % player.animation.speed == 0 then
		player.animation.frame = (player.animation.frame + 1) % player.animation.frame_count
	end
	
	if player.dash > 0 then 
		player.animation = animations.DASH
	elseif math.abs(player.vx) > 0 then 
		player.animation = animations.RUN 
	else
		player.animation = animations.IDLE
	end

	player.dash = player.dash - 1
	player.dash_cooldown = player.dash_cooldown - 1

	if current_animation ~= player.animation then
		current_animation = player.animation
		t = 0
	else
		t = t + 1
	end
	
end

return player