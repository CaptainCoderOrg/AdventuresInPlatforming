local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


local hit = { name = "hit" }
local INVINCIBLE_TIME = 1.2

function hit.start(player)
	player.hit_state.knockback_speed = 2
	player.hit_state.queued_jump = false
	player.hit_state.queued_attack = false
	player.animation = Animation.new(common.animations.HIT)
	player.hit_state.remaining_time = (common.animations.HIT.frame_count * common.animations.HIT.ms_per_frame) / 1000
	player.vy = math.max(0, player.vy)
end


function hit.update(player, dt)
	player.vx = -player.direction * player.hit_state.knockback_speed
	common.handle_gravity(player)
	player.hit_state.remaining_time = player.hit_state.remaining_time - dt
	if player.hit_state.remaining_time < 0 then
		player.invincible_time = INVINCIBLE_TIME
		if player.hit_state.queued_attack then
			player:set_state(player.states.attack)
		elseif player.hit_state.queued_jump and player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player:set_state(player.states.air)
		else
			player:set_state(player.states.idle)
		end
	end
end


function hit.input(player)
	if controls.jump_pressed() then
		player.hit_state.queued_jump = true
	end
	if controls.attack_pressed() then
		player.hit_state.queued_attack = true
	end
end


function hit.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hit
