local walls = require("platforms/walls")
local bridges = require("platforms/bridges")
local ladders = require("platforms/ladders")
local canvas = require("canvas")

local tiled = {}

--- Check if level data is Tiled format (has tilesets and layers arrays).
---@param level_data table Level data to check
---@return boolean True if Tiled format
function tiled.is_tiled_format(level_data)
	return level_data.tilesets ~= nil and level_data.layers ~= nil
end

--- Convert Tiled relative path to game asset path.
--- Strips "../assets/" prefix from paths used in Tiled exports.
---@param path string Tiled relative path (e.g., "../assets/Tilesets/bg.png")
---@return string|nil Asset path (e.g., "Tilesets/bg.png") or nil if not a game asset
local function to_asset_path(path)
	if path and path:match("^%.%./assets/") then
		return path:gsub("^%.%./assets/", "")
	end
	return nil
end

-- Maps tile type strings to their handler functions
local tile_handlers = {
	wall = walls.add_tile,
	platform = walls.add_tile,
	bridge = bridges.add_bridge,
	ladder = ladders.add_ladder,
}

--- Get handler function for a tile type string.
---@param tile_type string|nil Tile type ("wall", "bridge", "ladder")
---@return function|nil Handler function or nil
local function get_handler_for_type(tile_type)
	if not tile_type then return nil end
	return tile_handlers[tile_type:lower()]
end

--- Loads all image assets for a Tiled level without processing geometry.
--- Call this at startup for each level to ensure assets are available during transitions.
---@param level_data table Tiled level data
function tiled.preload_assets(level_data)
	if not tiled.is_tiled_format(level_data) then return end

	-- Load tileset images
	for _, tileset_ref in ipairs(level_data.tilesets or {}) do
		local tileset_filename = tileset_ref.filename
		if tileset_filename then
			local lua_filename = tileset_filename:gsub("%.tsx$", ".lua")
			local require_path = "Tilemaps/" .. lua_filename:gsub("%.lua$", "")

			local ok, tileset = pcall(require, require_path)
			if ok and tileset then
				-- Image-based tileset (main tileset image)
				local tileset_image = to_asset_path(tileset.image)
				if tileset_image then
					canvas.assets.load_image(tileset_image, tileset_image)
				end

				-- Collection tileset tiles - only load game assets (../assets/ prefix)
				-- Tiles with other paths are editor-only images for entities
				for _, tile in ipairs(tileset.tiles or {}) do
					local image_path = to_asset_path(tile.image)
					if image_path then
						canvas.assets.load_image(image_path, image_path)
					end
				end
			end
		end
	end

	-- Load background images from image layers (only game assets)
	for _, layer in ipairs(level_data.layers or {}) do
		if layer.type == "imagelayer" then
			local image_path = to_asset_path(layer.image)
			if image_path then
				canvas.assets.load_image(image_path, image_path)
			end
		end
	end
end

--- Build mappings from global tile ID to tile properties by loading tileset files.
--- Returns three maps: tile collision types, full tile properties, and renderable tile info.
--- For image-based tilesets, tile_renderable[gid] = {tileset_image, columns, firstgid}.
--- For collection tilesets, tile_renderable[gid] = {image = path, width = w, height = h}.
---@param level_data table Tiled level data with tilesets array
---@return table<number, string>, table<number, table>, table<number, boolean|table> tile_types, tile_properties, tile_renderable
local function build_tile_maps(level_data)
	local tile_types = {}      -- gid → collision type (bridge, ladder, etc.)
	local tile_properties = {}
	local tile_renderable = {}  -- tileset info for tilemap tiles, {image, width, height} for collection tiles

	for _, tileset_ref in ipairs(level_data.tilesets or {}) do
		local firstgid = tileset_ref.firstgid
		local tileset_filename = tileset_ref.filename

		if tileset_filename then
			-- Convert .tsx to .lua and build require path
			local lua_filename = tileset_filename:gsub("%.tsx$", ".lua")
			local require_path = "Tilemaps/" .. lua_filename:gsub("%.lua$", "")

			local ok, tileset = pcall(require, require_path)
			if ok and tileset then
				-- Check if this is an image-based tileset (has 'image' property)
				-- Collection tilesets have individual images per tile instead
				local is_image_tileset = tileset.image ~= nil

				if is_image_tileset and tileset.tilecount then
					-- Convert tileset image path and load it
					local tileset_image = tileset.image:gsub("^%.%./assets/", "")
					canvas.assets.load_image(tileset_image, tileset_image)

					-- Store tileset info for all tiles from this tileset
					local tileset_info = {
						tileset_image = tileset_image,
						columns = tileset.columns,
						firstgid = firstgid
					}
					for i = 0, tileset.tilecount - 1 do
						tile_renderable[firstgid + i] = tileset_info
					end
				end

				-- Process tiles with custom properties or individual images
				for _, tile in ipairs(tileset.tiles or {}) do
					local gid = firstgid + tile.id

					-- Get type from tile.type or tile.properties.type
					local tile_type = tile.type or (tile.properties and tile.properties.type)
					if tile_type then
						tile_types[gid] = tile_type
					end
					-- Store all properties for object layer processing
					if tile.properties then
						tile_properties[gid] = tile.properties
					end

					-- Collection tileset: mark tiles as renderable
					if not is_image_tileset and tile.image then
						if tile_type then
							-- Typed tiles (collision/entity): use fallback sprite rendering (no tile_id, no image)
							tile_renderable[gid] = "fallback"
						else
							-- Typeless tiles (decorations): store image info for collection rendering
							local image_path = tile.image:gsub("^%.%./assets/", "")
							tile_renderable[gid] = {
								image = image_path,
								width = tile.width,
								height = tile.height
							}
						end
					end
				end
			end
		end
	end

	return tile_types, tile_properties, tile_renderable
