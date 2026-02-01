local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local tiled = require("platforms.tiled_loader")
local world = require("world")

local platforms = {}

-- Set by load_level(), cleared by clear()
local background_layers = {}  -- Array of background configs for Tiled image layers
local patrol_areas = {}  -- Debug: patrol area rectangles for visualization
local map_transition_colliders = {}  -- Array of map transition trigger collider owners
local one_way_platform_colliders = {}  -- Array of one-way platform collider owners

-- Exposed for main.lua to look up spawn positions
platforms.spawn_points = {}  -- Named spawn points lookup { [id] = {x, y} }

-- Background sprite native dimensions (before scaling)
local BG_NATIVE_WIDTH = 240
local BG_NATIVE_HEIGHT = 160

platforms.walls = require('platforms/walls')
platforms.slopes = require('platforms/slopes')
platforms.ladders = require('platforms/ladders')
platforms.bridges = require('platforms/bridges')

--- Applies optional offset to tile coordinates.
---@param tx number Base tile X coordinate
---@param ty number Base tile Y coordinate
---@param offset {x: number, y: number}|nil Optional offset table
---@return number, number Adjusted coordinates
local function apply_offset(tx, ty, offset)
	if not offset then
		return tx, ty
	end
	return tx + (offset.x or 0), ty + (offset.y or 0)
end

