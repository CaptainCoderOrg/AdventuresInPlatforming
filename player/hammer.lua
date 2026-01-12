local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


local hammer = { name = "hammer" }


function hammer.start(player)
	player.animation = Animation.new(common.animations.HAMMER)
	player.hammer_state.remaining_time = (common.animations.HAMMER.frame_count * common.animations.HAMMER.ms_per_frame) / 1000
end


function hammer.update(player, dt)
	player.vx = 0
	player.vy = 0
	player.hammer_state.remaining_time = player.hammer_state.remaining_time - dt
	if player.hammer_state.remaining_time < 0 then
		player:set_state(player.states.idle)
	end
end


function hammer.input(player)

end


function hammer.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hammer
