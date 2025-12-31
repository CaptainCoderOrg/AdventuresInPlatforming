local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local player = {}

player.x = 25
player.y = 25
player.size = 1
player.width = player.size * sprites.tile_size
player.height = player.size * sprites.tile_size
player.speed = 200

function player.draw() 
  sprites.draw_tile(1, 7, player.x, player.y)
  if config.bounding_boxes == true then
  	canvas.set_color("#FF0000")
  	canvas.draw_rect(player.x, player.y, player.width, player.height)
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
end

function player.update()
	player.x = math.max(0, math.min(canvas.get_width() - player.width, player.x))
	player.y = math.max(0, math.min(canvas.get_height() - player.height, player.y))
end

return player