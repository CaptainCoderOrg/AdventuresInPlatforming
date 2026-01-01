local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local player = {}

local JUMP_VELOCITY = 30
local GRAVITY = 3
local MAX_COYOTE = 3

player.x = 2
player.vx = 0
player.vy = 0
player.y = 2
player.is_grounded = true
player.box = { w = 0.9, h = 0.9, x = 0.05, y = 0.05 }
player.speed = 10
player.coyote_frames = 0
world.add_collider(player)

function player.draw() 
  sprites.draw_tile(1, 7, player.x * sprites.tile_size, player.y * sprites.tile_size)
  if config.bounding_boxes == true then
  	canvas.set_color("#FF0000")
  	canvas.draw_rect((player.x + player.box.x) * sprites.tile_size, (player.y + player.box.y) * sprites.tile_size, 
        player.box.w * sprites.tile_size, player.box.h * sprites.tile_size)
  end
end

function player.input()
	player.vx = 0
	player.vy = player.vy + GRAVITY
	if canvas.is_key_down(canvas.keys.A) then
		player.vx = -player.speed
	end
	if canvas.is_key_down(canvas.keys.D) then
		player.vx = player.speed
	end
	if canvas.is_key_pressed(canvas.keys.W) and player.is_grounded then
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

end

return player