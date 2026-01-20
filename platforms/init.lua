local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")

local platforms = {}

-- Set by load_level(), cleared by clear()
local background_sprite = nil

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
--- @param level_data table Level data with map array and optional symbols table
--- @return {spawn: {x: number, y: number}|nil, enemies: {x: number, y: number, type: string}[], props: {type: string, x: number, y: number}[], width: number, height: number}
function platforms.load_level(level_data)
	local spawn = nil
	local enemies = {}
	local props = {}
	local width = level_data.map[1] and #level_data.map[1] or 0
	local height = #level_data.map
	local symbols = level_data.symbols or {}

	background_sprite = level_data.background

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
					table.insert(enemies, { x = ox, y = oy, type = def.key })
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

	return {
		spawn = spawn,
		enemies = enemies,
		props = props,
		width = width,
		height = height
	}
end

--- Builds all colliders for walls, slopes, ladder tops, and bridges.
function platforms.build()
	platforms.walls.build_colliders(true)
	platforms.slopes.build_colliders()
	platforms.ladders.build_colliders()
	platforms.bridges.build_colliders()
end

--- Draws tiled background across the visible viewport.
--- @param camera {_x: number, _y: number} Camera instance with position in tile coordinates
--- @param sprite_key string Key into sprites.environment for background image
local function draw_background(camera, sprite_key)
	local scale = config.ui.SCALE
	local bg_width = BG_NATIVE_WIDTH * scale
	local bg_height = BG_NATIVE_HEIGHT * scale

	local cam_x = camera._x * sprites.tile_size
	local cam_y = camera._y * sprites.tile_size

	local start_x = math.floor(cam_x / bg_width) * bg_width
	local start_y = math.floor(cam_y / bg_height) * bg_height
	local end_x = cam_x + config.ui.canvas_width + bg_width
	local end_y = cam_y + config.ui.canvas_height + bg_height

	for y = start_y, end_y, bg_height do
		for x = start_x, end_x, bg_width do
			canvas.draw_image(
				sprites.environment[sprite_key],
				x, y,
				bg_width, bg_height
			)
		end
	end
end

--- Draws all platforms (walls, slopes, ladders, and bridges).
--- @param camera table Camera instance for viewport culling
function platforms.draw(camera)
	if background_sprite then
		draw_background(camera, background_sprite)
	end
	platforms.walls.draw(camera)
	platforms.slopes.draw(camera)
	platforms.ladders.draw(camera)
	platforms.bridges.draw(camera)
end

--- Clears all platform data (for level reloading).
function platforms.clear()
	background_sprite = nil
	platforms.walls.clear()
	platforms.slopes.clear()
	platforms.ladders.clear()
	platforms.bridges.clear()
end

return platforms