end

--- Process a single tile, adding it as decorative or collision based on layer/tile types.
---@param tile_id number Tile global ID
---@param world_x number World x coordinate (already offset-adjusted)
---@param world_y number World y coordinate (already offset-adjusted)
---@param layer_type string|nil Layer's collision type from properties
---@param tile_types table<number, string> Map of gid to collision type
---@param tile_renderable table<number, table|string> Map of gid to render info (tileset info or collection tile)
local function process_single_tile(tile_id, world_x, world_y, layer_type, tile_types, tile_renderable)
	local render_info = tile_renderable[tile_id]
	if not render_info then return end

	-- Determine render parameters based on render_info type:
	-- table with tileset_image = tilemap tile (pass tileset info)
	-- "fallback" = typed collection tile (pass nil, use fallback sprites)
	-- table with image = typeless collection tile (pass image info)
	local tileset_info = nil
	local tile_image = nil

	if type(render_info) == "table" then
		if render_info.tileset_image then
			-- Image-based tileset tile
			tileset_info = render_info
		elseif render_info.image then
			-- Collection tileset tile
			tile_image = render_info
		end
	end
	-- render_info == "fallback" means use fallback sprites (both nil)

	if not layer_type then
		-- Layer has no type: all tiles are decorative
		walls.add_decorative_tile(world_x, world_y, tile_id, tileset_info, tile_image)
		return
	end

	-- Layer has type: tile type can override layer type (e.g., bridge tile on wall layer)
	-- Falls back to layer_type if tile has no type or unknown type
	local tile_type = tile_types[tile_id]
	local handler = get_handler_for_type(tile_type) or get_handler_for_type(layer_type)

	if handler then
		handler(world_x, world_y, tile_id, tileset_info, tile_image)
	end
end

--- Process a tile layer, adding tiles based on layer and tile types.
--- Supports chunk-based storage for infinite maps.
--- If layer has no type: all tiles are decorative (render only).
--- If layer has type: tile type can override (e.g., bridge tile on wall layer = bridge).
---@param layer table Tiled tile layer data
---@param offset_x number X offset to normalize coordinates (subtracted from world coords)
---@param offset_y number Y offset to normalize coordinates (subtracted from world coords)
---@param tile_types table<number, string> Map of gid to collision type from tileset
---@param tile_renderable table<number, boolean|table> Map of gid to render info from tileset
local function process_tile_layer(layer, offset_x, offset_y, tile_types, tile_renderable)
	local layer_type = layer.properties and layer.properties.type

	if layer.chunks then
		-- Chunk-based storage (infinite map)
		for _, chunk in ipairs(layer.chunks) do
			local chunk_x, chunk_y = chunk.x, chunk.y
			local chunk_width = chunk.width
			for i, tile_id in ipairs(chunk.data) do
				if tile_id > 0 then
					local local_x = (i - 1) % chunk_width
					local local_y = math.floor((i - 1) / chunk_width)
					local world_x = chunk_x + local_x - offset_x
					local world_y = chunk_y + local_y - offset_y
					process_single_tile(tile_id, world_x, world_y, layer_type, tile_types, tile_renderable)
				end
			end
		end
	elseif layer.data then
		-- Non-chunked storage (fixed size map)
		local width = layer.width
		for i, tile_id in ipairs(layer.data) do
			if tile_id > 0 then
				local x = (i - 1) % width - offset_x
				local y = math.floor((i - 1) / width) - offset_y
				process_single_tile(tile_id, x, y, layer_type, tile_types, tile_renderable)
			end
		end
	end
