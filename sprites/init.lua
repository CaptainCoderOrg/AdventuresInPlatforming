local canvas = require("canvas")
local config = require("config")

canvas.assets.add_path("assets/")

local sprites = {}

sprites.tile_size = config.ui.TILE * config.ui.SCALE

--- Converts tile coordinate to pixel-aligned screen coordinate.
--- Rounds to nearest pixel to prevent sub-pixel jitter.
---@param tiles number Position in tile coordinates
---@return number Pixel-aligned screen coordinate
function sprites.px(tiles)
	return math.floor(tiles * sprites.tile_size + 0.5)
end

--- Returns a pixel-aligned Y position with hysteresis to prevent jitter.
--- Caches the last rendered position on the entity and only updates when
--- the new position differs by more than 1 pixel.
---@param entity table Entity to cache render position on
---@param tiles number Y position in tile coordinates
---@param pixel_offset number Offset in pixels (e.g., slope offset, pressure plate lift)
---@return number Stable pixel-aligned Y coordinate
function sprites.stable_y(entity, tiles, pixel_offset)
	local new_y = tiles * sprites.tile_size + (pixel_offset or 0)
	local cached_y = entity._render_y
	if not cached_y or math.abs(new_y - cached_y) >= 1 then
		entity._render_y = math.floor(new_y + 0.5)
	end
	return entity._render_y
end

sprites.player = require("sprites/player")
sprites.enemies = require("sprites/enemies")
sprites.effects = require("sprites/effects")
sprites.projectiles = require("sprites/projectiles")
sprites.ui = require("sprites/ui")
sprites.environment = require("sprites/environment")
sprites.controls = require("sprites/controls")
sprites.npcs = require("sprites/npcs")

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
---@param tileset string|nil Optional tileset key (defaults to tilemap)
function sprites.draw_tile(tx, ty, dx, dy, tileset)
	local base = config.ui.TILE
	local image = tileset or sprites.environment.tilemap
	canvas.draw_image(
		image,
		dx, dy, sprites.tile_size, sprites.tile_size,
		tx * base, ty * base, base, base
	)
end

return sprites
