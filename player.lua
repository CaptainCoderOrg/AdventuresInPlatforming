local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local player = {}

player.x = 2
player.y = 2
player.box = { w = 0.9, h = 0.9, x = 0.05, y = 0.05 }
player.speed = 5
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
    local dt = canvas.get_delta()
	if canvas.is_key_down(canvas.keys.A) then
		player.x = player.x - player.speed * dt
	end
	if canvas.is_key_down(canvas.keys.D) then
		player.x = player.x + player.speed * dt
	end
	if canvas.is_key_down(canvas.keys.W) then
		player.y = player.y - player.speed * dt
	end
	if canvas.is_key_down(canvas.keys.S) then
		player.y = player.y + player.speed * dt
	end
	world.move(player)
end

function player.update()
	-- player.x = math.max(0, math.min(canvas.get_width() - player.width, player.x))
	-- player.y = math.max(0, math.min(canvas.get_height() - player.height, player.y))
end

return player