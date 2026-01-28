local sprites = require('sprites')
local controls = require('controls')
local state = require('world_state')

local world = {}

local MAX_ITERATIONS = 4
local GROUND_PROBE_DISTANCE = 4 -- Pixels to probe downward for ground adhesion

-- Prints collision source to console on each ground contact
world.debug_collisions = false

--- Returns a debug identifier string for an HC collision shape.
--- Used for logging collision sources when debug_collisions is enabled.
---@param shape table|nil The HC shape to identify
---@return string Human-readable shape description
local function identify_shape(shape)
	if not shape then return "nil" end
	if not shape.owner then return "no_owner" end
	local owner = shape.owner
	if owner.is_player then return "player" end
	if owner.is_enemy then return "enemy:" .. tostring(owner.type_key or "unknown") end
	if owner.is_bridge then return "bridge" end
	if owner.is_slope then return "slope" end
	if owner.type_key then
		local id = owner.id or "?"
		local x = owner.x or "?"
		return string.format("prop:%s(id=%s,x=%s)", owner.type_key, tostring(id), tostring(x))
	end
	if owner.is_ladder_top then return "ladder_top" end
	-- Check if it's a wall collider
	local x1, y1 = shape:bbox()
	return string.format("solid@(%.1f,%.1f)", x1/48, y1/48)
end

--- Sets ground collision flag and calculates normalized ground normal from separation vector.
--- Updates ground_normal in-place to avoid allocation (if ground_normal table exists).
--- @param cols table Collision flags to update
--- @param sep table Separation vector {x, y}
local function set_ground_from_sep(cols, sep)
	cols.ground = true
	if cols.ground_normal then
		local len = math.sqrt(sep.x * sep.x + sep.y * sep.y)
		if len > 0 then
			cols.ground_normal.x = sep.x / len
			cols.ground_normal.y = sep.y / len
		end
	end
end

--- Checks if a bridge collision should be skipped (pass-through conditions).
--- Bridges act as one-way platforms that can be passed through from below.
--- @param obj table Entity with y, vy, box, wants_drop_through, drop_through_y properties
--- @param bridge table Bridge collider with y, box properties and is_bridge flag
--- @return boolean True if collision should be skipped (allow pass-through)
local function should_skip_bridge(obj, bridge)
	local bridge_top = bridge.y + bridge.box.y
	local player_bottom = obj.y + obj.box.y + obj.box.h
	local overlap = player_bottom - bridge_top

	-- Allow pass-through when player is more than 0.3 tiles into the bridge.
	-- This threshold (slightly larger than bridge collider height of 0.2) prevents
	-- snapping onto bridges when jumping up through them.
	if overlap > 0.3 then return true end

	-- Must be falling to land on bridge
	if obj.vy <= 0 then return true end

	-- Drop-through: skip bridges at or slightly below where drop started.
	-- The 0.5 tile buffer ensures the player clears the bridge they're standing
	-- on before collision re-enables, preventing immediate re-landing.
	if obj.wants_drop_through and obj.drop_through_y then
		if bridge_top < obj.drop_through_y + 0.5 then return true end
	end

	return false
end

--- Checks if collision should be skipped (entities passing through each other).
--- Players and enemies pass through each other, except shields block enemies.
--- @param obj table First collision object
--- @param other table The other collision shape
--- @return boolean True if collision should be skipped
local function should_skip_collision(obj, other)
	-- Shields are solid barriers for enemies
	if obj.is_enemy and other.is_shield then
		return false
	end

	-- Players pass through their own shield
	if obj.is_player and other.is_shield and other.owner == obj then
		return true
	end

	local other_owner = other.owner

	-- Players pass through enemies
	if obj.is_player and other_owner and other_owner.is_enemy then
		return true
	end

	-- Enemies pass through players and other enemies
	if obj.is_enemy and other_owner then
		if other_owner.is_player or other_owner.is_enemy then
			return true
		end
	end

	return false
end

