local HC = require('hc')
local sprites = require('sprites')
local controls = require('controls')

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

--- Checks if collision should be skipped (player/enemy pass through each other).
--- @param obj table First collision object
--- @param other_owner table Owner of the other collision shape
--- @return boolean True if collision should be skipped
local function should_skip_collision(obj, other_owner)
	if obj.is_player and other_owner and other_owner.is_enemy then return true end
	if obj.is_enemy and other_owner and other_owner.is_player then return true end
	if obj.is_enemy and other_owner and other_owner.is_enemy then return true end
	return false
end

-- Initialize HC with spatial hash cell size (50 tiles * tile_size in pixels)
world.hc = HC:new(50 * sprites.tile_size)

-- Maps game objects to their HC shapes
world.shape_map = {}

-- Maps game objects to their HC trigger shapes
world.trigger_map = {}

--- Adds a rectangular collider for an object.
--- @param obj table Object with x, y, and box properties
function world.add_collider(obj)
	local ts = sprites.tile_size
	local px = (obj.x + obj.box.x) * ts
	local py = (obj.y + obj.box.y) * ts
	local pw = obj.box.w * ts
	local ph = obj.box.h * ts

	local shape = world.hc:rectangle(px, py, pw, ph)
	shape.is_trigger = false
	shape.owner = obj
	world.shape_map[obj] = shape
	return shape
end

function world.add_trigger_collider(obj)
	local ts = sprites.tile_size
	local px = (obj.x + obj.box.x) * ts
	local py = (obj.y + obj.box.y) * ts
	local pw = obj.box.w * ts
	local ph = obj.box.h * ts

	local shape = world.hc:rectangle(px, py, pw, ph)
	shape.is_trigger = true
	shape.owner = obj
	world.trigger_map[obj] = shape
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
	local cols = { ground = false, ceiling = false, wall_left = false, wall_right = false, ground_normal = { x = 0, y = -1 }, triggers = {} }

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
				if other.is_trigger then
					table.insert(cols.triggers, other)
					goto skip_x_collision
				end
				if should_skip_collision(obj, other.owner) then
					goto skip_x_collision
				end
				if other ~= shape and sep.x ~= 0 then
					-- Only treat as wall if more horizontal than vertical (steeper than 45°)
					-- Slopes (<=45°) should be handled by Y pass, not blocked by X pass
					if math.abs(sep.x) > math.abs(sep.y) then
						any_collision = true
						shape:move(sep.x, 0)
						-- Skip wall flags for slopes to prevent wall sliding on them
						if not (other.owner and other.owner.is_slope) then
							if sep.x > 0 then cols.wall_left = true end
							if sep.x < 0 then cols.wall_right = true end
						end
					end
				end
				::skip_x_collision::
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
			if other.is_trigger then
				table.insert(cols.triggers, other)
				goto skip_y_collision
			end
			if should_skip_collision(obj, other.owner) then
				goto skip_y_collision
			end
			-- Detect ladder top collision before one-way platform check
			-- This ensures standing_on_ladder_top works even when pressing down
			if other.owner and other.owner.is_ladder_top then
				cols.is_ladder_top = true
				cols.ladder_from_top = other.owner.ladder
				-- One-way platform: pass-through from below, when pressing down, or when climbing
				if obj.vy < 0 or controls.down_down() or obj.is_climbing then
					goto skip_y_collision
				end
			end
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
			::skip_y_collision::
		end

		if not any_collision then break end
	end

	-- GROUND PROBE: If ground not detected, probe downward to find nearby ground
	-- This allows slope movement (moving up) while maintaining ground contact
	-- Skip when climbing to allow upward movement on ladders
	if not cols.ground and not obj.is_climbing then
		shape:move(0, GROUND_PROBE_DISTANCE)
		local collisions = world.hc:collisions(shape)
		local found_ground = false

		for other, sep in pairs(collisions) do
			if other.is_trigger then
				table.insert(cols.triggers, other)
				goto skip_ground_collision
			end
			if should_skip_collision(obj, other.owner) then
				goto skip_ground_collision
			end
			if other ~= shape and sep.y < 0 then
				found_ground = true
				shape:move(0, sep.y)
				set_ground_from_sep(cols, sep)
				break
			end
			::skip_ground_collision::
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

