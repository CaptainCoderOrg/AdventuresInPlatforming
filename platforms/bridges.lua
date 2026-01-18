local common = require('platforms/common')
local canvas = common.canvas
local sprites = common.sprites
local config = common.config
local world = common.world
local walls = require('platforms/walls')
local state = require('platforms/bridges_state')

local bridges = {}

bridges.tiles = state.tiles
bridges.colliders = state.colliders

--- Adds a bridge tile at the specified position.
--- @param x number Tile x coordinate
--- @param y number Tile y coordinate
function bridges.add_bridge(x, y)
	local key = x .. "," .. y
	local bridge = { x = x, y = y, is_bridge = true }
	bridges.tiles[key] = bridge
end

--- Builds solid colliders for bridges (one-way platforms).
--- Merges horizontally adjacent bridges into single colliders.
--- Also determines sprite type (left/middle/right) for each bridge.
--- Must be called after all bridges are added.
function bridges.build_colliders()
	-- First pass: determine sprite type for each bridge
	for _, bridge in pairs(bridges.tiles) do
		local left_key = (bridge.x - 1) .. "," .. bridge.y
		local right_key = (bridge.x + 1) .. "," .. bridge.y
		local has_bridge_left = bridges.tiles[left_key] ~= nil
		local has_bridge_right = bridges.tiles[right_key] ~= nil
		local has_wall_left = walls.has_tile(bridge.x - 1, bridge.y)
		local has_wall_right = walls.has_tile(bridge.x + 1, bridge.y)

		-- Select sprite: walls take priority, then check for bridge ends
		if has_wall_left then
			bridge.sprite_type = "left"
		elseif has_wall_right then
			bridge.sprite_type = "right"
		elseif not has_bridge_left then
			bridge.sprite_type = "left"
		elseif not has_bridge_right then
			bridge.sprite_type = "right"
		else
			bridge.sprite_type = "middle"
		end
	end

	-- Group bridges by row (Y coordinate)
	local rows = {}
	for _, bridge in pairs(bridges.tiles) do
		rows[bridge.y] = rows[bridge.y] or {}
		table.insert(rows[bridge.y], bridge)
	end

	-- For each row, sort by X and find horizontal runs
	for _, row_bridges in pairs(rows) do
		table.sort(row_bridges, function(a, b) return a.x < b.x end)

		local run_start = 1
		while run_start <= #row_bridges do
			-- Find end of this run (consecutive X values)
			local run_end = run_start
			while run_end < #row_bridges and
			      row_bridges[run_end + 1].x == row_bridges[run_end].x + 1 do
				run_end = run_end + 1
			end

			-- Create single collider for this run
			local first = row_bridges[run_start]
			local width = run_end - run_start + 1
			local collider = {
				x = first.x,
				y = first.y,
				box = { x = 0, y = 0, w = width, h = 0.2 },
				is_bridge = true
			}
			world.add_collider(collider)
			table.insert(bridges.colliders, collider)

			run_start = run_end + 1
		end
	end
end

--- Draws all bridge tiles and debug bounding boxes.
--- @param camera table Camera instance for viewport culling
function bridges.draw(camera)
	local ts = sprites.tile_size
	local min_x, min_y, max_x, max_y = camera:get_visible_bounds(ts)

	for _, bridge in pairs(bridges.tiles) do
		if bridge.x < min_x or bridge.x > max_x or bridge.y < min_y or bridge.y > max_y then
			goto continue
		end

		local sprite = sprites.environment.bridge_middle
		if bridge.sprite_type == "left" then
			sprite = sprites.environment.bridge_left
		elseif bridge.sprite_type == "right" then
			sprite = sprites.environment.bridge_right
		end
		sprites.draw_bridge(bridge.x * ts, bridge.y * ts, sprite)

		::continue::
	end

	if config.bounding_boxes then
		-- Cyan for bridge colliders
		canvas.set_color("#00FFFF")
		for _, col in ipairs(bridges.colliders) do
			canvas.draw_rect(
				(col.x + col.box.x) * ts,
				(col.y + col.box.y) * ts,
				col.box.w * ts,
				col.box.h * ts
			)
		end
	end
end

--- Clears all bridge data (for level reloading).
function bridges.clear()
	for _, col in ipairs(state.colliders) do
		world.remove_collider(col)
	end
	-- Clear tables in place to preserve state module references
	for k in pairs(state.tiles) do
		state.tiles[k] = nil
	end
	for i = #state.colliders, 1, -1 do
		state.colliders[i] = nil
	end
end

return bridges