end

--- Merge tileset properties with object properties.
--- Object properties override tileset properties.
---@param tileset_props table|nil Properties from tileset
---@param obj_props table|nil Properties from object instance
---@return table Merged properties
local function merge_properties(tileset_props, obj_props)
	local merged = {}
	if tileset_props then
		for k, v in pairs(tileset_props) do
			merged[k] = v
		end
	end
	if obj_props then
		for k, v in pairs(obj_props) do
			merged[k] = v
		end
	end
	return merged
end

--- Check if a point (in pixels) is inside a rectangle.
---@param px number Point x in pixels
---@param py number Point y in pixels
---@param rect table Rectangle with x, y, width, height in pixels
---@return boolean
local function point_in_rect(px, py, rect)
	return px >= rect.x and px < rect.x + rect.width
		and py >= rect.y and py < rect.y + rect.height
end

--- Find the patrol area containing a point.
---@param px number Point x in pixels
---@param py number Point y in pixels
---@param patrol_areas table[] Array of patrol area rectangles
---@return table|nil The patrol area or nil
local function find_patrol_area(px, py, patrol_areas)
	for _, area in ipairs(patrol_areas) do
		if point_in_rect(px, py, area) then
			return area
		end
	end
	return nil
end

--- Process an object layer, extracting spawn point, enemies, props, spawn points, and map transitions.
---@param layer table Tiled object layer data
---@param spawn table|nil Current spawn point (modified in place)
---@param enemies table Array of enemy definitions (modified in place)
---@param props table Array of prop definitions (modified in place)
---@param tile_size number Tile size in pixels for coordinate conversion
---@param offset_x number X offset to normalize coordinates
---@param offset_y number Y offset to normalize coordinates
---@param tile_properties table<number, table> Map of gid to tileset properties
---@param spawn_points table<string, table> Named spawn points lookup (modified in place)
---@param map_transitions table Array of map transition zones (modified in place)
---@param one_way_platforms table Array of one-way platform zones (modified in place)
---@return table|nil spawn Updated spawn point
---@return table patrol_areas_tiles Patrol areas converted to tile coordinates
local function process_object_layer(layer, spawn, enemies, props, tile_size, offset_x, offset_y, tile_properties, spawn_points, map_transitions, one_way_platforms)
	-- First pass: collect patrol areas
	local patrol_areas = {}
	for _, obj in ipairs(layer.objects or {}) do
		local obj_type = (obj.properties and obj.properties.type) or (obj.name or ""):lower()
		if obj_type == "patrol_area" then
			table.insert(patrol_areas, {
				x = obj.x,
				y = obj.y,
				width = obj.width or 0,
				height = obj.height or 0,
			})
		end
	end

	-- Second pass: process all objects
	for _, obj in ipairs(layer.objects or {}) do
		-- Convert pixel coords to tile coords, applying offset normalization
		local tx = obj.x / tile_size - offset_x
		local ty = obj.y / tile_size - offset_y

		-- Tile objects (with gid) use bottom-left origin in Tiled, adjust to top-left
		if obj.gid then
			ty = (obj.y - (obj.height or tile_size)) / tile_size - offset_y
		end

		local tileset_props = obj.gid and tile_properties[obj.gid]
		local merged_props = merge_properties(tileset_props, obj.properties)

		-- Get type from merged properties (or use object name as fallback)
		local obj_type = merged_props.type or (obj.name or ""):lower()

		-- Register named spawn point if present (used for map transitions)
		local spawn_id = merged_props.id
		if spawn_id then
			spawn_points[spawn_id] = { x = tx, y = ty }
		end

		-- Process object based on type (empty type means spawn marker only)
		if obj_type == "" then
			-- Spawn point marker with no other behavior
		elseif obj_type == "spawn" or obj.name == "Start" then
			spawn = { x = tx, y = ty }
		elseif obj_type == "map_transition" then
			-- Map transition zone: trigger area that loads another map
			local target_map = merged_props.target_map
			local target_id = merged_props.target_id
			if target_map and target_id then
				table.insert(map_transitions, {
					x = tx,
					y = ty,
					width = (obj.width or tile_size) / tile_size,
					height = (obj.height or tile_size) / tile_size,
					target_map = target_map,
					target_id = target_id,
				})
			end
		elseif obj_type == "one_way_platform" then
			table.insert(one_way_platforms, {
				x = tx,
				y = ty,
				width = (obj.width or tile_size) / tile_size,
			})
		elseif obj_type == "patrol_area" then
			-- Already processed in first pass, skip
		elseif obj_type == "enemy" then
			local enemy_key = merged_props.key or obj.name
			-- Apply offset properties from tileset (for sprite alignment)
			local ex = tx + (merged_props.offset_x or 0)
			local ey = ty + (merged_props.offset_y or 0)
			local enemy_data = {
				type = enemy_key,
				x = ex,
				y = ey,
			}
			-- Copy merged properties
			if merged_props.flip then
				enemy_data.flip = merged_props.flip
			end
			-- Waypoint support: check if enemy is inside a patrol area
			-- For tile objects (gid), y is bottom-left origin, adjust to top-left for containment check
			local check_y = obj.gid and (obj.y - (obj.height or tile_size)) or obj.y
			local patrol_area = find_patrol_area(obj.x, check_y, patrol_areas)
			if patrol_area then
				-- Use patrol area bounds as waypoints (in tile coords)
				-- Inset right edge by 1 tile so enemy stays within bounds
				enemy_data.waypoints = {
					a = patrol_area.x / tile_size - offset_x,
					b = (patrol_area.x + patrol_area.width) / tile_size - offset_x - 1
				}
			elseif merged_props.waypoint_a and merged_props.waypoint_b then
				-- Fallback to explicit waypoint properties
				enemy_data.waypoints = {
					a = merged_props.waypoint_a / tile_size,
					b = merged_props.waypoint_b / tile_size
				}
			end
			table.insert(enemies, enemy_data)
		else
			-- Treat as prop
			-- Apply offset properties from tileset (for sprite alignment)
			local px = tx + (merged_props.offset_x or 0)
			local py = ty + (merged_props.offset_y or 0)
			local prop_data = {
				type = obj_type,
				x = px,
				y = py,
			}
			for k, v in pairs(merged_props) do
				if k ~= "type" and k ~= "offset_x" and k ~= "offset_y" then
					prop_data[k] = v
				end
			end
			table.insert(props, prop_data)
		end
	end

	-- Convert patrol areas to tile coordinates for debug rendering
	local patrol_areas_tiles = {}
	for _, area in ipairs(patrol_areas) do
		table.insert(patrol_areas_tiles, {
			x = area.x / tile_size - offset_x,
			y = area.y / tile_size - offset_y,
			width = area.width / tile_size,
			height = area.height / tile_size,
		})
	end

	return spawn, patrol_areas_tiles
