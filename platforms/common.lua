local common = {}

common.canvas = require('canvas')
common.sprites = require('sprites')
common.config = require('config')
common.world = require('world')
local tile_transform = require('platforms/tile_transform')

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
---@param flip_h boolean|nil Horizontal flip flag
---@param flip_v boolean|nil Vertical flip flag
function common.draw_collection_tile(tile_image, x, y, ts, flip_h, flip_v)
	local scale = common.config.ui.SCALE
	local height_offset = (tile_image.height / common.BASE_TILE - 1) * ts
	local width_scaled = tile_image.width * scale
	local height_scaled = tile_image.height * scale
	local draw_x = x * ts
	local draw_y = y * ts - height_offset

	if tile_transform.has_transform(flip_h, flip_v) then
		common.canvas.save()
		common.canvas.translate(draw_x, draw_y)
		tile_transform.apply(flip_h, flip_v, width_scaled, height_scaled)
		common.canvas.draw_image(tile_image.image, 0, 0, width_scaled, height_scaled)
		common.canvas.restore()
	else
		common.canvas.draw_image(tile_image.image, draw_x, draw_y, width_scaled, height_scaled)
	end
end

--- Draws a tile using Tiled tileset info (collection tile or image-based tileset).
--- Returns true if the tile was drawn, false if fallback rendering is needed.
---@param tile table Tile with tile_id, tileset_info, optional tile_image, and flip flags
---@param ts number Tile size in pixels (scaled)
---@return boolean True if tile was drawn using Tiled data
function common.draw_tiled_tile(tile, ts)
	if tile.tile_image then
		common.draw_collection_tile(tile.tile_image, tile.x, tile.y, ts, tile.flip_h, tile.flip_v)
		return true
	end

	if tile.tile_id and tile.tileset_info then
		local info = tile.tileset_info
		local local_id = tile.tile_id - info.firstgid
		local tx = local_id % info.columns
		local ty = math.floor(local_id / info.columns)
		local draw_x = tile.x * ts
		local draw_y = tile.y * ts

		if tile_transform.has_transform(tile.flip_h, tile.flip_v) then
			common.canvas.save()
			common.canvas.translate(draw_x, draw_y)
			tile_transform.apply(tile.flip_h, tile.flip_v, ts, ts)
			common.sprites.draw_tile(tx, ty, 0, 0, info.tileset_image)
			common.canvas.restore()
		else
			common.sprites.draw_tile(tx, ty, draw_x, draw_y, info.tileset_image)
		end
		return true
	end

	return false
end

return common
