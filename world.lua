local HC = require('APIS.hc')
local sprites = require('sprites')

local world = {}

-- Configuration
local MAX_ITERATIONS = 4
local GROUND_PROBE_DISTANCE = 4 -- Pixels to probe downward for ground adhesion

--- Sets ground collision flag and calculates normalized ground normal from separation vector.
--- @param cols table Collision flags to update
--- @param sep table Separation vector {x, y}
local function set_ground_from_sep(cols, sep)
	cols.ground = true
	local len = math.sqrt(sep.x * sep.x + sep.y * sep.y)
	if len > 0 then
		cols.ground_normal = { x = sep.x / len, y = sep.y / len }
	end
end

-- Initialize HC with spatial hash cell size (50 tiles * tile_size in pixels)
world.hc = HC:new(50 * sprites.tile_size)

-- Maps game objects to their HC shapes
world.shape_map = {}

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

--- Moves an object using separated X/Y collision passes.
--- Returns collision flags for ground, ceiling, and walls.
--- @param obj table Object with x, y, vx, vy, and box properties
--- @return table Collision flags {ground, ceiling, wall_left, wall_right}
function world.move(obj)
	local shape = world.shape_map[obj]
	if not shape then return { ground = false, ceiling = false, wall_left = false, wall_right = false, ground_normal = { x = 0, y = -1 } } end

	local ts = sprites.tile_size
	local cols = { ground = false, ceiling = false, wall_left = false, wall_right = false, ground_normal = { x = 0, y = -1 } }

	-- Get current shape position
	local x1, y1, _, _ = shape:bbox()

	-- X PASS: Move horizontally first, resolve X collisions
	local target_x = (obj.x + obj.box.x) * ts
	local dx = target_x - x1
	if dx ~= 0 then
		shape:move(dx, 0)

		for _ = 1, MAX_ITERATIONS do
			local collisions = world.hc:collisions(shape)
			local any_collision = false

			for other, sep in pairs(collisions) do
				if other ~= shape and sep.x ~= 0 then
					-- Only treat as wall if more horizontal than vertical (steeper than 45°)
					-- Slopes (<=45°) should be handled by Y pass, not blocked by X pass
					if math.abs(sep.x) > math.abs(sep.y) then
						any_collision = true
						shape:move(sep.x, 0)
						if sep.x > 0 then cols.wall_left = true end
						if sep.x < 0 then cols.wall_right = true end
					end
				end
			end

			if not any_collision then break end
		end
	end

	-- Y PASS: Move vertically, resolve Y collisions
	local _, cur_y, _, _ = shape:bbox()
	local target_y = (obj.y + obj.box.y) * ts
	local dy = target_y - cur_y
	if dy ~= 0 then
		shape:move(0, dy)
	end

	-- Always check for Y collisions (needed for ceiling slopes during horizontal dash)
	for _ = 1, MAX_ITERATIONS do
		local collisions = world.hc:collisions(shape)
		local any_collision = false

		for other, sep in pairs(collisions) do
			if other ~= shape and sep.y ~= 0 then
				any_collision = true
				if sep.y > 0 then
					-- Ceiling: apply full separation to prevent sliding on angled ceilings
					shape:move(sep.x, sep.y)
					cols.ceiling = true
					local len = math.sqrt(sep.x * sep.x + sep.y * sep.y)
					if len > 0 then
						cols.ceiling_normal = { x = sep.x / len, y = sep.y / len }
					end
				else
					-- Ground: only apply Y to allow slope walking
					shape:move(0, sep.y)
					set_ground_from_sep(cols, sep)
				end
			end
		end

		if not any_collision then break end
	end

	-- GROUND PROBE: If ground not detected, probe downward to find nearby ground
	-- This allows slope movement (moving up) while maintaining ground contact
	if not cols.ground then
		shape:move(0, GROUND_PROBE_DISTANCE)
		local collisions = world.hc:collisions(shape)
		local found_ground = false

		for other, sep in pairs(collisions) do
			if other ~= shape and sep.y < 0 then
				found_ground = true
				shape:move(0, sep.y)
				set_ground_from_sep(cols, sep)
				break
			end
		end

		if not found_ground then
			-- No ground found, undo probe
			shape:move(0, -GROUND_PROBE_DISTANCE)
		end
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
