local common = require('platforms/common')
local canvas = common.canvas
local sprites = common.sprites
local config = common.config
local world = common.world

local walls = {}

walls.tiles = {}
walls.solo_tiles = {}
walls.decorative_tiles = {}  -- Render-only tiles array (no collision), sorted by depth
walls.decorative_below = {}  -- Decorative tiles drawn below collision tiles
walls.decorative_above = {}  -- Decorative tiles drawn above collision tiles
walls.decorative_sorted = false  -- Track if decorative tiles need sorting/splitting
walls.walls_depth = 0  -- Layer depth of collision tiles (for splitting decorative tiles)
walls.colliders = {}
walls.tile_to_collider = {}

--- Returns tiles from lookup sorted by x, then y coordinate.
---@param tile_lookup table<string, {x: number, y: number}>
---@return {x: number, y: number}[]
local function get_sorted_tiles(tile_lookup)
	local sorted = {}
	for _, tile in pairs(tile_lookup) do
		table.insert(sorted, tile)
	end
	table.sort(sorted, function(a, b)
		if a.x == b.x then return a.y < b.y end
		return a.x < b.x
	end)
	return sorted
end

--- Finds all connected components of tiles using flood fill.
---@param tile_lookup table<string, {x: number, y: number}>
---@return table[] Array of components, each containing tile arrays
local function find_connected_components(tile_lookup)
	local visited = {}
	local components = {}

	for key, tile in pairs(tile_lookup) do
		if not visited[key] then
			local component = {}
			local stack = { tile }

			while #stack > 0 do
				local current = table.remove(stack)
				local ckey = current.x .. "," .. current.y

				if not visited[ckey] and tile_lookup[ckey] then
					visited[ckey] = true
					table.insert(component, current)

					local neighbors = {
						{ x = current.x - 1, y = current.y },
						{ x = current.x + 1, y = current.y },
						{ x = current.x, y = current.y - 1 },
						{ x = current.x, y = current.y + 1 },
					}
					for _, n in ipairs(neighbors) do
						local nkey = n.x .. "," .. n.y
						if tile_lookup[nkey] and not visited[nkey] then
							table.insert(stack, n)
						end
					end
				end
			end

			if #component > 0 then
				table.insert(components, component)
			end
		end
	end

	return components
end

--- Traces ALL boundary loops of a tile component.
--- Returns multiple polygons if the shape has holes.
---@param tiles table[] Array of {x, y} tiles
---@return table[][] Array of vertex arrays
local function trace_all_boundaries(tiles)
	local tile_set = {}
	for _, t in ipairs(tiles) do
		tile_set[t.x .. "," .. t.y] = true
	end

	-- Collect all perimeter edges
	local edges = {}
	for _, tile in ipairs(tiles) do
		local x, y = tile.x, tile.y
		if not tile_set[x .. "," .. (y - 1)] then
			table.insert(edges, { x1 = x, y1 = y, x2 = x + 1, y2 = y, dir = "top" })
		end
		if not tile_set[x .. "," .. (y + 1)] then
			table.insert(edges, { x1 = x + 1, y1 = y + 1, x2 = x, y2 = y + 1, dir = "bottom" })
		end
		if not tile_set[(x - 1) .. "," .. y] then
			table.insert(edges, { x1 = x, y1 = y + 1, x2 = x, y2 = y, dir = "left" })
		end
		if not tile_set[(x + 1) .. "," .. y] then
			table.insert(edges, { x1 = x + 1, y1 = y, x2 = x + 1, y2 = y + 1, dir = "right" })
		end
	end

	if #edges == 0 then return {} end

	-- Build adjacency map
	local edges_from_start = {}
	for _, e in ipairs(edges) do
		local key = e.x1 .. "," .. e.y1
		edges_from_start[key] = edges_from_start[key] or {}
		table.insert(edges_from_start[key], e)
	end

	local used_edges = {}
	local function edge_key(e)
		return e.x1 .. "," .. e.y1 .. "-" .. e.x2 .. "," .. e.y2
	end

	local function find_start_edge()
		local best = nil
		for _, e in ipairs(edges) do
			if not used_edges[edge_key(e)] then
				if e.dir == "top" then
					if not best or e.y1 < best.y1 or (e.y1 == best.y1 and e.x1 < best.x1) then
						best = e
					end
				elseif not best then
					best = e
				end
			end
		end
		return best
	end

	local function find_next_edge(x, y)
		local key = x .. "," .. y
		local candidates = edges_from_start[key]
		if not candidates then return nil end
		for _, e in ipairs(candidates) do
			if not used_edges[edge_key(e)] then
				return e
			end
		end
		return nil
	end

	local polygons = {}
	while true do
		local start_edge = find_start_edge()
		if not start_edge then break end

		local vertices = {}
		local current = start_edge
		local safety = #edges + 1

		repeat
			local key = edge_key(current)
			if used_edges[key] then break end
			used_edges[key] = true
			table.insert(vertices, { x = current.x1, y = current.y1 })
			current = find_next_edge(current.x2, current.y2)
			safety = safety - 1
		until current == nil or safety <= 0

		if #vertices >= 3 then
			table.insert(polygons, vertices)
		end
	end

	return polygons
