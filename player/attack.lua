local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')
local Enemy = require('Enemies')
local config = require('config')
local canvas = require('canvas')


local attack = { name = "attack" }

local ATTACK_COOLDOWN = 0.2
local HOLD_TIME = 0.16

local attack_animations = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 }

local SWORD_WIDTH = 1.0

local function get_sword_hitbox(player)
	-- ATTACK_2 shows sword on frame 2 (index 1), others on frame 3 (index 2)
	local min_frame = player.attack_state.next_anim_ix == 1 and 1 or 2
	local max_frame = player.animation.definition.frame_count - 2

	if player.animation.frame < min_frame or player.animation.frame > max_frame then
		return nil
	end

	return {
		x = player.direction == 1
			and player.x + player.box.x + player.box.w
			or player.x + player.box.x - SWORD_WIDTH,
		y = player.y + player.box.y,
		w = SWORD_WIDTH,
		h = player.box.h
	}
end

local function check_attack_hits(player)
	local sword = get_sword_hitbox(player)
	if not sword then return end

	for enemy, _ in pairs(Enemy.all) do
		if not player.attack_state.hit_enemies[enemy] then
			local ex = enemy.x + enemy.box.x
			local ey = enemy.y + enemy.box.y
			local ew = enemy.box.w
			local eh = enemy.box.h

			if sword.x < ex + ew and sword.x + sword.w > ex and
			   sword.y < ey + eh and sword.y + sword.h > ey then
				enemy:on_hit("weapon", { damage = player.weapon_damage, x = player.x })
				player.attack_state.hit_enemies[enemy] = true
			end
		end
	end
end

local function next_animation(player)
	local animation = attack_animations[player.attack_state.next_anim_ix]
	player.animation = Animation.new(animation)
	player.attack_state.remaining_time = (animation.frame_count * animation.ms_per_frame) / 1000
	audio.play_sword_sound()
	player.attack_state.queued = false
	player.attack_state.hit_enemies = {}
	player.attack_state.next_anim_ix = player.attack_state.next_anim_ix + 1
	if player.attack_state.next_anim_ix > #attack_animations then
		player.attack_state.next_anim_ix = 1
	end
end

function attack.start(player)
    player.attack_state.count = 1
    player.attack_state.next_anim_ix = 1
    player.attack_state.queued_jump = false
    next_animation(player)
end

local function can_cancel(player)
	local on_last_frame = player.animation.frame >= player.animation.definition.frame_count - 1
	local in_hold_time = player.attack_state.remaining_time <= 0
	return on_last_frame or in_hold_time
end

function attack.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if controls.attack_pressed() then
		player.attack_state.queued = true
		player.attack_state.queued_jump = false
	end
	if controls.jump_pressed() then
		player.attack_state.queued_jump = true
	end

	if can_cancel(player) then
		local combo_available = player.attack_state.queued and player.attacks > player.attack_state.count
		if not combo_available and player.attack_state.queued_jump and player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.air)
			return
		end
		if not combo_available and (controls.left_down() or controls.right_down()) then
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.run)
			return
		end
	end
end


function attack.update(player, dt)
	check_attack_hits(player)
	player.vx = 0
	player.vy = 0
	player.attack_state.remaining_time = player.attack_state.remaining_time - dt
	if player.attack_state.remaining_time <= 0 then
		if player.attack_state.queued and player.attacks > player.attack_state.count then
			player.attack_state.count = player.attack_state.count + 1
			next_animation(player)
		elseif player.attack_state.remaining_time <= -HOLD_TIME then
			-- Hold time expired, transition back to idle
			player:set_state(player.states.idle)
			player.attack_cooldown = ATTACK_COOLDOWN
		end
		-- else: animation finished but still in hold period, waiting for combo input
	end
end


function attack.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)

	local sword = get_sword_hitbox(player)
	if config.bounding_boxes and sword then
		canvas.set_color("#FF00FF")
		canvas.draw_rect(
			sword.x * sprites.tile_size,
			sword.y * sprites.tile_size,
			sword.w * sprites.tile_size,
			sword.h * sprites.tile_size)
	end
end

return attack