--- Parses a level and adds tiles to walls and slopes.
--- Supports both ASCII map format and Tiled export format.
---@param level_data table Level data with map array and optional symbols table, or Tiled export
---@return {spawn: {x: number, y: number}|nil, enemies: {x: number, y: number, type: string}[], props: {type: string, x: number, y: number}[], width: number, height: number}
function platforms.load_level(level_data)
	if tiled.is_tiled_format(level_data) then
		local result = tiled.load(level_data)
		background_layers = result.backgrounds or {}
		patrol_areas = result.patrol_areas or {}
		platforms.spawn_points = result.spawn_points or {}

		-- Create trigger colliders for map transitions
		for _, transition in ipairs(result.map_transitions or {}) do
			local owner = {
				x = transition.x,
				y = transition.y,
				box = { x = 0, y = 0, w = transition.width, h = transition.height },
				is_map_transition = true,
				target_map = transition.target_map,
				target_id = transition.target_id,
			}
			world.add_trigger_collider(owner)
			table.insert(map_transition_colliders, owner)
		end

		-- Create one-way platform colliders for Tiled rectangle objects
		-- (allows arbitrary-width platforms without visible bridge tiles)
		for _, platform in ipairs(result.one_way_platforms or {}) do
			local owner = {
				x = platform.x,
				y = platform.y,
				-- Thin collider (0.2 tiles) matches bridge behavior for consistent drop-through
				box = { x = 0, y = 0, w = platform.width, h = 0.2 },
				is_bridge = true,
			}
			world.add_collider(owner)
			table.insert(one_way_platform_colliders, owner)
		end

		return result
	end

	-- ASCII format parsing below
	local spawn = nil
	local enemies = {}
	local props = {}
	local width = level_data.map[1] and #level_data.map[1] or 0
	local height = #level_data.map
	local symbols = level_data.symbols or {}

	-- Collect waypoints by row for enemies that patrol between markers
	-- Format: [enemy_key][row] = { positions = {x...}, count = 1 }
	local waypoint_enemies = {}

	-- ASCII format uses a single background
	if level_data.background then
		background_layers = { level_data.background }
	end

	for y, row in ipairs(level_data.map) do
		for x = 1, #row do
			local tx, ty = x - 1, y - 1
			local ch = row:sub(x, x)
			-- Reserved geometry symbols (hardcoded)
			if ch == "#" then
				platforms.walls.add_tile(tx, ty)
			elseif ch == "X" then
				platforms.walls.add_solo_tile(tx, ty)
			elseif ch == "/" then
				platforms.slopes.add_tile(tx, ty, "/")
			elseif ch == "\\" then
				platforms.slopes.add_tile(tx, ty, "\\")
			elseif ch == "H" then
				platforms.ladders.add_ladder(tx, ty)
			elseif ch == "-" then
				platforms.bridges.add_bridge(tx, ty)
			elseif symbols[ch] then
				local def = symbols[ch]
				local ox, oy = apply_offset(tx, ty, def.offset)

				if def.type == "spawn" then
					spawn = { x = ox, y = oy }
				elseif def.type == "enemy" then
					-- Waypoint-based enemies (bat_eye, zombie) are collected for pairing
					if def.key == "bat_eye" or def.key == "zombie" then
						waypoint_enemies[def.key] = waypoint_enemies[def.key] or {}
						local by_row = waypoint_enemies[def.key]
						by_row[ty] = by_row[ty] or { positions = {}, count = 1 }
						table.insert(by_row[ty].positions, tx)
						if def.count and def.count > by_row[ty].count then
							by_row[ty].count = def.count
						end
					else
						local enemy_data = { x = ox, y = oy, type = def.key }
						-- Copy extra properties (flip, etc.)
						for k, v in pairs(def) do
							if k ~= "type" and k ~= "key" and k ~= "offset" then
								enemy_data[k] = v
							end
						end
						table.insert(enemies, enemy_data)
					end
				else
					-- Generic prop handling (includes signs) - copy all properties from def
					local prop_data = { type = def.type, x = ox, y = oy }
					for k, v in pairs(def) do
						if k ~= "type" and k ~= "offset" then
							prop_data[k] = v
						end
					end
					table.insert(props, prop_data)
				end
			end
		end
	end

	-- Create enemies from paired waypoints
	for enemy_key, rows in pairs(waypoint_enemies) do
		for row, data in pairs(rows) do
			local positions = data.positions
			local count = data.count

			if #positions >= 2 then
				table.sort(positions)  -- Ensure left-to-right order
				local left, right = positions[1], positions[2]

				-- Spawn count enemies distributed across the patrol range
				-- For count=1: center. For count>1: evenly distributed from left to right
				local range = right - left
				for i = 1, count do
					local t = count == 1 and 0.5 or (i - 1) / (count - 1)
					table.insert(enemies, {
						x = left + t * range,
						y = row,
						type = enemy_key,
						waypoints = { a = left, b = right }
					})
				end

				if #positions > 2 then
					print("[WARNING] Row " .. row .. " has " .. #positions .. " " .. enemy_key .. " markers (expected 1 or 2)")
				end
			else
				-- Single marker: spawn without patrol
				table.insert(enemies, {
					x = positions[1],
					y = row,
					type = enemy_key
				})
			end
		end
	end

	return {
		spawn = spawn,
		enemies = enemies,
		props = props,
		width = width,
		height = height
	}
end

--- Builds all colliders for walls, slopes, ladder tops, and bridges.
--- Call after load_level() to create collision geometry.
function platforms.build()
	platforms.walls.build_colliders(true)
	platforms.slopes.build_colliders()
	platforms.ladders.build_colliders()
	platforms.bridges.build_colliders()
end

--- Calculates tiling range for a single axis.
--- Returns start position (aligned to tile boundary) and end position (past viewport).
---@param screen_cam number Camera position in screen space (parallax-adjusted)
---@param cam_px number Camera position in world pixels
---@param offset number Layer offset in pixels
---@param parallax_offset number Offset to counteract camera transform
---@param bg_size number Size of one background tile in pixels
---@param viewport_size number Viewport dimension in pixels
---@return number, number start, end positions
local function calc_tile_range(screen_cam, cam_px, offset, parallax_offset, bg_size, viewport_size)
	local start = math.floor((screen_cam - offset) / bg_size) * bg_size + offset + parallax_offset
	local end_pos = cam_px + viewport_size + bg_size + parallax_offset
	return start, end_pos
end

--- Draws tiled background across the visible viewport.
--- Supports both sprite key strings and Tiled image layer configs.
--- Parallax: 0 = fixed on screen, 1 = scrolls with world, 0.5 = half speed
---@param camera {_x: number, _y: number} Camera instance with position in tile coordinates
---@param bg_config string|table Sprite key or Tiled image layer config
local function draw_background(camera, bg_config)
	local scale = config.ui.SCALE
	local tile_size = sprites.tile_size

	-- Determine image source and parallax
	local image
	local parallax_x, parallax_y = 1, 1
	local offset_x, offset_y = 0, 0
	local repeat_x, repeat_y = true, true
	local clamp_bottom = false
	local bg_width, bg_height

	if type(bg_config) == "string" then
		-- Old format: sprite key
		image = sprites.environment[bg_config]
		bg_width = BG_NATIVE_WIDTH * scale
		bg_height = BG_NATIVE_HEIGHT * scale
	elseif type(bg_config) == "table" then
		-- New format: Tiled image layer config
		image = bg_config.image
		parallax_x = bg_config.parallax_x or 1
		parallax_y = bg_config.parallax_y or 1
		offset_x = (bg_config.offset_x or 0) * scale
		offset_y = (bg_config.offset_y or 0) * scale
		repeat_x = bg_config.repeat_x ~= false
		repeat_y = bg_config.repeat_y ~= false
		clamp_bottom = bg_config.clamp_bottom or false
		bg_width = (bg_config.width or BG_NATIVE_WIDTH) * scale
		bg_height = (bg_config.height or BG_NATIVE_HEIGHT) * scale
	end

	if not image then return end

	-- Camera position in pixels
	local cam_px = camera._x * tile_size
	local cam_py = camera._y * tile_size

	-- Parallax offset: counteracts camera transform for slower/fixed backgrounds
	local parallax_offset_x = cam_px * (1 - parallax_x)
	local parallax_offset_y = cam_py * (1 - parallax_y)

	-- Screen-space camera position (where tiling should start)
	local screen_cam_x = cam_px * parallax_x
	local screen_cam_y = cam_py * parallax_y

	-- Calculate positions for each axis
	local start_x, end_x, start_y, end_y

	if repeat_x then
		start_x, end_x = calc_tile_range(screen_cam_x, cam_px, offset_x, parallax_offset_x, bg_width, config.ui.canvas_width)
	else
		start_x = offset_x + parallax_offset_x
		end_x = start_x
	end

	if repeat_y then
		start_y, end_y = calc_tile_range(screen_cam_y, cam_py, offset_y, parallax_offset_y, bg_height, config.ui.canvas_height)
	else
		start_y = offset_y + parallax_offset_y
		-- Clamp bottom: prevent image bottom from rising above screen bottom
		if clamp_bottom then
			local image_bottom = start_y + bg_height
			local screen_bottom = cam_py + config.ui.canvas_height
			if image_bottom < screen_bottom then
				start_y = screen_bottom - bg_height
			end
		end
		end_y = start_y
	end

	-- Draw tiles
	for y = start_y, end_y, bg_height do
		for x = start_x, end_x, bg_width do
			canvas.draw_image(image, x, y, bg_width, bg_height)
		end
	end
end

--- Draws all platforms (walls, slopes, ladders, and bridges).
---@param camera table Camera instance for viewport culling
---@param margin number|nil Optional margin in tiles to expand culling bounds (default 0)
function platforms.draw(camera, margin)
	margin = margin or 0
	-- Draw all background layers in order (first layer = furthest back)
	for _, bg in ipairs(background_layers) do
		draw_background(camera, bg)
	end
	platforms.walls.draw(camera, margin)
	platforms.slopes.draw(camera, margin)
	platforms.ladders.draw(camera, margin)
	platforms.bridges.draw(camera, margin)

	-- Debug: draw patrol areas
	if config.bounding_boxes and #patrol_areas > 0 then
		local ts = sprites.tile_size
		canvas.set_color("#ffff0060")  -- Yellow with transparency
		for _, area in ipairs(patrol_areas) do
			canvas.fill_rect(area.x * ts, area.y * ts, area.width * ts, area.height * ts)
		end
		canvas.set_color("#ffff00")  -- Yellow outline
		for _, area in ipairs(patrol_areas) do
			canvas.draw_rect(area.x * ts, area.y * ts, area.width * ts, area.height * ts)
		end
	end
end

--- Clears all platform data and resets background state.
--- Call before loading a new level to prevent stale data.
function platforms.clear()
	background_layers = {}
	patrol_areas = {}
	platforms.spawn_points = {}

	-- Remove map transition trigger colliders
	for _, owner in ipairs(map_transition_colliders) do
		world.remove_trigger_collider(owner)
	end
	map_transition_colliders = {}

	-- Remove one-way platform colliders
	for _, owner in ipairs(one_way_platform_colliders) do
		world.remove_collider(owner)
	end
	one_way_platform_colliders = {}

	platforms.walls.clear()
	platforms.slopes.clear()
	platforms.ladders.clear()
	platforms.bridges.clear()
end

return platforms