end

--- Calculate actual level bounds from tile layers and object layers.
--- Returns min/max coordinates that contain tile data and objects.
--- Supports both chunk-based (infinite) and fixed-size tile layers.
---@param level_data table Tiled export data
---@return number, number, number, number min_x, min_y, max_x, max_y
local function calculate_bounds(level_data)
	local tile_size = level_data.tilewidth or 16
	local min_x, min_y = math.huge, math.huge
	local max_x, max_y = -math.huge, -math.huge

	for _, layer in ipairs(level_data.layers) do
		if layer.type == "tilelayer" then
			if layer.chunks then
				-- Chunk-based storage (infinite map)
				for _, chunk in ipairs(layer.chunks) do
					local chunk_width = chunk.width
					for i, tile_id in ipairs(chunk.data) do
						if tile_id > 0 then
							local local_x = (i - 1) % chunk_width
							local local_y = math.floor((i - 1) / chunk_width)
							local world_x = chunk.x + local_x
							local world_y = chunk.y + local_y
							min_x = math.min(min_x, world_x)
							min_y = math.min(min_y, world_y)
							max_x = math.max(max_x, world_x)
							max_y = math.max(max_y, world_y)
						end
					end
				end
			elseif layer.data then
				-- Fixed-size storage (standard map)
				local width = layer.width
				for i, tile_id in ipairs(layer.data) do
					if tile_id > 0 then
						local x = (i - 1) % width
						local y = math.floor((i - 1) / width)
						min_x = math.min(min_x, x)
						min_y = math.min(min_y, y)
						max_x = math.max(max_x, x)
						max_y = math.max(max_y, y)
					end
				end
			end
		elseif layer.type == "objectgroup" then
			-- Include object positions in bounds calculation, but skip marker-only objects
			for _, obj in ipairs(layer.objects or {}) do
				local obj_type = (obj.properties and obj.properties.type) or ""
				local has_id = obj.properties and obj.properties.id
				-- Skip spawn points (id-only) and map transitions (marker objects)
				local is_marker = (has_id and obj_type == "") or obj_type == "map_transition"
				if not is_marker then
					local obj_x = obj.x / tile_size
					local obj_y = obj.y / tile_size
					local obj_w = (obj.width or tile_size) / tile_size
					local obj_h = (obj.height or tile_size) / tile_size
					min_x = math.min(min_x, obj_x)
					min_y = math.min(min_y, obj_y)
					max_x = math.max(max_x, obj_x + obj_w)
					max_y = math.max(max_y, obj_y + obj_h)
				end
			end
		end
	end

	-- Fallback if no tiles found
	if min_x == math.huge then
		return 0, 0, level_data.width, level_data.height
	end

	-- Add 1 to max because tiles occupy space (0,0 to 1,1 means width=1)
	return min_x, min_y, max_x + 1, max_y + 1
