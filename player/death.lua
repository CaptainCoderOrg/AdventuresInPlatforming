local Animation = require('Animation')
local canvas = require('canvas')
local common = require('player.common')
local config = require('config')
local world = require('world')

--- Death state: Player has died.
--- Plays death animation, then sets is_dead flag for game over handling.
local death = { name = "death" }

--- Called when entering death state. Stops all movement and plays death animation.
---@param player table The player object
function death.start(player)
	world.remove_shield(player)
	player.animation = Animation.new(common.animations.DEATH)
	player.vx = 0
	player.vy = 0
end

--- Updates death state. Sets is_dead flag when animation completes.
---@param player table The player object
---@param dt number Delta time (unused)
function death.update(player, dt)
	if player.animation:is_finished() then
		player.is_dead = true
	end
end

--- Handles input while dead. Debug mode allows instant respawn with R key.
---@param player table The player object
function death.input(player)
	if config.debug and canvas.is_key_pressed(canvas.keys.R) then
		player.is_dead = false
		player.damage = 0
		player:set_state(player.states.idle)
	end
end

--- Renders the player in death animation.
---@param player table The player object
function death.draw(player)
	common.draw(player)
end

return death