--- Checks if a shape is non-solid (trigger or probe) and should be skipped for physics.
--- If the shape is a trigger, it is added to the collision triggers list.
--- @param other table The collision shape to check
--- @param cols table Collision result with triggers array
--- @return boolean True if this shape should be skipped
local function is_non_solid(other, cols)
	if other.is_probe then return true end
	if other.is_trigger then
		cols.triggers[#cols.triggers + 1] = other
		return true
	end
	return false
end

-- Reference state from persistent module
world.hc = state.hc
world.shape_map = state.shape_map
world.trigger_map = state.trigger_map
world.hitbox_map = state.hitbox_map
world.shield_map = state.shield_map

--- Adds a rectangular collider for an object.
---@param obj table Object with x, y, and box properties
---@return table The created HC shape
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

--- Adds a circle collider for an object.
--- Uses the smaller of width/height as diameter.
---@param obj table Object with x, y, and box properties
---@return table The created HC shape
function world.add_circle_collider(obj)
	local ts = sprites.tile_size
	local radius = math.min(obj.box.w, obj.box.h) * ts / 2
	local cx = (obj.x + obj.box.x + obj.box.w / 2) * ts
	local cy = (obj.y + obj.box.y + obj.box.h / 2) * ts

	local shape = world.hc:circle(cx, cy, radius)
	shape.is_trigger = false
	shape.is_circle = true
	shape.radius = radius
	shape.owner = obj
	world.shape_map[obj] = shape
	return shape
end

--- Adds a trigger collider for an object (non-blocking, for overlap detection).
--- @param obj table Object with x, y, and box properties
--- @return table The created HC shape
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

--- Adds a combat hitbox for an object (separate from physics shape).
--- Used for hit detection with projectiles/attacks. Can be rotated.
---@param obj table Object with x, y, and box properties
---@return table The created HC shape
function world.add_hitbox(obj)
	local ts = sprites.tile_size
	local px = (obj.x + obj.box.x) * ts
	local py = (obj.y + obj.box.y) * ts
	local pw = obj.box.w * ts
	local ph = obj.box.h * ts

	local shape = world.hc:rectangle(px, py, pw, ph)
	shape.is_hitbox = true
	shape.owner = obj
	world.hitbox_map[obj] = shape
	return shape
end

--- Removes a combat hitbox for an object.
--- @param obj table The object whose hitbox to remove
function world.remove_hitbox(obj)
	local shape = world.hitbox_map[obj]
	if shape then
		world.hc:remove(shape)
		world.hitbox_map[obj] = nil
	end
end

--- Updates a combat hitbox position and rotation.
--- @param obj table Object with x, y, box, and optional slope_rotation
--- @param y_offset number Y offset in pixels (for sprite grounding)
function world.update_hitbox(obj, y_offset)
	local shape = world.hitbox_map[obj]
	if not shape then return end

	local ts = sprites.tile_size
	local px = (obj.x + obj.box.x) * ts
	local py = (obj.y + obj.box.y) * ts + (y_offset or 0)

	-- Move shape to new position
	local old_x, old_y, _, _ = shape:bbox()
	local dx = px - old_x
	local dy = py - old_y
	shape:move(dx, dy)

	-- Apply rotation if available (negate to match visual rotation)
	if obj.slope_rotation then
		local cx = px + (obj.box.w * ts / 2)
		local cy = py + (obj.box.h * ts / 2)
		shape:setRotation(-obj.slope_rotation, cx, cy)
	end
end

---@class CollisionResult
---@field ground boolean Whether standing on ground
---@field ceiling boolean Whether touching ceiling
---@field wall_left boolean Whether touching wall on left
---@field wall_right boolean Whether touching wall on right
---@field ground_normal {x: number, y: number} Normal vector of ground surface
---@field ceiling_normal {x: number, y: number} Normal vector of ceiling surface (check has_ceiling_normal)
---@field has_ceiling_normal boolean Whether ceiling_normal was set this frame
---@field is_ladder_top boolean|nil Whether standing on ladder top
---@field ladder_from_top table|nil Ladder object when standing on top
---@field is_bridge boolean|nil Whether standing on bridge
---@field triggers table[] Array of trigger shapes overlapping

--- Resets a cols table to default values (avoids allocation when reusing)
---@param cols CollisionResult Collision flags table to reset
local function reset_cols(cols)
	cols.ground = false
	cols.ceiling = false
	cols.wall_left = false
	cols.wall_right = false
	if cols.ground_normal then
		cols.ground_normal.x = 0
		cols.ground_normal.y = -1
	end
	if cols.ceiling_normal then
		cols.ceiling_normal.x = 0
		cols.ceiling_normal.y = 1
		cols.has_ceiling_normal = false
	end
	cols.is_ladder_top = nil
	cols.ladder_from_top = nil
	cols.is_bridge = nil
	cols.shield = false
	cols.shield_owner = nil
	-- Clear triggers array if present
	if cols.triggers then
		for i = 1, #cols.triggers do cols.triggers[i] = nil end
	end
end

--- Creates a new cols table with default values
---@return CollisionResult Fresh collision flags table
local function new_cols()
	return {
		ground = false, ceiling = false, wall_left = false, wall_right = false,
		ground_normal = { x = 0, y = -1 },
		ceiling_normal = { x = 0, y = 1 },
		has_ceiling_normal = false,
		shield = false, shield_owner = nil,
		triggers = {}
	}
end

--- Moves an object using separated X/Y collision passes.
--- Returns collision flags for ground, ceiling, and walls.
--- @param obj table Object with x, y, vx, vy, and box properties
--- @param cols table|nil Optional reusable collision result table (avoids allocation)
--- @return table Collision flags {ground, ceiling, wall_left, wall_right}
function world.move(obj, cols)
	local shape = world.shape_map[obj]
	if not shape then
		if cols then
			reset_cols(cols)
			return cols
		end
		return new_cols()
	end

	local ts = sprites.tile_size
	if cols then
		reset_cols(cols)
	else
		cols = new_cols()
	end

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
				if is_non_solid(other, cols) then goto skip_x_collision end
				if should_skip_collision(obj, other) then goto skip_x_collision end
				if other.is_shield then
					cols.shield = true
					cols.shield_owner = other.owner
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
			if is_non_solid(other, cols) then goto skip_y_collision end
			if should_skip_collision(obj, other) then goto skip_y_collision end
			if other.is_shield then
				cols.shield = true
				cols.shield_owner = other.owner
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
			-- Detect bridge collision (one-way platform)
			if other.owner and other.owner.is_bridge then
				if should_skip_bridge(obj, other.owner) then
					goto skip_y_collision
				end
				cols.is_bridge = true
			end
			if other ~= shape and sep.y ~= 0 then
				any_collision = true
				if sep.y > 0 then
					-- Ceiling: apply full separation to prevent sliding on angled ceilings
					shape:move(sep.x, sep.y)
					cols.ceiling = true
					if cols.ceiling_normal then
						local len = math.sqrt(sep.x * sep.x + sep.y * sep.y)
						if len > 0 then
							cols.ceiling_normal.x = sep.x / len
							cols.ceiling_normal.y = sep.y / len
							cols.has_ceiling_normal = true
						end
					end
				else
					-- Ground: only apply Y to allow slope walking
					shape:move(0, sep.y)
					set_ground_from_sep(cols, sep)
					if world.debug_collisions and obj.is_player then
						print("[COLLISION] Ground from Y-pass: " .. identify_shape(other))
					end
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
			if is_non_solid(other, cols) then goto skip_ground_collision end
			if should_skip_collision(obj, other) then goto skip_ground_collision end
			-- Apply bridge pass-through logic (overlap, falling direction, drop-through)
			if other.owner and other.owner.is_bridge then
				if should_skip_bridge(obj, other.owner) then
					goto skip_ground_collision
				end
			end
			if other ~= shape and sep.y < 0 then
				found_ground = true
				shape:move(0, sep.y)
				set_ground_from_sep(cols, sep)
				if world.debug_collisions and obj.is_player then
					print("[COLLISION] Ground from probe: " .. identify_shape(other))
				end
				break
			end
			::skip_ground_collision::
		end

		if not found_ground then
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
		-- Skip probe and trigger shapes
		if other.is_probe or other.is_trigger then goto continue end

		local owner = other.owner
		local is_player = owner and owner.is_player
		local is_enemy = owner and owner.is_enemy

		-- Check if this is a valid collision target
		local is_physics_shape = world.shape_map[owner] == other
		local is_combat_hitbox = world.hitbox_map[owner] == other

		if not is_player then
			if is_enemy and is_combat_hitbox then
				-- Enemy with combat hitbox - use hitbox for detection
				enemy_hit = { shape = other, sep = sep }
			elseif is_enemy and is_physics_shape and not world.hitbox_map[owner] then
				-- Enemy without combat hitbox - fall back to physics shape
				enemy_hit = { shape = other, sep = sep }
			elseif is_physics_shape and not is_enemy and not solid_hit then
				-- Non-enemy physics shape (walls, platforms)
				-- Skip bridges so projectiles pass through
				local is_bridge = owner and owner.is_bridge
				local is_shield = other.is_shield
				if not is_bridge then
					solid_hit = { shape = other, sep = sep, is_shield = is_shield }
				end
			end
		end
		::continue::
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
			y = obj.y,
			is_shield = hit.is_shield
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

--- Removes a trigger collider for an object.
--- @param obj table The object to remove
function world.remove_trigger_collider(obj)
	local shape = world.trigger_map[obj]
	if shape then
		world.hc:remove(shape)
		world.trigger_map[obj] = nil
	end
end

--- Calculates shield X offset based on player direction.
--- Shield is positioned at player's front edge.
---@param player table Player with direction, box properties
---@param shield_w number Shield width in tiles
---@return number X offset in tiles from player.x
local function get_shield_x_offset(player, shield_w)
	if player.direction == 1 then
		return player.box.x + player.box.w
	end
	return player.box.x - shield_w
end

--- Adds a shield collider for a player (solid physics collider).
--- Idempotent: removes existing shield before creating new one.
--- @param player table Player object
--- @param shield_box table Shield dimensions {w, h}
--- @return table The created shield shape
function world.add_shield(player, shield_box)
	-- Remove existing shield to prevent orphaned colliders
	world.remove_shield(player)

	local ts = sprites.tile_size
	local x_offset = get_shield_x_offset(player, shield_box.w)

	local px = (player.x + x_offset) * ts
	local py = (player.y + player.box.y) * ts
	local pw = shield_box.w * ts
	local ph = shield_box.h * ts

	local shape = world.hc:rectangle(px, py, pw, ph)
	shape.is_shield = true
	shape.owner = player
	world.shield_map[player] = shape
	return shape
end

--- Updates shield position based on player position and direction.
--- @param player table Player with x, y, direction, box properties
--- @param shield_box table Shield dimensions {w, h}
function world.update_shield(player, shield_box)
	local shape = world.shield_map[player]
	if not shape then return end

	local ts = sprites.tile_size
	local x_offset = get_shield_x_offset(player, shield_box.w)

	local target_x = (player.x + x_offset) * ts
	local target_y = (player.y + player.box.y) * ts

	local old_x, old_y, _, _ = shape:bbox()
	shape:move(target_x - old_x, target_y - old_y)
end

--- Removes the shield collider for a player.
--- @param player table The player object
function world.remove_shield(player)
	local shape = world.shield_map[player]
	if shape then
		world.hc:remove(shape)
		world.shield_map[player] = nil
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

--- Checks if a point has solid ground.
--- Uses a persistent probe shape to avoid allocations.
--- @param x number X position in tiles
--- @param y number Y position in tiles
--- @return boolean True if solid ground exists at point
function world.point_has_ground(x, y)
	local ts = sprites.tile_size
	local px, py = x * ts - ts/2, y * ts - ts

	-- Lazy-init persistent probe (once per level)
	if not state.ground_probe then
		state.ground_probe = world.hc:rectangle(px, py, ts, ts)
		state.ground_probe.is_probe = true
	else
		-- moveTo uses center coordinates, not top-left
		state.ground_probe:moveTo(px + ts/2, py + ts/2)
	end

	local collisions = world.hc:collisions(state.ground_probe)

	for other, _ in pairs(collisions) do
		local skip = other.is_probe or other.is_trigger or (other.owner and other.owner.is_enemy)
		if not skip then return true end
	end
	return false
end

--- Clears persistent probe shapes.
--- Call when clearing/reloading a level to prevent stale shapes.
function world.clear_probes()
	if state.ground_probe then
		world.hc:remove(state.ground_probe)
		state.ground_probe = nil
	end
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
