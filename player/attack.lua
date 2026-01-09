local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')


local attack = { name = "attack" }

local ATTACK_COOLDOWN = 12
local HOLD_FRAMES = 4

local attack_animations = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 }

local function next_animation(player)
    local animation = attack_animations[player.attack_state.next_anim_ix]
	animation.frame = 0
	player.animation = animation
	player.attack_state.remaining_frames = (animation.frame_count * animation.speed)
    audio.play_sword_sound()
    player.attack_state.queued = false
    player.attack_state.next_anim_ix = player.attack_state.next_anim_ix + 1
    if player.attack_state.next_anim_ix > #attack_animations then
        player.attack_state.next_anim_ix = 1
    end
end

function attack.start(player)
    player.attack_state.count = 1
    player.attack_state.next_anim_ix = 1
    next_animation(player)
end

function attack.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
    if controls.attack_pressed() then
        player.attack_state.queued = true
    end
end


function attack.update(player, dt)
	player.vx = 0
    player.vy = 0
	player.attack_state.remaining_frames = player.attack_state.remaining_frames - 1
	if player.attack_state.remaining_frames <= 0 then
        if player.attack_state.queued and player.attacks > player.attack_state.count then
            player.attack_state.count = player.attack_state.count + 1
            next_animation(player)
        elseif player.attack_state.remaining_frames <= -HOLD_FRAMES then
            -- TODO: Decide actual state. Are we falling? Are we moving?
            player:set_state(player.states.idle)
            player.attack_cooldown = ATTACK_COOLDOWN
        end
	end
end


function attack.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return attack
