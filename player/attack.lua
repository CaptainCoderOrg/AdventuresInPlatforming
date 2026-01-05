local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local attack = { name = "attack" }

local ATTACK_FRAMES = common.animations.ATTACK_0.frame_count * common.animations.ATTACK_0.speed
local ATTACK_COOLDOWN = ATTACK_FRAMES

local attack_animations = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 }

local function next_animation(player)
    local animation = attack_animations[attack.next_anim_ix]
	animation.frame = 0
	player.animation = animation
	attack.remaining_frames = animation.frame_count * animation.speed
    audio.play_sword_sound()
    attack.queued = false
    attack.next_anim_ix = attack.next_anim_ix + 1
    if attack.next_anim_ix > #attack_animations then
        attack.next_anim_ix = 1
    end
end

function attack.start(player)
    attack.count = 1
    attack.next_anim_ix = 1
    next_animation(player)
end

function attack.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
    if controls.attack_pressed() then
        attack.queued = true
    end
end


function attack.update(player, dt)
	player.vx = 0
	-- common.handle_gravity(player)
    player.vy = 0
	attack.remaining_frames = attack.remaining_frames - 1
	if attack.remaining_frames <= 0 then
        if attack.queued and player.attacks > attack.count then
            attack.count = attack.count + 1
            next_animation(player)
        else
            -- TODO: Decide actual state. Are we falling? Are we moving?
            player.set_state(player.states.idle)
            player.attack_cooldown = ATTACK_COOLDOWN
        end 
	end
end


function attack.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return attack
