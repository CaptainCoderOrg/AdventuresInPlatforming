local Animation = require('Animation')
local sprites = require('sprites')
local config = require('config')

local common = {}

local ROTATION_LERP_SPEED = 10  -- Higher = faster rotation

--- Check if player is within range of enemy
--- @param enemy table The enemy
--- @param range number Distance in tiles
--- @return boolean
function common.player_in_range(enemy, range)
	if not enemy.target_player then return false end
	local dx = enemy.target_player.x - enemy.x
	local dy = enemy.target_player.y - enemy.y
	return math.sqrt(dx * dx + dy * dy) <= range
end

--- Get direction toward player (-1 or 1)
--- @param enemy table The enemy
--- @return number Direction (-1 left, 1 right)
function common.direction_to_player(enemy)
	if not enemy.target_player then return enemy.direction end
	return enemy.target_player.x < enemy.x and -1 or 1
end

--- Standard enemy draw function
--- @param enemy table The enemy to draw
function common.draw(enemy)
	if enemy.animation then
		local rotation = common.get_slope_rotation(enemy)
		local y_offset = 0

		-- Offset Y to keep sprite grounded when rotated
		if rotation ~= 0 then
			local sprite_width = enemy.animation.definition.width * config.ui.SCALE
			y_offset = (sprite_width / 2) * math.abs(math.sin(rotation))
		end

		enemy.animation:draw(
			enemy.x * sprites.tile_size,
			enemy.y * sprites.tile_size + y_offset,
			rotation
		)
	end
end

--- Check if enemy is blocked by wall or edge in current direction
--- @param enemy table The enemy to check
--- @return boolean True if blocked
function common.is_blocked(enemy)
	return (enemy.direction == -1 and (enemy.wall_left or enemy.edge_left)) or
	       (enemy.direction == 1 and (enemy.wall_right or enemy.edge_right))
end

--- Reverse enemy direction and flip animation
--- @param enemy table The enemy to reverse
function common.reverse_direction(enemy)
	enemy.direction = -enemy.direction
	enemy.animation.flipped = enemy.direction
end

--- Create standard death state
--- @param death_animation table Animation definition for death
--- @return table State object
function common.create_death_state(death_animation)
	return {
		name = "death",
		start = function(enemy, definition)
			enemy.animation = Animation.new(death_animation, { flipped = enemy.direction })
			enemy.vx = (enemy.hit_direction or -1) * 4
			enemy.vy = 0
			enemy.gravity = 0
		end,
		update = function(enemy, dt)
			enemy.vx = enemy.vx * 0.9
			if enemy.animation:is_finished() then
				enemy.marked_for_destruction = true
			end
		end,
		draw = common.draw
	}
end

--- Update enemy's visual rotation with smooth lerp
--- @param enemy table The enemy with ground_normal
--- @param dt number Delta time in seconds
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
--- @param enemy table The enemy
--- @return number Rotation angle in radians
function common.get_slope_rotation(enemy)
	if not enemy.rotate_to_slope then return 0 end
	return enemy.slope_rotation or 0
end

return common
