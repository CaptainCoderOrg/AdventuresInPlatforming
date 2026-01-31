local common = {}

common.canvas = require('canvas')
common.sprites = require('sprites')
common.config = require('config')
common.world = require('world')

-- Base tile size in pixels (before scaling)
common.BASE_TILE = 16

-- Tiled tileset configuration (tileset_dungeon)
local TILESET_COLUMNS = 9  -- 144px / 16px
local TILESET_FIRSTGID = 1

--- Converts a Tiled global tile ID to tilemap (tx, ty) coordinates.
--- @param gid number Global tile ID from Tiled
--- @return number, number Tile x and y in the tileset
function common.gid_to_tilemap(gid)
	local local_id = gid - TILESET_FIRSTGID
	local tx = local_id % TILESET_COLUMNS
	local ty = math.floor(local_id / TILESET_COLUMNS)
	return tx, ty
end

--- Draws a collection tile image with proper height offset.
--- Tiled uses bottom-left origin, so tiles taller than BASE_TILE need Y adjustment.
---@param tile_image table Collection tile info {image, width, height}
---@param x number Tile X coordinate
---@param y number Tile Y coordinate
---@param ts number Tile size in pixels (scaled)
function common.draw_collection_tile(tile_image, x, y, ts)
	local scale = common.config.ui.SCALE
	local height_offset = (tile_image.height / common.BASE_TILE - 1) * ts
	common.canvas.draw_image(
		tile_image.image,
		x * ts,
		y * ts - height_offset,
		tile_image.width * scale,
		tile_image.height * scale
	)
end

return common