end

--- Extract background info from an image layer.
--- Converts Tiled relative path to game asset path.
---@param layer table Tiled image layer data
---@return table|nil Background configuration or nil
local function process_image_layer(layer)
	-- Convert relative path to asset path (only game assets)
	local image_path = to_asset_path(layer.image)
	if not image_path then return nil end

	-- Check for custom properties
	local props = layer.properties or {}

	return {
		image = image_path,
		offset_x = layer.offsetx or 0,  -- Keep in pixels, scale applied at draw time
		offset_y = layer.offsety or 0,
		parallax_x = layer.parallaxx or 1,
		parallax_y = layer.parallaxy or 1,
		repeat_x = layer.repeatx or false,
		repeat_y = layer.repeaty or false,
		width = props.width,       -- Custom width in native pixels (optional)
		height = props.height,     -- Custom height in native pixels (optional)
		clamp_bottom = props.clamp_bottom,  -- Prevent bottom from rising above screen bottom
		clamp_slack = props.clamp_slack,    -- Extra pixels below screen bottom before clamp activates
	}
end

--- Load a Tiled level, converting to game format.
--- Processes tile layers for geometry and object layers for entities.
---@param level_data table Tiled export data
---@return table { spawn, enemies, props, width, height, backgrounds }
function tiled.load(level_data)
	local spawn = nil
	local enemies = {}
	local props = {}
	local patrol_areas = {}
	local backgrounds = {}  -- Array of background layers (rendered in order)
	local spawn_points = {}  -- Named spawn points for map transitions
	local map_transitions = {}  -- Map transition trigger zones
	local one_way_platforms = {}  -- One-way platform collision zones
	local tile_size = level_data.tilewidth or 16

	-- Build tile maps from tileset files
	-- tile_types: gid → collision type (bridge, ladder - overrides layer type)
	-- tile_properties: gid → all tile properties (for objects)
	-- tile_renderable: gid → true (tilemap) or {image, width, height} (collection)
	local tile_types, tile_properties, tile_renderable = build_tile_maps(level_data)

	-- Load collection tileset images
	for _, info in pairs(tile_renderable) do
		if type(info) == "table" and info.image then
			canvas.assets.load_image(info.image, info.image)
		end
	end

	-- Calculate actual bounds from chunk data (handles negative coordinates)
	-- All coordinates are normalized by subtracting min_x/min_y so level starts at (0,0)
	local min_x, min_y, max_x, max_y = calculate_bounds(level_data)

	-- Process each layer with offset normalization
	for _, layer in ipairs(level_data.layers) do
		if layer.type == "tilelayer" then
			process_tile_layer(layer, min_x, min_y, tile_types, tile_renderable)
		elseif layer.type == "objectgroup" then
			local layer_spawn, layer_patrol_areas = process_object_layer(layer, spawn, enemies, props, tile_size, min_x, min_y, tile_properties, spawn_points, map_transitions, one_way_platforms)
			spawn = layer_spawn
			for _, area in ipairs(layer_patrol_areas) do
				table.insert(patrol_areas, area)
			end
		elseif layer.type == "imagelayer" then
			local bg = process_image_layer(layer)
			if bg then
				-- Load the image asset
				canvas.assets.load_image(bg.image, bg.image)
				table.insert(backgrounds, bg)
			end
		end
	end

	-- Fallback: extract background from map properties (sprite key)
	if #backgrounds == 0 and level_data.properties and level_data.properties.background then
		table.insert(backgrounds, level_data.properties.background)
	end

	return {
		spawn = spawn,
		enemies = enemies,
		props = props,
		patrol_areas = patrol_areas,
		width = max_x - min_x,
		height = max_y - min_y,
		backgrounds = backgrounds,
		spawn_points = spawn_points,
		map_transitions = map_transitions,
		one_way_platforms = one_way_platforms,
	}
end

return tiled
