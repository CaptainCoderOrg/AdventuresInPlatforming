local platforms = {}

platforms.walls = require('platforms/walls')
platforms.slopes = require('platforms/slopes')
platforms.ladders = require('platforms/ladders')

--- Parses a level and adds tiles to walls and slopes.
--- @param level_data table Level data with map array
--- @return table spawn Player spawn position {x, y}, level width and height, enemy spawns
function platforms.load_level(level_data)
	local spawn = nil
	local enemies = {}
	local width = 0
	local height = #level_data.map

	for y, row in ipairs(level_data.map) do
		-- Infer width from first row
		if y == 1 then
			width = #row
		end

		for x = 1, #row do
			local ch = row:sub(x, x)
			if ch == "#" then
				platforms.walls.add_tile(x - 1, y - 1)
			elseif ch == "X" then
				platforms.walls.add_solo_tile(x - 1, y - 1)
			elseif ch == "/" then
				platforms.slopes.add_tile(x - 1, y - 1, "/")
			elseif ch == "\\" then
				platforms.slopes.add_tile(x - 1, y - 1, "\\")
			elseif ch == "H" then
				platforms.ladders.add_ladder(x - 1, y - 1)
			elseif ch == "S" then
				spawn = { x = x - 1, y = y - 1 }
			elseif ch == "R" then
				table.insert(enemies, { x = x - 1, y = y - 1, type = "ratto" })
			elseif ch == "W" then
				table.insert(enemies, { x = x - 1, y = y - 1, type = "worm" })
			elseif ch == "G" then
				table.insert(enemies, { x = x - 1, y = y - 1, type = "spike_slug" })
			end
		end
	end

	return {
		spawn = spawn,
		enemies = enemies,
		width = width,
		height = height
	}
end

--- Builds all colliders for walls, slopes, and ladder tops.
function platforms.build()
	platforms.walls.build_colliders(true)
	platforms.slopes.build_colliders()
	platforms.ladders.build_colliders()
end

--- Draws all platforms (walls and slopes).
--- @param camera table Camera instance for viewport culling
function platforms.draw(camera)
	platforms.walls.draw(camera)
	platforms.slopes.draw(camera)
	platforms.ladders.draw(camera)
end

--- Clears all platform data (for level reloading).
function platforms.clear()
	platforms.walls.clear()
	platforms.slopes.clear()
end

return platforms
