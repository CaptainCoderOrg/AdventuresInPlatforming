local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')
local Prop = require('Prop')
local world = require('world')

local common = {}

local ROTATION_LERP_SPEED = 10  -- Rotation interpolation speed (higher = faster, ~0.1s to settle)
local TARGET_FPS = 60  -- Base frame rate for physics calculations
local anim_opts = { flipped = 1 }  -- Reused to avoid allocation

--- Sets up enemy animation, reusing existing instance when possible.
---@param enemy table The enemy instance
---@param definition table Animation definition to use
function common.set_animation(enemy, definition)
	anim_opts.flipped = enemy.direction
	if enemy.animation then
		enemy.animation:reinit(definition, anim_opts)
	else
		enemy.animation = Animation.new(definition, anim_opts)
	end
end

--- Applies gravity acceleration to an enemy in a frame-rate independent way.
---@param enemy table The enemy object with vy, gravity, max_fall_speed
---@param dt number Delta time in seconds
function common.apply_gravity(enemy, dt)
	enemy.vy = math.min(enemy.max_fall_speed, enemy.vy + enemy.gravity * dt * TARGET_FPS)
end

--- Applies velocity friction/damping in a frame-rate independent way.
---@param velocity number Current velocity
---@param friction number Per-frame friction at 60fps (e.g., 0.9 = 10% reduction per frame)
---@param dt number Delta time in seconds
---@return number Damped velocity
function common.apply_friction(velocity, friction, dt)
	return velocity * (friction ^ (dt * TARGET_FPS))
end

--- Check if player is within range of enemy
---@param enemy table The enemy
---@param range number Distance in tiles
---@return boolean
function common.player_in_range(enemy, range)
	if not enemy.target_player then return false end
	local dx = enemy.target_player.x - enemy.x
	local dy = enemy.target_player.y - enemy.y
	return dx * dx + dy * dy <= range * range
end

--- Get direction toward player (-1 or 1)
---@param enemy table The enemy
---@return number Direction (-1 left, 1 right)
function common.direction_to_player(enemy)
	if not enemy.target_player then return enemy.direction end
	return enemy.target_player.x < enemy.x and -1 or 1
end

--- Check if enemy has clear line of sight to player.
--- Uses raycast from enemy center to player center, filtering out non-solid shapes.
---@param enemy table The enemy with target_player reference
---@return boolean True if line of sight is clear
function common.has_line_of_sight(enemy)
	if not enemy.target_player then return false end

	local ts = sprites.tile_size
	local player = enemy.target_player

	-- Enemy center position (in pixels)
	local enemy_cx = (enemy.x + enemy.box.x + enemy.box.w / 2) * ts
	local enemy_cy = (enemy.y + enemy.box.y + enemy.box.h / 2) * ts

	-- Player center position (in pixels)
	local player_cx = (player.x + player.box.x + player.box.w / 2) * ts
	local player_cy = (player.y + player.box.y + player.box.h / 2) * ts

	-- Calculate ray direction and distance
	local dx = player_cx - enemy_cx
	local dy = player_cy - enemy_cy
	local distance = math.sqrt(dx * dx + dy * dy)

	if distance == 0 then return true end

	-- Normalize direction
	local dir_x = dx / distance
	local dir_y = dy / distance

	-- Cast ray from enemy to player
	local intersections = world.hc:raycast(enemy_cx, enemy_cy, dir_x, dir_y, distance)

	-- Get enemy's own shape and player's shape to filter them out
	local enemy_shape = world.shape_map[enemy]
	local player_shape = world.shape_map[player]

	-- Pre-compute threshold (distance minus 1 tile buffer, squared for perf)
	local threshold_sq = (distance - 1) * (distance - 1)

	for shape, hits in pairs(intersections) do
		-- Skip enemy's own shape
		if shape == enemy_shape then goto continue end
		-- Skip player's shape (we're checking if we can see them, not collide)
		if shape == player_shape then goto continue end
		-- Skip probes and triggers
		if shape.is_probe or shape.is_trigger then goto continue end
		-- Skip hitboxes (combat only, not physical barriers)
		if shape.is_hitbox then goto continue end

		local owner = shape.owner
		if owner then
			-- Skip other enemies
			if owner.is_enemy then goto continue end
			-- Skip player
			if owner.is_player then goto continue end
		end

		-- Any other solid geometry blocks line of sight
		for _, hit in pairs(hits) do
			local hit_dist_sq = (hit.x - enemy_cx)^2 + (hit.y - enemy_cy)^2
			if hit_dist_sq < threshold_sq then
				return false
			end
		end

		::continue::
	end

	return true
