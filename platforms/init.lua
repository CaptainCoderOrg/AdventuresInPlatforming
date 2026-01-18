local platforms = {}

platforms.walls = require('platforms/walls')
platforms.slopes = require('platforms/slopes')
platforms.ladders = require('platforms/ladders')
platforms.bridges = require('platforms/bridges')

--- Parses a level and adds tiles to walls and slopes.
--- @param level_data table Level data with map array and optional symbols table
--- @return {spawn: {x: number, y: number}|nil, enemies: {x: number, y: number, type: string}[], signs: {x: number, y: number, text: string}[], width: number, height: number}
function platforms.load_level(level_data)
	local spawn = nil
	local enemies = {}
	local signs = {}
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
				if def.type == "spawn" then
					spawn = { x = tx, y = ty }
				elseif def.type == "enemy" then
					table.insert(enemies, { x = tx, y = ty, type = def.key })
				elseif def.type == "sign" then
					table.insert(signs, { x = tx, y = ty, text = def.text })
				end
			end
		end
	end

	return {
		spawn = spawn,
		enemies = enemies,
		signs = signs,
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
