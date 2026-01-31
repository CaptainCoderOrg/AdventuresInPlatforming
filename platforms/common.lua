local common = {}

common.canvas = require('canvas')
common.sprites = require('sprites')
common.config = require('config')
common.world = require('world')

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

return common
