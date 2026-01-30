local Animation = require('Animation')
local audio = require('audio')
local combat = require('combat')
local common = require('player.common')
local controls = require('controls')
local Effects = require('Effects')
local prop_common = require('Prop.common')
local shield = require('player.shield')


--- Attack state: Player performs melee combo attacks.
--- Supports 3-hit combo chain with input queueing for smooth chaining.
local attack = { name = "attack" }

local ATTACK_COOLDOWN = 0.2
local HOLD_TIME = 0.16
local SHIELD_KNOCKBACK = 3  -- Slight knockback when hitting enemy shield

local attack_animations = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 }

-- Sword hitbox dimensions (centered relative to player box)
local SWORD_WIDTH = 1.15
local SWORD_HEIGHT = 1.1
local SWORD_Y_OFFSET = -0.1  -- Center vertically relative to player box

-- Reusable state for filters (avoids closure allocation per frame)
local filter_player = nil
local attack_hit_source = { damage = 0, x = 0, is_crit = false }

--- Filter function for enemy hits (uses module-level state to avoid closure allocation)
---@param entity table Entity to check
---@return boolean True if entity is a valid target
local function enemy_filter(entity)
	return entity.is_enemy
		and entity.shape
		and not filter_player.attack_state.hit_enemies[entity]
end

--- Returns the sword hitbox for the current attack frame, or nil if not active.
--- Hitbox is only active during specific animation frames to match visual sword position.
---@param player table The player object
---@return table|nil Hitbox {x, y, w, h} in tiles, or nil if sword not active
local function get_sword_hitbox(player)
	-- next_anim_ix points to NEXT animation (incremented in next_animation()).
	-- When == 1, we just played ATTACK_2 (wrapped from 3->1), which shows sword on frame 2.
	-- ATTACK_0/1 show sword on frame 3.
	local min_frame = player.attack_state.next_anim_ix == 1 and 1 or 2
	local max_frame = player.animation.definition.frame_count - 2

	if player.animation.frame < min_frame or player.animation.frame > max_frame then
		return nil
	end
	return common.create_melee_hitbox(player, SWORD_WIDTH, SWORD_HEIGHT, SWORD_Y_OFFSET)
end

--- Checks for enemies overlapping the sword hitbox and applies damage.
--- Tracks hit enemies to prevent multi-hit within a single swing.
--- Blocked by enemy shields (plays solid sound, no damage, slight knockback).
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
local function check_attack_hits(player, hitbox)
	-- Check if blocked by enemy shield
	local blocked_by, shield_x, shield_y = combat.check_shield_block(hitbox.x, hitbox.y, hitbox.w, hitbox.h)
	if blocked_by then
		if not player.attack_state.hit_shield then
			audio.play_solid_sound()
			Effects.create_hit(shield_x - 0.5, shield_y - 0.5, player.direction)
			-- Slight knockback away from player
			blocked_by.vx = player.direction * SHIELD_KNOCKBACK
			player.attack_state.hit_shield = true
		end
		return  -- Always return when blocked
	end

	-- Query combat system for enemies overlapping sword hitbox
	filter_player = player
	local hits = combat.query_rect(hitbox.x, hitbox.y, hitbox.w, hitbox.h, enemy_filter)
	local crit_threshold = player:critical_percent()

	for i = 1, #hits do
		local enemy = hits[i]
		-- Roll for critical hit (multiplier applied after armor by enemy)
		local is_crit = math.random() * 100 < crit_threshold
		attack_hit_source.damage = player.weapon_damage
		attack_hit_source.x = player.x
		attack_hit_source.is_crit = is_crit
		enemy:on_hit("weapon", attack_hit_source)
		player.attack_state.hit_enemies[enemy] = true
	end
end

