local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


local hit = { name = "hit" }
local INVINCIBLE_TIME = 0.5 -- In seconds

function hit.start(player)
	player.hit_state.knockback_speed = 2
	player.animation = Animation.new(common.animations.HIT)
	player.hit_state.remaining_time = (common.animations.HIT.frame_count * common.animations.HIT.ms_per_frame) / 1000
	player.vy = math.max(0, player.vy)
end


function hit.update(player, dt)
	player.vx = -player.direction * player.hit_state.knockback_speed
	common.handle_gravity(player)
	player.hit_state.remaining_time = player.hit_state.remaining_time - dt
	if player.hit_state.remaining_time < 0 then
		player:set_state(player.states.idle)
		player.invincible_time = INVINCIBLE_TIME
	end
end


function hit.input(player)

end


function hit.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hit
