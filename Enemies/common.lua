local Animation = require('Animation')
local sprites = require('sprites')

local common = {}

--- Standard enemy draw function
--- @param enemy table The enemy to draw
function common.draw(enemy)
	if enemy.animation then
		enemy.animation:draw(
			enemy.x * sprites.tile_size,
			enemy.y * sprites.tile_size
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

return common
