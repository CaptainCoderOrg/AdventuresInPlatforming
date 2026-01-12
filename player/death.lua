local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local canvas = require('canvas')
local config = require('config')


local death = { name = "death" }

function death.start(player)
	player.animation = sprites.create_animation_state(common.animations.DEATH)
	player.vx = 0
	player.vy = 0
end


function death.update(player, dt)
	if player.animation.frame == player.animation.definition.frame_count - 1 then
		player.is_dead = true
	end
end


function death.input(player)
	if config.debug and canvas.is_key_pressed(canvas.keys.R) then
		player.is_dead = false
		player.damage = 0
		player:set_state(player.states.idle)
	end
end


function death.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return death
