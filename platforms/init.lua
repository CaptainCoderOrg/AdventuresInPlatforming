local platforms = {}

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
--- @return {spawn: {x: number, y: number}|nil, enemies: {x: number, y: number, type: string}[], signs: {x: number, y: number, text: string}[], spike_traps: {x: number, y: number}[], buttons: {x: number, y: number}[], campfires: {x: number, y: number}[], width: number, height: number}
function platforms.load_level(level_data)
	local spawn = nil
	local enemies = {}
	local signs = {}
	local spike_traps = {}
	local buttons = {}
	local campfires = {}
	local width = level_data.map[1] and #level_data.map[1] or 0
	local height = #level_data.map
	local symbols = level_data.symbols or {}

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
				-- Dynamic symbol handling from level data
				local def = symbols[ch]
				local ox, oy = apply_offset(tx, ty, def.offset)
				if def.type == "spawn" then
					spawn = { x = ox, y = oy }
				elseif def.type == "enemy" then
					table.insert(enemies, { x = ox, y = oy, type = def.key })
				elseif def.type == "sign" then
					table.insert(signs, { x = ox, y = oy, text = def.text })
				elseif def.type == "spike_trap" then
					table.insert(spike_traps, {
						x = ox,
						y = oy,
						mode = def.mode,
						extend_time = def.extend_time,
						retract_time = def.retract_time,
						start_retracted = def.start_retracted,
						group = def.group,
					})
				elseif def.type == "button" then
					table.insert(buttons, { x = ox, y = oy, on_press = def.on_press })
				elseif def.type == "campfire" then
					table.insert(campfires, { x = ox, y = oy })
				end
			end
		end
	end

	return {
		spawn = spawn,
		enemies = enemies,
		signs = signs,
		spike_traps = spike_traps,
		buttons = buttons,
		campfires = campfires,
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

--- Draws all platforms (walls, slopes, ladders, and bridges).
--- @param camera table Camera instance for viewport culling
function platforms.draw(camera)
	platforms.walls.draw(camera)
	platforms.slopes.draw(camera)
	platforms.ladders.draw(camera)
	platforms.bridges.draw(camera)
end

--- Clears all platform data (for level reloading).
function platforms.clear()
	platforms.walls.clear()
	platforms.slopes.clear()
	platforms.ladders.clear()
	platforms.bridges.clear()
end

return platforms
