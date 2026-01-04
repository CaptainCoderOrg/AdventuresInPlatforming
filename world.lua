local HC = require('APIS.hc')
local sprites = require('sprites')

local world = {}

-- Configuration
local MAX_ITERATIONS = 4

-- Initialize HC with spatial hash cell size (50 tiles * tile_size in pixels)
world.hc = HC:new(50 * sprites.tile_size)

-- Maps game objects to their HC shapes
world.shape_map = {}

--- Converts HC separation vector to collision normal.
--- Uses axis-aligned snapping for platformer physics.
--- @param sx number Separation X component
--- @param sy number Separation Y component
--- @return number, number Normal X and Y (-1, 0, or 1)
local function get_normal(sx, sy)
	local abs_x, abs_y = math.abs(sx), math.abs(sy)
	if abs_x > abs_y then
		return (sx > 0) and 1 or -1, 0
	elseif abs_y > 0 then
		return 0, (sy > 0) and 1 or -1
	end
	return 0, 0
end

--- Adds a rectangular collider for an object.
--- @param obj table Object with x, y, and box properties
function world.add_collider(obj)
	local ts = sprites.tile_size
	local px = (obj.x + obj.box.x) * ts
	local py = (obj.y + obj.box.y) * ts
	local pw = obj.box.w * ts
	local ph = obj.box.h * ts

	local shape = world.hc:rectangle(px, py, pw, ph)
	shape.owner = obj
	world.shape_map[obj] = shape
	return shape
end

--- Moves an object and resolves collisions, returning collision data.
--- @param obj table Object with x, y, vx, vy, and box properties
--- @return table Array of collision info with normal vectors
function world.move(obj)
	local shape = world.shape_map[obj]
	if not shape then return {} end

	local ts = sprites.tile_size
	local cols = {}

	-- Calculate where the shape should be based on obj position
	local target_x = (obj.x + obj.box.x) * ts
	local target_y = (obj.y + obj.box.y) * ts

	-- Get current shape position (top-left from bounding box)
	local x1, y1, _, _ = shape:bbox()

	-- Move shape to target position
	local dx = target_x - x1
	local dy = target_y - y1
	shape:move(dx, dy)

	-- Collision resolution loop
	for _ = 1, MAX_ITERATIONS do
		local collisions = world.hc:collisions(shape)
		local any_collision = false

		for other, sep in pairs(collisions) do
			-- Skip self-collision (shouldn't happen but safety check)
			if other ~= shape then
				any_collision = true

				-- Apply separation to escape collision
				shape:move(sep.x, sep.y)

				-- Calculate normal from separation vector
				local nx, ny = get_normal(sep.x, sep.y)

				-- Record collision for physics processing
				table.insert(cols, {
					normal = { x = nx, y = ny },
					other = other.owner
				})
			end
		end

		if not any_collision then break end
	end

	-- Update object position from final shape position
	local fx1, fy1, _, _ = shape:bbox()
	obj.x = fx1 / ts - obj.box.x
	obj.y = fy1 / ts - obj.box.y

	return cols
end

--- Removes a collider for an object.
--- @param obj table The object to remove
function world.remove_collider(obj)
	local shape = world.shape_map[obj]
	if shape then
		world.hc:remove(shape)
		world.shape_map[obj] = nil
	end
end

--- Adds a polygon collider for an object.
--- Vertices are in tile coordinates, converted to pixels internally.
--- @param obj table Object to associate with this collider
--- @param vertices table Array of {x, y} points in tile coordinates
--- @return table The created HC shape
function world.add_polygon(obj, vertices)
	local ts = sprites.tile_size
	local coords = {}

	for _, v in ipairs(vertices) do
		table.insert(coords, v.x * ts)
		table.insert(coords, v.y * ts)
	end

	local shape = world.hc:polygon(unpack(coords))
	shape.owner = obj
	world.shape_map[obj] = shape
	return shape
end

--- Syncs shape position to object without collision resolution.
--- Used for teleportation or direct position changes.
--- @param obj table Object with x, y, and box properties
function world.sync_position(obj)
	local shape = world.shape_map[obj]
	if not shape then return end

	local ts = sprites.tile_size
	local target_x = (obj.x + obj.box.x) * ts
	local target_y = (obj.y + obj.box.y) * ts

	local x1, y1, _, _ = shape:bbox()
	shape:move(target_x - x1, target_y - y1)
end

return world
