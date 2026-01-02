local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local animation = require("animation")
local player = {}

local GRAVITY = 1.5
local JUMP_VELOCITY = GRAVITY*14
local MAX_COYOTE = 3

player.run_boost = 2
player.x = 2
player.vx = 0
player.vy = 0
player.y = 2
player.is_grounded = true
player.box = { w = 0.9, h = 0.9, x = 0.05, y = 0.05 }
player.speed = 7
player.coyote_frames = 0
world.add_collider(player)

local animations = { 
	IDLE = animation.create("player_idle", 6), 
	RUN = animation.create("player_run", 8),
}

player.animation = animations.IDLE
player.animation.flipped = 1

local ANIM_SPEED = 7 -- Number of game frames per animation frame
local t = 0

function player.draw() 

  sprites.draw_player(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
  if config.bounding_boxes == true then
  	canvas.set_color("#FF0000")
  	canvas.draw_rect((player.x + player.box.x) * sprites.tile_size, (player.y + player.box.y) * sprites.tile_size, 
        player.box.w * sprites.tile_size, player.box.h * sprites.tile_size)
  end
end

function player.input()
	player.vx = 0
	player.vy = player.vy + GRAVITY
	local speed_boost = 1
	if canvas.is_key_down(canvas.keys.SHIFT) then
		speed_boost = player.run_boost
	end
	if canvas.is_key_down(canvas.keys.A) then
		player.vx = -player.speed * speed_boost
		player.animation.flipped = -1
	end
	if canvas.is_key_down(canvas.keys.D) then
		player.vx = player.speed * speed_boost
		player.animation.flipped = 1
	end
	if (canvas.is_key_pressed(canvas.keys.W) or canvas.is_mouse_pressed(0)) and player.is_grounded then
		player.vy = -JUMP_VELOCITY
		player.is_grounded = false
	end
end

function player.set_position(x, y)
	player.x = x
	player.y = y
	world.grid:update(player, player.x, player.y)
end

function player.update()
	local dt = canvas.get_delta()
	player.x = player.x + (player.vx * dt)
	player.y = player.y + (player.vy * dt)
	local cols = world.move(player)
	
	local on_ground = false
	for _, col in pairs(cols) do
		if col.normal.y < 0 then 
			on_ground = true
			player.is_grounded = true
			player.coyote_frames = 0
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

	if t % ANIM_SPEED == 0 then
		player.animation.frame = (player.animation.frame + 1) % player.animation.frame_count
	end
	
	if math.abs(player.vx) > 0 then 
		player.animation = animations.RUN 
	else
		player.animation = animations.IDLE
	end

	t = t + 1
end

return player