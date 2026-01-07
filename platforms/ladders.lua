local sprites = require('sprites')
local world = require('world')
local canvas = require('canvas')
local config = require('config')

local ladders = {}

ladders.tiles = {}
ladders.top_colliders = {}

--- Adds a ladder tile at the specified position.
--- Creates a trigger collider for climb detection.
--- @param x number Tile x coordinate
--- @param y number Tile y coordinate
function ladders.add_ladder(x, y)
	local key = x .. "," .. y
	local ladder = { x = x, y = y, box = { x = 0, y = 0, w = 1, h = 1 }, is_ladder = true }
	ladders.tiles[key] = ladder
	world.add_trigger_collider(ladder)
end

--- Builds solid colliders for ladder tops (one-way platforms).
--- Also marks top/bottom tiles for sprite selection.
--- Must be called after all ladders are added.
function ladders.build_colliders()
	for key, ladder in pairs(ladders.tiles) do
		-- Mark top tiles (no ladder above)
		local above_key = ladder.x .. "," .. (ladder.y - 1)
		if not ladders.tiles[above_key] then
			local top_collider = {
				x = ladder.x,
				y = ladder.y,
				box = { x = 0, y = 0, w = 1, h = 0.2 },
				is_ladder_top = true,
				ladder = ladder
			}
			ladder.is_top = true
			world.add_collider(top_collider)
			table.insert(ladders.top_colliders, top_collider)
		end

		-- Mark bottom tiles (no ladder below)
		local below_key = ladder.x .. "," .. (ladder.y + 1)
		if not ladders.tiles[below_key] then
			ladder.is_bottom = true
		end
	end
end

--- Draws all ladder tiles and debug bounding boxes.
function ladders.draw()
	for _, ladder in pairs(ladders.tiles) do
		local sprite = nil  -- nil = LADDER_MID (default)
		if ladder.is_top then
			sprite = "ladder_top"
		elseif ladder.is_bottom then
			sprite = "ladder_bottom"
		end
		sprites.draw_ladder(ladder.x * sprites.tile_size, ladder.y * sprites.tile_size, sprite)
	end

	if config.bounding_boxes then
		-- Yellow for ladder triggers (1x1 tiles)
		canvas.set_color("#FFFF00")
		for _, ladder in pairs(ladders.tiles) do
			canvas.draw_rect(
				ladder.x * sprites.tile_size,
				ladder.y * sprites.tile_size,
				sprites.tile_size,
				sprites.tile_size
			)
		end

		-- Red for ladder top colliders (one-way platforms)
		canvas.set_color("#FF0000")
		for _, top in ipairs(ladders.top_colliders) do
			canvas.draw_rect(
				(top.x + top.box.x) * sprites.tile_size,
				(top.y + top.box.y) * sprites.tile_size,
				top.box.w * sprites.tile_size,
				top.box.h * sprites.tile_size
			)
		end
	end
end

return ladders