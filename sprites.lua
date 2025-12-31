local canvas = require("canvas")
local sprites = {}

local TILE = 16
local SCALE = 2

sprites.tile_size = TILE * SCALE

canvas.assets.add_path("assets/")
canvas.assets.load_image("tilemap", "images/tilemap_packed.png")

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
