local canvas = require("canvas")
local config = require("config")

canvas.assets.add_path("assets/")

local sprites = {}

sprites.tile_size = config.ui.TILE * config.ui.SCALE

sprites.player = require("sprites/player")
sprites.enemies = require("sprites/enemies")
sprites.effects = require("sprites/effects")
sprites.projectiles = require("sprites/projectiles")
sprites.ui = require("sprites/ui")
sprites.environment = require("sprites/environment")
sprites.controls = require("sprites/controls")

--- Draws a ladder tile at the given screen position.
---@param dx number Destination x in screen pixels
---@param dy number Destination y in screen pixels
---@param sprite string|nil Sprite key (defaults to ladder_mid)
function sprites.draw_ladder(dx, dy, sprite)
	sprite = sprite or sprites.environment.ladder_mid
	canvas.draw_image(sprite, dx, dy, sprites.tile_size, sprites.tile_size)
end

--- Draws a bridge tile at the given screen position.
--- Bridge sprites are 16x8px, aligned to top of tile.
---@param dx number Destination x in screen pixels
---@param dy number Destination y in screen pixels
---@param sprite string Sprite key (bridge_left, bridge_middle, or bridge_right)
function sprites.draw_bridge(dx, dy, sprite)
	local bridge_height = sprites.tile_size / 2 -- 8px scaled
	canvas.draw_image(sprite, dx, dy, sprites.tile_size, bridge_height)
end

--- Draws a tile from the tilemap at the given screen position.
---@param tx number Tile x coordinate in tilemap
---@param ty number Tile y coordinate in tilemap
---@param dx number Destination x in screen pixels
---@param dy number Destination y in screen pixels
function sprites.draw_tile(tx, ty, dx, dy)
	local base = config.ui.TILE
	canvas.draw_image(
		sprites.environment.tilemap,
		dx, dy, sprites.tile_size, sprites.tile_size,
		tx * base, ty * base, base, base
	)
end

return sprites
