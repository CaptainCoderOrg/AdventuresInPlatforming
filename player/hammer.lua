local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


local hammer = { name = "hammer" }


function hammer.start(player)
	player.animation = Animation.new(common.animations.HAMMER)
	player.hammer_state.remaining_time = (common.animations.HAMMER.frame_count * common.animations.HAMMER.ms_per_frame) / 1000
	common.clear_input_queue(player)
end


function hammer.update(player, dt)
	player.vx = 0
	player.vy = 0
	player.hammer_state.remaining_time = player.hammer_state.remaining_time - dt
	if player.hammer_state.remaining_time < 0 then
		if not common.process_input_queue(player) then
			player:set_state(player.states.idle)
		end
	end
end


function hammer.input(player)
	common.queue_inputs(player)
end


function hammer.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hammer
