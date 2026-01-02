local canvas = require("canvas")

local sprites = {}

local TILE = 16
local SCALE = 2

sprites.tile_size = TILE * SCALE

canvas.assets.add_path("assets/")
canvas.assets.load_image("tilemap", "images/tilemap_packed.png")
canvas.assets.load_image("player_idle", "sprites/character/idle.png")
canvas.assets.load_image("player_run", "sprites/character/run.png")

function sprites.draw_player(anim, x, y)
	local x_adjust = 0
	if anim.flipped == 1 then x_adjust = sprites.tile_size end
	canvas.save()
	canvas.translate(x + x_adjust, y)
	canvas.scale(-anim.flipped, 1)
	canvas.draw_image(anim.name, 0, 0, sprites.tile_size, sprites.tile_size, anim.frame*TILE, 0, TILE, TILE)
	canvas.restore()
end

function sprites.draw_tile(tx, ty, dx, dy)
	canvas.draw_image(
		"tilemap",
		dx,
		dy,
		TILE * SCALE,
		TILE * SCALE, -- destination: x, y, width, height
		tx * TILE,
		ty * TILE,
		TILE,
		TILE -- source: x, y, width, height
	)
end

return sprites
