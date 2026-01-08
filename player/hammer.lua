local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local hammer = { name = "hammer" }


function hammer.start(player)
	common.animations.HAMMER.frame = 0
	player.animation = common.animations.HAMMER
	hammer.remaining_frames = common.animations.HAMMER.frame_count * common.animations.HAMMER.speed
end


function hammer.update(player, dt)
	player.vx = 0
	player.vy = 0
	hammer.remaining_frames = hammer.remaining_frames - 1
	if hammer.remaining_frames < 0 then
		player.set_state(player.states.idle)
	end
end


function hammer.input(player)
	
end


function hammer.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hammer
