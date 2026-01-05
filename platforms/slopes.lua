local common = require('platforms/common')
local canvas = common.canvas
local sprites = common.sprites
local config = common.config
local world = common.world
local walls = require('platforms/walls')

local slopes = {}

slopes.tiles = {}
slopes.colliders = {}

--- Adds a slope tile at the given position.
--- @param x number Tile X coordinate
--- @param y number Tile Y coordinate
--- @param slope_type string Type of slope ('/' or '\')
function slopes.add_tile(x, y, slope_type)
	local key = x .. "," .. y
	slopes.tiles[key] = { x = x, y = y, slope_type = slope_type }
end

--- Finds all connected groups of slope tiles using flood fill.
--- Uses 4-directional connectivity, only groups tiles of the same type.
--- @param tiles table<string, table> The slope tiles lookup
--- @return table[] Array of groups, each group is array of tiles
local function find_connected_groups(tiles)
	local visited = {}
	local groups = {}

	for key, tile in pairs(tiles) do
		if not visited[key] then
			local group = {}
			local stack = { tile }
			local group_type = tile.slope_type

			while #stack > 0 do
				local current = table.remove(stack)
				local ckey = current.x .. "," .. current.y

				if not visited[ckey] and tiles[ckey] then
					visited[ckey] = true
					table.insert(group, tiles[ckey])

					-- 4-directional neighbors (orthogonal only, same type)
					local neighbors = {
						{ x = current.x - 1, y = current.y },
						{ x = current.x + 1, y = current.y },
						{ x = current.x, y = current.y - 1 },
						{ x = current.x, y = current.y + 1 },
					}
					for _, n in ipairs(neighbors) do
						local nkey = n.x .. "," .. n.y
						if tiles[nkey] and not visited[nkey]
						   and tiles[nkey].slope_type == group_type then
							table.insert(stack, n)
						end
					end
				end
			end

			if #group > 0 then
				table.insert(groups, group)
			end
		end
	end

	return groups
end

--- Gets the bounding box of a group of tiles.
--- @param group table[] Array of tiles with x, y coordinates
--- @return number, number, number, number min_x, min_y, max_x, max_y
local function get_group_bounds(group)
	local min_x, min_y = math.huge, math.huge
	local max_x, max_y = -math.huge, -math.huge

	for _, tile in ipairs(group) do
		min_x = math.min(min_x, tile.x)
		min_y = math.min(min_y, tile.y)
		max_x = math.max(max_x, tile.x)
		max_y = math.max(max_y, tile.y)
	end

	return min_x, min_y, max_x, max_y
end

--- Checks if a wall or slope exists at the given tile coordinates.
--- @param x number Tile X coordinate
--- @param y number Tile Y coordinate
--- @return boolean
local function has_solid_at(x, y)
	local key = x .. "," .. y
	return walls.tiles[key] ~= nil or slopes.tiles[key] ~= nil
end

--- Checks which edges of a bounding box are adjacent to walls or other slopes.
--- @param min_x number
--- @param min_y number
--- @param max_x number
--- @param max_y number
--- @return table { left=bool, right=bool, above=bool, below=bool }
local function check_adjacency(min_x, min_y, max_x, max_y)
	local adjacency = { left = false, right = false, above = false, below = false }

	-- Check left edge (x = min_x - 1)
	for y = min_y, max_y do
		if has_solid_at(min_x - 1, y) then
			adjacency.left = true
			break
		end
	end

	-- Check right edge (x = max_x + 1)
	for y = min_y, max_y do
		if has_solid_at(max_x + 1, y) then
			adjacency.right = true
			break
		end
	end

	-- Check top edge (y = min_y - 1)
	for x = min_x, max_x do
		if has_solid_at(x, min_y - 1) then
			adjacency.above = true
			break
		end
	end

	-- Check bottom edge (y = max_y + 1)
	for x = min_x, max_x do
		if has_solid_at(x, max_y + 1) then
			adjacency.below = true
			break
		end
	end

	return adjacency
end

--- Gets triangle vertices based on slope type and neighbor hints.
--- Character type determines hypotenuse direction, neighbors determine filled side.
--- @param min_x number
--- @param min_y number
--- @param max_x number
--- @param max_y number
--- @param slope_type string '/' or '\'
--- @param adjacency table { left, right, above, below }
--- @return table[] Array of {x, y} vertices
local function get_triangle_vertices(min_x, min_y, max_x, max_y, slope_type, adjacency)
	-- Convert tile coordinates to world coordinates (add 1 to max for far edge)
	local left = min_x
	local right = max_x + 1
	local top = min_y
	local bottom = max_y + 1

	if slope_type == "/" then
		-- Hypotenuse BL ↔ TR
		if adjacency.below or adjacency.right then
			-- Floor ramp: BL, BR, TR (open TL)
			return {
				{ x = left, y = bottom },
				{ x = right, y = bottom },
				{ x = right, y = top },
			}
		else
			-- Ceiling slope: TL, BL, TR (open BR)
			return {
				{ x = left, y = top },
				{ x = left, y = bottom },
				{ x = right, y = top },
			}
		end
	else -- "\"
		-- Hypotenuse TL ↔ BR
		if adjacency.below or adjacency.left then
			-- Floor ramp: TL, BL, BR (open TR)
			return {
				{ x = left, y = top },
				{ x = left, y = bottom },
				{ x = right, y = bottom },
			}
		else
			-- Ceiling slope: TL, TR, BR (open BL)
			return {
				{ x = left, y = top },
				{ x = right, y = top },
				{ x = right, y = bottom },
			}
		end
	end
end

--- Builds colliders for all slope tiles.
--- Connected slope tiles form a single triangle collider.
function slopes.build_colliders()
	local groups = find_connected_groups(slopes.tiles)

	for _, group in ipairs(groups) do
		local min_x, min_y, max_x, max_y = get_group_bounds(group)
		local slope_type = group[1].slope_type
		local adjacency = check_adjacency(min_x, min_y, max_x, max_y)
		local vertices = get_triangle_vertices(min_x, min_y, max_x, max_y, slope_type, adjacency)

		local col = {
			bounds = { min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y },
			vertices = vertices,
			is_slope = true,
		}
		table.insert(slopes.colliders, col)
		world.add_polygon(col, vertices)
	end
end

--- Draws all slope colliders.
function slopes.draw()
	local ts = sprites.tile_size

	for _, col in ipairs(slopes.colliders) do
		local verts = col.vertices

		canvas.save()
		canvas.begin_path()
		canvas.move_to(verts[1].x * ts, verts[1].y * ts)
		for i = 2, #verts do
			canvas.line_to(verts[i].x * ts, verts[i].y * ts)
		end
		canvas.close_path()
		canvas.clip()

		local bounds = col.bounds
		for y = bounds.min_y, bounds.max_y do
			for x = bounds.min_x, bounds.max_x do
				sprites.draw_tile(4, 3, x * ts, y * ts)
			end
		end

		canvas.restore()
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
