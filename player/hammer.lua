local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local hammer = { name = "hammer" }


function hammer.start(player)
	player.animation = sprites.create_animation_state(common.animations.HAMMER)
	player.hammer_state.remaining_frames = common.animations.HAMMER.frame_count * common.animations.HAMMER.speed
end


function hammer.update(player, dt)
	player.vx = 0
	player.vy = 0
	player.hammer_state.remaining_frames = player.hammer_state.remaining_frames - 1
	if player.hammer_state.remaining_frames < 0 then
		player:set_state(player.states.idle)
	end
end


function hammer.input(player)

end


function hammer.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hammer
