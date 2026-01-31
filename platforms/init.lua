local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local tiled = require("platforms.tiled_loader")

local platforms = {}

-- Set by load_level(), cleared by clear()
local background_config = nil
local background_image = nil  -- Cached loaded image for Tiled backgrounds
local patrol_areas = {}  -- Debug: patrol area rectangles for visualization

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
		background_config = result.background
		patrol_areas = result.patrol_areas or {}
		-- Load image for Tiled image layer backgrounds
		if type(background_config) == "table" and background_config.image then
			background_image = background_config.image
			canvas.assets.load_image(background_image, background_config.image)
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

	background_config = level_data.background

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

--- Draws tiled background across the visible viewport.
--- Supports both sprite key strings and Tiled image layer configs.
---@param camera {_x: number, _y: number} Camera instance with position in tile coordinates
---@param bg_config string|table Sprite key or Tiled image layer config
local function draw_background(camera, bg_config)
	local scale = config.ui.SCALE
	local bg_width = BG_NATIVE_WIDTH * scale
	local bg_height = BG_NATIVE_HEIGHT * scale

	-- Determine image source and parallax
	local image
	local parallax_x, parallax_y = 1, 1
	local offset_x, offset_y = 0, 0
	local repeat_x, repeat_y = true, true

	if type(bg_config) == "string" then
		-- Old format: sprite key
		image = sprites.environment[bg_config]
	elseif type(bg_config) == "table" then
		-- New format: Tiled image layer config
		image = background_image
		parallax_x = bg_config.parallax_x or 1
		parallax_y = bg_config.parallax_y or 1
		-- Offset is in native pixels, scale to match display
		offset_x = (bg_config.offset_x or 0) * scale
		offset_y = (bg_config.offset_y or 0) * scale
		repeat_x = bg_config.repeat_x ~= false
		repeat_y = bg_config.repeat_y ~= false
	end

	if not image then return end

	-- Apply parallax to camera position
	local cam_x = camera._x * sprites.tile_size * parallax_x
	local cam_y = camera._y * sprites.tile_size * parallax_y

	if repeat_x and repeat_y then
		-- Tile in both directions
		-- Account for offset in tiling calculation to handle any offset value
		local start_x = math.floor((cam_x - offset_x) / bg_width) * bg_width + offset_x
		local start_y = math.floor((cam_y - offset_y) / bg_height) * bg_height + offset_y
		local end_x = cam_x + config.ui.canvas_width + bg_width
		local end_y = cam_y + config.ui.canvas_height + bg_height

		for y = start_y, end_y, bg_height do
			for x = start_x, end_x, bg_width do
				canvas.draw_image(image, x, y, bg_width, bg_height)
			end
		end
	elseif repeat_x then
		-- Tile horizontally only
		local start_x = math.floor((cam_x - offset_x) / bg_width) * bg_width + offset_x
		local end_x = cam_x + config.ui.canvas_width + bg_width
		local y = offset_y

		for x = start_x, end_x, bg_width do
			canvas.draw_image(image, x, y, bg_width, bg_height)
		end
	elseif repeat_y then
		-- Tile vertically only
		local start_y = math.floor((cam_y - offset_y) / bg_height) * bg_height + offset_y
		local end_y = cam_y + config.ui.canvas_height + bg_height
		local x = offset_x

		for y = start_y, end_y, bg_height do
			canvas.draw_image(image, x, y, bg_width, bg_height)
		end
	else
		-- No repeat: single image
		canvas.draw_image(image, offset_x, offset_y, bg_width, bg_height)
	end
end

--- Draws all platforms (walls, slopes, ladders, and bridges).
---@param camera table Camera instance for viewport culling
---@param margin number|nil Optional margin in tiles to expand culling bounds (default 0)
function platforms.draw(camera, margin)
	margin = margin or 0
	if background_config then
		draw_background(camera, background_config)
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
	background_config = nil
	background_image = nil
	patrol_areas = {}
	platforms.walls.clear()
	platforms.slopes.clear()
	platforms.ladders.clear()
	platforms.bridges.clear()
end

return platforms
