local common = require('platforms/common')
local canvas = common.canvas
local sprites = common.sprites
local config = common.config
local world = common.world

local slopes = {}

slopes.tiles = {}
slopes.colliders = {}

--- Adds a slope tile at the given position.
--- @param x number Tile X coordinate
--- @param y number Tile Y coordinate
--- @param slope_type string Type of slope ('/' for right-facing)
function slopes.add_tile(x, y, slope_type)
	local key = x .. "," .. y
	slopes.tiles[key] = { x = x, y = y, slope_type = slope_type }
end

--- Gets the vertices for a slope type in tile coordinates.
--- @param x number Tile X coordinate
--- @param y number Tile Y coordinate
--- @param slope_type string Type of slope
--- @return table[] Array of {x, y} vertices
local function get_slope_vertices(x, y, slope_type)
	if slope_type == "/" then
		-- Right-facing slope: bottom-left, bottom-right, top-right
		return {
			{ x = x, y = y + 1 },       -- bottom-left
			{ x = x + 1, y = y + 1 },   -- bottom-right
			{ x = x + 1, y = y },       -- top-right
		}
	elseif slope_type == "\\" then
		-- Left-facing slope: bottom-left, bottom-right, top-left
		return {
			{ x = x, y = y + 1 },       -- bottom-left
			{ x = x + 1, y = y + 1 },   -- bottom-right
			{ x = x, y = y },           -- top-left
		}
	end
	return {}
end

--- Builds colliders for all slope tiles.
--- Each slope gets its own polygon collider (no merging).
function slopes.build_colliders()
	for key, tile in pairs(slopes.tiles) do
		local vertices = get_slope_vertices(tile.x, tile.y, tile.slope_type)
		if #vertices >= 3 then
			local col = {
				x = tile.x,
				y = tile.y,
				vertices = vertices,
				slope_type = tile.slope_type,
				is_slope = true,
			}
			table.insert(slopes.colliders, col)
			world.add_polygon(col, vertices)
		end
	end
end

--- Draws all slope tiles.
function slopes.draw()
	local ts = sprites.tile_size

	for _, tile in pairs(slopes.tiles) do
		local vertices = get_slope_vertices(tile.x, tile.y, tile.slope_type)
		if #vertices >= 3 then
			-- Save canvas state before clipping
			canvas.save()

			-- Create triangular clipping path
			canvas.begin_path()
			canvas.move_to(vertices[1].x * ts, vertices[1].y * ts)
			for i = 2, #vertices do
				canvas.line_to(vertices[i].x * ts, vertices[i].y * ts)
			end
			canvas.close_path()
			canvas.clip()

			-- Draw wall sprite within clipped area
			sprites.draw_tile(4, 3, tile.x * ts, tile.y * ts)

			-- Restore canvas state (removes clipping)
			canvas.restore()
		end
	end

	-- Debug drawing
	if config.bounding_boxes then
		canvas.set_color("#00ff1179")
		for _, col in ipairs(slopes.colliders) do
			local verts = col.vertices
			for i = 1, #verts do
				local v1 = verts[i]
				local v2 = verts[i % #verts + 1]
				canvas.draw_line(
					v1.x * ts,
					v1.y * ts,
					v2.x * ts,
					v2.y * ts
				)
			end
		end
	end
end

--- Clears all slope data (for level reloading).
function slopes.clear()
	slopes.tiles = {}
	for _, col in ipairs(slopes.colliders) do
		world.remove_collider(col)
	end
	slopes.colliders = {}
end

return slopes