--- Checks for levers overlapping the sword hitbox and toggles them.
--- Only allows one lever hit per swing.
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
local function check_lever_hits(player, hitbox)
	if player.attack_state.hit_lever then return end
	if prop_common.check_lever_hit(hitbox) then
		player.attack_state.hit_lever = true
	end
end

--- Advances to the next attack animation in the combo chain.
--- Resets hit tracking, plays sword sound, and wraps to first animation after final.
---@param player table The player object
local function next_animation(player)
	local animation = attack_animations[player.attack_state.next_anim_ix]
	player.animation = Animation.new(animation)
	player.attack_state.remaining_time = (animation.frame_count * animation.ms_per_frame) / 1000
	audio.play_sword_sound()
	player.attack_state.queued = false
	-- Clear existing table instead of allocating new one
	local hit_enemies = player.attack_state.hit_enemies
	for k in pairs(hit_enemies) do hit_enemies[k] = nil end
	player.attack_state.hit_lever = false
	player.attack_state.hit_shield = false
	player.attack_state.next_anim_ix = player.attack_state.next_anim_ix + 1
	if player.attack_state.next_anim_ix > #attack_animations then
		player.attack_state.next_anim_ix = 1
	end
end

--- Called when entering attack state. Initializes combo and clears input queue.
--- Removes shield if transitioning from block/block_move state.
---@param player table The player object
function attack.start(player)
    shield.remove(player)
    player.attack_state.count = 1
    player.attack_state.next_anim_ix = 1
    common.clear_input_queue(player)
    next_animation(player)
end

--- Returns whether the attack can be canceled into another action.
--- Allows canceling on last frame or during post-animation hold window.
---@param player table The player object
---@return boolean True if attack can be canceled
local function can_cancel(player)
	local on_last_frame = player.animation.frame >= player.animation.definition.frame_count - 1
	local in_hold_time = player.attack_state.remaining_time <= 0
	return on_last_frame or in_hold_time
end

--- Handles input during attack. Queues combo continuation, jump, or throw.
--- Allows direction change and early state cancels during hold window.
---@param player table The player object
function attack.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if controls.attack_pressed() then
		player.attack_state.queued = true
		-- Clear jump/throw queues when combo is queued (combo takes priority)
		player.input_queue.jump = false
		player.input_queue.throw = false
	end
	if controls.jump_pressed() then
		common.queue_input(player, "jump")
	end
	if controls.throw_pressed() then
		common.queue_input(player, "throw")
	end

	if can_cancel(player) then
		local combo_available = player.attack_state.queued and player.attacks > player.attack_state.count
		if not combo_available and player.input_queue.jump and player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.air)
			return
		end
		-- Check energy inline since we're bypassing handle_throw for queued input
		if not combo_available and player.input_queue.throw and player.energy_used < player.max_energy then
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.throw)
			return
		end
		if not combo_available and (controls.left_down() or controls.right_down()) then
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.run)
			return
		end
	end
end

--- Updates attack state. Checks for hits, advances combo, and handles timing.
--- Transitions to idle after hold window expires if no combo queued.
---@param player table The player object
---@param dt number Delta time in seconds
function attack.update(player, dt)
	-- Compute hitbox once and pass to all check functions
	local hitbox = get_sword_hitbox(player)
	if hitbox then
		check_attack_hits(player, hitbox)
		check_lever_hits(player, hitbox)
	end
	-- Lock player in place during attack animation (no movement, no gravity)
	player.vx = 0
	player.vy = 0
	player.attack_state.remaining_time = player.attack_state.remaining_time - dt
	if player.attack_state.remaining_time <= 0 then
		local can_combo = player.attack_state.queued and player.attacks > player.attack_state.count
		if can_combo and player:use_stamina(common.ATTACK_STAMINA_COST) then
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

--- Renders the player in attack animation with optional debug hitbox.
---@param player table The player object
function attack.draw(player)
	common.draw(player)
	common.draw_debug_hitbox(get_sword_hitbox(player), "#FF00FF")
end

return attack
