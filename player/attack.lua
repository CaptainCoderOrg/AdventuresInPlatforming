local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local attack = { name = "attack" }

local ATTACK_FRAMES = common.animations.ATTACK_0.frame_count * common.animations.ATTACK_0.speed
local ATTACK_COOLDOWN = ATTACK_FRAMES


function attack.start(player)
	common.animations.ATTACK_0.frame = 0
	player.animation = common.animations.ATTACK_0
	attack.remaining_frames = ATTACK_FRAMES
    audio.play_sword_sound()
end


function attack.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
end


function attack.update(player, dt)
	player.vx = 0
	-- common.handle_gravity(player)
    player.vy = 0
	attack.remaining_frames = attack.remaining_frames - 1
	if attack.remaining_frames <= 0 then
		-- TODO: Decide actual state. Are we falling? Are we moving?
		player.set_state(player.states.idle)
        player.attack_cooldown = ATTACK_COOLDOWN
	end
end


function attack.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return attack