end

--- Standard enemy draw function
---@param enemy table The enemy to draw
function common.draw(enemy)
	if enemy.animation then
		local rotation = common.get_slope_rotation(enemy)
		local y_offset = enemy._cached_y_offset or 0
		local lift = Prop.get_pressure_plate_lift(enemy)

		enemy.animation:draw(
			sprites.px(enemy.x),
			sprites.stable_y(enemy, enemy.y, y_offset - lift),
			rotation
		)
	end
end

--- Check if enemy is blocked by wall or edge in current direction
---@param enemy table The enemy to check
---@return boolean True if blocked
function common.is_blocked(enemy)
	return (enemy.direction == -1 and (enemy.wall_left or enemy.edge_left)) or
	       (enemy.direction == 1 and (enemy.wall_right or enemy.edge_right))
end

--- Reverse enemy direction and flip animation
---@param enemy table The enemy to reverse
function common.reverse_direction(enemy)
	enemy.direction = -enemy.direction
	enemy.animation.flipped = enemy.direction
end

--- Create standard death state
---@param death_animation table Animation definition for death
---@return table State object
function common.create_death_state(death_animation)
	return {
		name = "death",
		start = function(enemy, _)
			anim_opts.flipped = enemy.direction
			enemy.animation = Animation.new(death_animation, anim_opts)
			enemy.vx = (enemy.hit_direction or -1) * 4
			enemy.vy = 0
			enemy.gravity = 0
		end,
		update = function(enemy, dt)
			enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
			if enemy.animation:is_finished() then
				enemy.marked_for_destruction = true
			end
		end,
		draw = common.draw
	}
end

--- Update enemy's visual rotation with smooth lerp
---@param enemy table The enemy with ground_normal
---@param dt number Delta time in seconds
function common.update_slope_rotation(enemy, dt)
	if not enemy.rotate_to_slope then return end

	-- Initialize rotation if not set
	enemy.slope_rotation = enemy.slope_rotation or 0

	-- Calculate target rotation from ground normal
	local target = 0
	if enemy.is_grounded then
		local nx = enemy.ground_normal.x
		local ny = enemy.ground_normal.y
		target = -math.atan(nx, -ny)  -- Negate for screen coordinates (Y-down)
	end

	-- Lerp toward target
	local diff = target - enemy.slope_rotation
	enemy.slope_rotation = enemy.slope_rotation + diff * math.min(1, ROTATION_LERP_SPEED * dt)
end

--- Get current slope rotation for drawing
---@param enemy table The enemy
---@return number Rotation angle in radians
function common.get_slope_rotation(enemy)
	if not enemy.rotate_to_slope then return 0 end
	return enemy.slope_rotation or 0
end

--- Get Y offset to keep sprite/hitbox grounded when rotated
--- Only needed for rectangle physics colliders; circle colliders sit naturally on slopes
---@param enemy table The enemy
---@return number Y offset in pixels
function common.get_slope_y_offset(enemy)
	if not enemy.rotate_to_slope or not enemy.animation then return 0 end
	-- Circle colliders don't need Y offset - they naturally conform to slopes
	if enemy.shape and enemy.shape.is_circle then return 0 end
	local rotation = enemy.slope_rotation or 0
	if rotation == 0 then return 0 end
	local sprite_width = enemy.animation.definition.width * config.ui.SCALE
	return (sprite_width / 2) * math.abs(math.sin(rotation))
end

return common
