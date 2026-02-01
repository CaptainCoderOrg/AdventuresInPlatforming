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
---@param gid number Global tile ID from Tiled
---@return number, number Tile x and y in the tileset
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

--- Draws a tile using Tiled tileset info (collection tile or image-based tileset).
--- Returns true if the tile was drawn, false if fallback rendering is needed.
---@param tile table Tile with tile_id, tileset_info, and optional tile_image
---@param ts number Tile size in pixels (scaled)
---@return boolean True if tile was drawn using Tiled data
function common.draw_tiled_tile(tile, ts)
	if tile.tile_image then
		common.draw_collection_tile(tile.tile_image, tile.x, tile.y, ts)
		return true
	end

	if tile.tile_id and tile.tileset_info then
		local info = tile.tileset_info
		local local_id = tile.tile_id - info.firstgid
		local tx = local_id % info.columns
		local ty = math.floor(local_id / info.columns)
		common.sprites.draw_tile(tx, ty, tile.x * ts, tile.y * ts, info.tileset_image)
		return true
	end

	return false
end

return common
