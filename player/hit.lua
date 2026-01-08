local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local hit = { name = "hit" }


function hit.start(player)
	hit.knockback_speed = 2
	common.animations.HIT.frame = 0
	player.animation = common.animations.HIT
	hit.remaining_frames = common.animations.HIT.frame_count * common.animations.HIT.speed
	player.vy = math.max(0, player.vy)
end


function hit.update(player, dt)
	player.vx = -player.direction * hit.knockback_speed
	common.handle_gravity(player)
	hit.remaining_frames = hit.remaining_frames - 1
	if hit.remaining_frames < 0 then
		player.set_state(player.states.idle)
	end
end


function hit.input(player)
	
end


function hit.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hit
