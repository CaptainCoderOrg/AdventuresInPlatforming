local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')
local combat = require('combat')
local config = require('config')
local canvas = require('canvas')


--- Attack state: Player performs melee combo attacks.
--- Supports 3-hit combo chain with input queueing for smooth chaining.
local attack = { name = "attack" }

local ATTACK_COOLDOWN = 0.2
local HOLD_TIME = 0.16

local attack_animations = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 }

-- Sword hitbox dimensions (centered relative to player box)
local SWORD_WIDTH = 1.15
local SWORD_HEIGHT = 1.1
local SWORD_Y_OFFSET = -0.1  -- Center vertically relative to player box

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

local function check_attack_hits(player)
	local sword = get_sword_hitbox(player)
	if not sword then return end

	-- Query combat system for enemies overlapping sword hitbox
	local hits = combat.query_rect(sword.x, sword.y, sword.w, sword.h, function(entity)
		-- Only hit enemies we haven't already hit this swing
		return entity.is_enemy
			and entity.shape  -- Has physics shape (not dead/dying)
			and not player.attack_state.hit_enemies[entity]
	end)

	for _, enemy in ipairs(hits) do
		enemy:on_hit("weapon", { damage = player.weapon_damage, x = player.x })
		player.attack_state.hit_enemies[enemy] = true
	end
end

local function next_animation(player)
	local animation = attack_animations[player.attack_state.next_anim_ix]
	player.animation = Animation.new(animation)
	player.attack_state.remaining_time = (animation.frame_count * animation.ms_per_frame) / 1000
	audio.play_sword_sound()
	player.attack_state.queued = false
	-- Clear existing table instead of allocating new one
	local hit_enemies = player.attack_state.hit_enemies
	for k in pairs(hit_enemies) do hit_enemies[k] = nil end
	player.attack_state.next_anim_ix = player.attack_state.next_anim_ix + 1
	if player.attack_state.next_anim_ix > #attack_animations then
		player.attack_state.next_anim_ix = 1
	end
end

--- Called when entering attack state. Initializes combo and clears input queue.
---@param player table The player object
function attack.start(player)
    player.attack_state.count = 1
    player.attack_state.next_anim_ix = 1
    common.clear_input_queue(player)
    next_animation(player)
end

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
	check_attack_hits(player)
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
