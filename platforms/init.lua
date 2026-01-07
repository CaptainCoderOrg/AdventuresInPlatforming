local platforms = {}

platforms.walls = require('platforms/walls')
platforms.slopes = require('platforms/slopes')
platforms.ladders = require('platforms/ladders')

--- Parses a level and adds tiles to walls and slopes.
--- @param level_data table Level data with map array
--- @return table|nil spawn Player spawn position {x, y} or nil if not found
function platforms.load_level(level_data)
	local spawn = nil

	for y, row in ipairs(level_data.map) do
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
			end
		end
	end

	return spawn
end

--- Builds all colliders for walls, slopes, and ladder tops.
function platforms.build()
	platforms.walls.build_colliders(true)
	platforms.slopes.build_colliders()
	platforms.ladders.build_colliders()
end

--- Draws all platforms (walls and slopes).
function platforms.draw()
	platforms.walls.draw()
	platforms.slopes.draw()
	platforms.ladders.draw()
end

--- Clears all platform data (for level reloading).
function platforms.clear()
	platforms.walls.clear()
	platforms.slopes.clear()
end

return platforms