end

--- Simplifies a polygon by removing collinear points.
---@param vertices table[]
---@return table[]
local function simplify_polygon(vertices)
	if #vertices < 3 then return vertices end

	local result = {}
	local n = #vertices

	for i = 1, n do
		local prev = vertices[(i - 2) % n + 1]
		local curr = vertices[i]
		local next = vertices[i % n + 1]

		local dx1 = curr.x - prev.x
		local dy1 = curr.y - prev.y
		local dx2 = next.x - curr.x
		local dy2 = next.y - curr.y

		local cross = dx1 * dy2 - dy1 * dx2
		if cross ~= 0 then
			table.insert(result, curr)
		end
	end

	return result
end

--- Merges tiles into rectangular colliders (fallback for shapes with holes).
---@param tiles table[]
---@return table[]
local function merge_into_rectangles(tiles)
	local tile_lookup = {}
	for _, t in ipairs(tiles) do
		tile_lookup[t.x .. "," .. t.y] = t
	end

	local sorted = get_sorted_tiles(tile_lookup)
	local merged = {}
	local vertical_colliders = {}

	for _, tile in ipairs(sorted) do
		local key = tile.x .. "," .. tile.y
		if not merged[key] then
			local run_tiles = { tile }
			merged[key] = true

			local next_y = tile.y + 1
			local next_key = tile.x .. "," .. next_y
			while tile_lookup[next_key] and not merged[next_key] do
				table.insert(run_tiles, tile_lookup[next_key])
				merged[next_key] = true
				next_y = next_y + 1
				next_key = tile.x .. "," .. next_y
			end

			table.insert(vertical_colliders, {
				x = tile.x,
				y = tile.y,
				box = { x = 0, y = 0, w = 1, h = #run_tiles },
				tiles = run_tiles
			})
		end
	end

	local groups = {}
	for _, col in ipairs(vertical_colliders) do
		local key = col.y .. "," .. col.box.h
		groups[key] = groups[key] or {}
		table.insert(groups[key], col)
	end

	local result = {}
	for _, group in pairs(groups) do
		table.sort(group, function(a, b) return a.x < b.x end)

		local i = 1
		while i <= #group do
			local start_col = group[i]
			local merged_tiles = {}
			for _, t in ipairs(start_col.tiles) do
				table.insert(merged_tiles, t)
			end
			local total_width = start_col.box.w
			local j = i + 1

			while j <= #group and group[j].x == start_col.x + total_width do
				for _, t in ipairs(group[j].tiles) do
					table.insert(merged_tiles, t)
				end
				total_width = total_width + group[j].box.w
				j = j + 1
			end

			table.insert(result, {
				x = start_col.x,
				y = start_col.y,
				box = { x = 0, y = 0, w = total_width, h = start_col.box.h },
				tiles = merged_tiles
			})

			i = j
		end
	end

	return result
end

--- Creates colliders from tiles using polygons when possible, rectangles for shapes with holes.
---@param tile_lookup table<string, {x: number, y: number}>
---@return table[]
local function create_colliders(tile_lookup)
	local components = find_connected_components(tile_lookup)
	local colliders = {}

	for _, component in ipairs(components) do
		local boundaries = trace_all_boundaries(component)

		if #boundaries == 1 then
			-- Solid shape: use single polygon (no seams)
			local vertices = simplify_polygon(boundaries[1])
			if #vertices >= 3 then
				table.insert(colliders, {
					vertices = vertices,
					tiles = component,
					is_polygon = true
				})
			end
		else
			-- Shape has holes: use rectangles (HC can't handle polygon holes)
			local rects = merge_into_rectangles(component)
			for _, rect in ipairs(rects) do
				rect.is_polygon = false
				table.insert(colliders, rect)
			end
		end
	end

	return colliders
end

--- Registers colliders with the physics world and updates tile-to-collider mapping.
---@param colliders table[] Array of collider definitions
local function register_colliders(colliders)
	for _, col in ipairs(colliders) do
		table.insert(walls.colliders, col)
		if col.is_polygon then
			world.add_polygon(col, col.vertices)
		else
			world.add_collider(col)
		end
		for _, t in ipairs(col.tiles) do
			walls.tile_to_collider[t.x .. "," .. t.y] = col
		end
	end
end

--- Adds a tile position to be merged later.
---@param x number Tile X coordinate
---@param y number Tile Y coordinate
---@param tile_id number|nil Optional Tiled global tile ID for tilemap rendering
---@param tileset_info table|nil Optional tileset info {tileset_image, columns, firstgid}
---@param tile_image table|nil Optional collection tile {image, width, height}
function walls.add_tile(x, y, tile_id, tileset_info, tile_image)
	local key = x .. "," .. y
	walls.tiles[key] = { x = x, y = y, tile_id = tile_id, tileset_info = tileset_info, tile_image = tile_image }
end

--- Adds a decorative tile (render only, no collision).
---@param x number Tile X coordinate
---@param y number Tile Y coordinate
---@param tile_id number|nil Tiled global tile ID for tilemap rendering
---@param tileset_info table|nil Optional tileset info {tileset_image, columns, firstgid}
---@param tile_image table|nil Optional collection tile {image, width, height}
---@param depth number|nil Layer depth for draw ordering (higher = drawn later/on top)
function walls.add_decorative_tile(x, y, tile_id, tileset_info, tile_image, depth)
	-- Use array index as key to allow multiple tiles at same position from different layers
	table.insert(walls.decorative_tiles, {
		x = x,
		y = y,
		tile_id = tile_id,
		tileset_info = tileset_info,
		tile_image = tile_image,
		depth = depth or 0
	})
	walls.decorative_sorted = false
end

--- Sets the layer depth of collision tiles.
--- Decorative tiles with depth > this value will be drawn above collision tiles.
---@param depth number Layer depth of the last collision tile layer
function walls.set_walls_depth(depth)
	walls.walls_depth = depth
	walls.decorative_sorted = false  -- Force re-split on next draw
end

--- Adds a solo tile that won't merge with adjacent tiles.
---@param x number
---@param y number
function walls.add_solo_tile(x, y)
	local key = x .. "," .. y
	walls.solo_tiles[key] = { x = x, y = y }
end

--- Builds colliders from all added tiles.
---@param merge? boolean Whether to merge adjacent tiles (default true)
function walls.build_colliders(merge)
	if merge == false then
		for _, tile in pairs(walls.tiles) do
			local col = {
				x = tile.x,
				y = tile.y,
				box = { x = 0, y = 0, w = 1, h = 1 },
				tiles = { tile },
				is_polygon = false
			}
			table.insert(walls.colliders, col)
			world.add_collider(col)
			walls.tile_to_collider[tile.x .. "," .. tile.y] = col
		end
	else
		local colliders = create_colliders(walls.tiles)
		register_colliders(colliders)
	end

	-- Add solo tiles as individual 1x1 colliders (never merged)
	for _, tile in pairs(walls.solo_tiles) do
		local col = {
			x = tile.x,
			y = tile.y,
			box = { x = 0, y = 0, w = 1, h = 1 },
			tiles = { tile },
			is_polygon = false
		}
		table.insert(walls.colliders, col)
		world.add_collider(col)
		walls.tile_to_collider[tile.x .. "," .. tile.y] = col
	end
end

--- Removes a tile and rebuilds affected collider.
---@param x number
---@param y number
---@return boolean success
function walls.remove_tile(x, y)
	local key = x .. "," .. y
	local tile = walls.tiles[key]
	if not tile then return false end

	local collider = walls.tile_to_collider[key]
	if not collider then return false end

	walls.tiles[key] = nil
	walls.tile_to_collider[key] = nil
	world.remove_collider(collider)

	for i, c in ipairs(walls.colliders) do
		if c == collider then
			table.remove(walls.colliders, i)
			break
		end
	end

	local temp_lookup = {}
	for _, t in ipairs(collider.tiles) do
		local tk = t.x .. "," .. t.y
		if tk ~= key then
			temp_lookup[tk] = t
			walls.tile_to_collider[tk] = nil
		end
	end

	if next(temp_lookup) then
		local new_colliders = create_colliders(temp_lookup)
		register_colliders(new_colliders)
	end

	return true
end

--- Checks if a tile is visible within the camera bounds.
--- For collection tiles, accounts for width/height extending beyond origin.
---@param tile table Tile with x, y, and optional tile_image
---@param min_x number Minimum visible x in tiles
---@param min_y number Minimum visible y in tiles
---@param max_x number Maximum visible x in tiles
---@param max_y number Maximum visible y in tiles
---@return boolean True if any part of the tile is visible
local function is_tile_visible(tile, min_x, min_y, max_x, max_y)
	if tile.tile_image then
		-- Collection tile: check full extent
		local img = tile.tile_image
		local width_tiles = img.width / common.BASE_TILE
		local height_tiles = img.height / common.BASE_TILE
		-- Tile extends right from x and up from y (bottom-left origin)
		local tile_left = tile.x
		local tile_right = tile.x + width_tiles
		local tile_top = tile.y - (height_tiles - 1)
		local tile_bottom = tile.y + 1
		return tile_right > min_x and tile_left <= max_x
			and tile_bottom > min_y and tile_top <= max_y
	else
		-- Standard 1x1 tile
		return tile.x >= min_x and tile.x <= max_x
			and tile.y >= min_y and tile.y <= max_y
	end
end

--- Draws a single tile, handling both tilemap and collection tile images.
---@param tile table Tile with x, y, tile_id, tileset_info, and optional tile_image
---@param ts number Tile size in pixels (scaled)
local function draw_tile(tile, ts)
	if not common.draw_tiled_tile(tile, ts) then
		sprites.draw_tile(4, 3, tile.x * ts, tile.y * ts)
	end
end

--- Draws all wall tiles and debug bounding boxes.
---@param camera table Camera instance for viewport culling
---@param margin number|nil Optional margin in tiles to expand culling bounds (default 0)
function walls.draw(camera, margin)
	local ts = sprites.tile_size
	local min_x, min_y, max_x, max_y = camera:get_visible_bounds(ts, margin)

	-- Sort and split decorative tiles by depth if needed
	if not walls.decorative_sorted then
		table.sort(walls.decorative_tiles, function(a, b)
			return a.depth < b.depth
		end)
		-- Split into below/above based on walls_depth
		walls.decorative_below = {}
		walls.decorative_above = {}
		for _, tile in ipairs(walls.decorative_tiles) do
			if tile.depth <= walls.walls_depth then
				table.insert(walls.decorative_below, tile)
			else
				table.insert(walls.decorative_above, tile)
			end
		end
		walls.decorative_sorted = true
	end

	-- Draw decorative tiles below collision tiles
	for _, tile in ipairs(walls.decorative_below) do
		if is_tile_visible(tile, min_x, min_y, max_x, max_y) then
			draw_tile(tile, ts)
		end
	end

	-- Draw collision tiles
	for _, tile in pairs(walls.tiles) do
		if is_tile_visible(tile, min_x, min_y, max_x, max_y) then
			draw_tile(tile, ts)
		end
	end

	for _, tile in pairs(walls.solo_tiles) do
		if is_tile_visible(tile, min_x, min_y, max_x, max_y) then
			draw_tile(tile, ts)
		end
	end

	-- Draw decorative tiles above collision tiles
	for _, tile in ipairs(walls.decorative_above) do
		if is_tile_visible(tile, min_x, min_y, max_x, max_y) then
			draw_tile(tile, ts)
		end
	end

	if config.bounding_boxes then
		canvas.set_color("#00ff1179")
		for _, col in pairs(walls.colliders) do
			if col.is_polygon and col.vertices then
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
			elseif col.box then
				canvas.draw_rect(
					col.x * ts,
					col.y * ts,
					col.box.w * ts,
					col.box.h * ts
				)
			end
		end
	end
end

--- Clears all wall data and removes colliders from physics world.
--- Call before level reload to reset state.
function walls.clear()
	walls.tiles = {}
	walls.solo_tiles = {}
	walls.decorative_tiles = {}
	walls.decorative_below = {}
	walls.decorative_above = {}
	walls.decorative_sorted = false
	walls.walls_depth = 0
	for _, col in ipairs(walls.colliders) do
		world.remove_collider(col)
	end
	walls.colliders = {}
	walls.tile_to_collider = {}
end

--- Checks if a wall tile exists at the given position.
---@param x number Tile x coordinate
---@param y number Tile y coordinate
---@return boolean True if a wall (normal or solo) exists at position
function walls.has_tile(x, y)
	local key = x .. "," .. y
	return walls.tiles[key] ~= nil or walls.solo_tiles[key] ~= nil
end

return walls