--- Moves a trigger object and detects first collision along path.
--- @param obj table The trigger object to move
--- @return table|nil collision info {other, x, y} or nil if no collision
function world.move_trigger(obj)
	local shape = world.trigger_map[obj]
	if not shape then return nil end

	local ts = sprites.tile_size
	local old_x, old_y, _, _ = shape:bbox()
	local new_x = (obj.x + obj.box.x) * ts
	local new_y = (obj.y + obj.box.y) * ts

	local dx = new_x - old_x
	local dy = new_y - old_y

	if dx == 0 and dy == 0 then return nil end

	shape:move(dx, dy)

	local collisions = world.hc:collisions(shape)

	-- First pass: prioritize enemy collisions
	local enemy_hit = nil
	local solid_hit = nil

	for other, sep in pairs(collisions) do
		if world.shape_map[other.owner] == other and not (other.owner and other.owner.is_player) then
			if other.owner and other.owner.is_enemy then
				enemy_hit = { shape = other, sep = sep }
			elseif not solid_hit then
				solid_hit = { shape = other, sep = sep }
			end
		end
	end

	-- Return enemy hit if found, otherwise solid hit
	local hit = enemy_hit or solid_hit
	if hit then
		shape:move(hit.sep.x, hit.sep.y)

		local x, y, _, _ = shape:bbox()
		obj.x = x / ts - obj.box.x
		obj.y = y / ts - obj.box.y

		return {
			other = hit.shape,
			x = obj.x,
			y = obj.y
		}
	end

	return nil
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
	local shape = world.shape_map[obj] or world.trigger_map[obj]
	if not shape then return end

	local ts = sprites.tile_size
	local target_x = (obj.x + obj.box.x) * ts
	local target_y = (obj.y + obj.box.y) * ts

	local x1, y1, _, _ = shape:bbox()
	shape:move(target_x - x1, target_y - y1)
end

--- Raycasts downward to find the ground below a position
--- @param player table Player object (to filter out player's own collider)
--- @param max_distance number Maximum search distance downward (in tiles)
--- @return number|nil Landing Y position (in tiles), or nil if no ground found
function world.raycast_down(player, max_distance)
	local tile_size = sprites.tile_size
	local box = player.box

	-- Get player's collision shape to filter it out
	local player_shape = world.shape_map[player]

	-- Cast a ray downward from player's center
	local center_x = (player.x + box.x + box.w / 2) * tile_size
	local player_bottom_y = (player.y + box.y + box.h) * tile_size
	local ray_start_x, ray_start_y = center_x, player_bottom_y
	local ray_dx, ray_dy = 0, 1  -- Pointing straight down
	local ray_range = max_distance * tile_size

	-- Use HC's raycast method to find intersections
	local intersections = world.hc:raycast(ray_start_x, ray_start_y, ray_dx, ray_dy, ray_range)

	local closest_ground_y = nil

	for shape, hits in pairs(intersections) do
		-- Skip player's own collider
		if shape == player_shape then
			goto continue
		end

		-- Skip triggers
		local is_trigger = world.trigger_map[shape.owner] ~= nil
		if is_trigger then
			goto continue
		end

		-- Find the closest hit by distance from ray origin
		-- Note: HC uses sparse arrays with pairs(), not ipairs()
		local hit_count = 0
		for _ in pairs(hits) do hit_count = hit_count + 1 end

		if hit_count > 0 then
			local closest_hit = nil
			local closest_distance = math.huge

			for _, hit in pairs(hits) do
				local distance = hit.y - ray_start_y
				if distance >= 0 and distance < closest_distance then
					closest_hit = hit
					closest_distance = distance
				end
			end

			if closest_hit then
				-- Convert hit Y to player standing position (tiles)
				local stand_y = (closest_hit.y / tile_size) - box.y - box.h

				if not closest_ground_y or stand_y < closest_ground_y then
					closest_ground_y = stand_y
				end
			end
		end

		::continue::
	end

	return closest_ground_y
end

return world
