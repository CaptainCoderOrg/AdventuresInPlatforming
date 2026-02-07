local Animation = require('Animation')
local audio = require('audio')
local combat = require('combat')
local common = require('player.common')
local controls = require('controls')
local Effects = require('Effects')
local prop_common = require('Prop.common')
local shield = require('player.shield')
local weapon_sync = require('player.weapon_sync')
local upgrade_effects = require('upgrade/effects')


--- Attack state: Player performs melee combo attacks.
--- Supports unlimited combo chain (stamina-limited) with input queueing for smooth chaining.
--- Animation pattern: 1 → 2 → 3 → 2 → 3 → 2 → 3...
local attack = { name = "attack" }

local ATTACK_COOLDOWN = 0.2
local HOLD_TIME = 0.16
local SHIELD_KNOCKBACK = 3  -- Slight knockback when hitting enemy shield

-- Animation sets by weapon type
local animation_sets = {
	default = { common.animations.ATTACK_0, common.animations.ATTACK_1, common.animations.ATTACK_2 },
	short = { common.animations.ATTACK_SHORT_0, common.animations.ATTACK_SHORT_1, common.animations.ATTACK_SHORT_2 },
	wide = { common.animations.ATTACK_WIDE_0, common.animations.ATTACK_WIDE_1, common.animations.ATTACK_WIDE_2 },
}

--- Returns the attack animation set for the given weapon stats.
---@param stats table|nil Weapon stats (may be nil)
---@return table Array of animation definitions
local function get_attack_animations(stats)
	local variant = stats and stats.animation
	return animation_sets[variant] or animation_sets.default
end

-- Default hitbox dimensions (used if weapon has no hitbox stats)
local DEFAULT_WIDTH = 1.15
local DEFAULT_HEIGHT = 1.3
local DEFAULT_Y_OFFSET = -0.2

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

--- Returns the weapon hitbox for the current attack frame, or nil if not active.
--- Hitbox is only active during frames 2 to (frame_count - 2) to match visual weapon position.
---@param player table The player object
---@param stats table|nil Pre-fetched weapon stats (avoids redundant lookup)
---@return table|nil Hitbox {x, y, w, h} in tiles, or nil if weapon not active
local function get_weapon_hitbox(player, stats)
	local min_frame = 1
	local max_frame = player.animation.definition.frame_count - 1

	if player.animation.frame < min_frame or player.animation.frame > max_frame then
		return nil
	end

	local weapon_hitbox = stats and stats.hitbox
	local width = (weapon_hitbox and weapon_hitbox.width) or DEFAULT_WIDTH
	local height = (weapon_hitbox and weapon_hitbox.height) or DEFAULT_HEIGHT
	local y_offset = (weapon_hitbox and weapon_hitbox.y_offset) or DEFAULT_Y_OFFSET

	return common.create_melee_hitbox(player, width, height, y_offset)
end

--- Checks for enemies overlapping the weapon hitbox and applies damage.
--- Tracks hit enemies to prevent multi-hit within a single swing.
--- Blocked by enemy shields (plays solid sound, no damage, slight knockback).
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@param stats table|nil Pre-fetched weapon stats
local function check_attack_hits(player, hitbox, stats)
	local blocked_by, shield_x, shield_y = combat.check_shield_block(hitbox.x, hitbox.y, hitbox.w, hitbox.h)
	if blocked_by then
		if not player.attack_state.hit_shield then
			audio.play_solid_sound()
			Effects.create_hit(shield_x - 0.5, shield_y - 0.5, player.direction)
			blocked_by.vx = player.direction * SHIELD_KNOCKBACK
			player.attack_state.hit_shield = true
		end
		return
	end

	local base_damage = stats and stats.damage or 1
	local damage = upgrade_effects.get_weapon_damage(player, player.active_weapon, base_damage)
	filter_player = player
	local hits = combat.query_rect(hitbox.x, hitbox.y, hitbox.w, hitbox.h, enemy_filter)
	local crit_threshold = player:critical_percent()

	for i = 1, #hits do
		local enemy = hits[i]
		local is_crit = math.random() * 100 < crit_threshold
		attack_hit_source.damage = damage
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
---@param stats table|nil Pre-fetched weapon stats
local function next_animation(player, stats)
	local attack_animations = get_attack_animations(stats)
	local animation = attack_animations[player.attack_state.next_anim_ix]
	local override_ms = stats and stats.ms_per_frame
	player.animation = Animation.new(animation, { ms_per_frame = override_ms })
	-- Use override for remaining_time calculation
	local effective_ms = override_ms or animation.ms_per_frame
	player.attack_state.remaining_time = (animation.frame_count * effective_ms) / 1000
	audio.play_sword_sound()
	player.attack_state.queued = false
	-- Clear existing table instead of allocating new one
	local hit_enemies = player.attack_state.hit_enemies
	for k in pairs(hit_enemies) do hit_enemies[k] = nil end
	player.attack_state.hit_lever = false
	player.attack_state.hit_shield = false
	player.attack_state.next_anim_ix = player.attack_state.next_anim_ix + 1
	if player.attack_state.next_anim_ix > #attack_animations then
		-- Loop back to 2nd animation after 3rd (pattern: 1, 2, 3, 2, 3, 2, 3...)
		player.attack_state.next_anim_ix = 2
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
	local stats = weapon_sync.get_weapon_stats(player)
	next_animation(player, stats)
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
	if controls.ability_pressed() then
		common.queue_input(player, "throw")
	end

	if can_cancel(player) then
		local combo_queued = player.attack_state.queued
		if not combo_queued and player.input_queue.jump and player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player.attack_cooldown = ATTACK_COOLDOWN
			player:set_state(player.states.air)
			return
		end
		-- Check projectile, unlock, charges, energy and stamina inline since we're bypassing handle_throw for queued input
		if not combo_queued and player.input_queue.throw and player.projectile and player:is_projectile_unlocked(player.projectile)
		   and weapon_sync.has_throw_charges(player) and player.energy_used < player.max_energy then
			local throw_stamina = player.projectile.stamina_cost or 0
			if throw_stamina == 0 or player:use_stamina(throw_stamina) then
				player.attack_cooldown = ATTACK_COOLDOWN
				player:set_state(player.states.throw)
				return
			end
		end
		if not combo_queued and (controls.left_down() or controls.right_down()) then
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
	-- Fetch stats once per frame and cache for draw()
	local stats = weapon_sync.get_weapon_stats(player)
	player.attack_state.cached_stats = stats
	local hitbox = get_weapon_hitbox(player, stats)
	player.attack_state.cached_hitbox = hitbox
	if hitbox then
		check_attack_hits(player, hitbox, stats)
		check_lever_hits(player, hitbox)
	end
	-- Lock player in place during attack animation (no movement, no gravity)
	player.vx = 0
	player.vy = 0
	player.attack_state.remaining_time = player.attack_state.remaining_time - dt
	if player.attack_state.remaining_time <= 0 then
		local stamina_cost = stats and stats.stamina_cost or common.ATTACK_STAMINA_COST
		if player.attack_state.queued and player:use_stamina(stamina_cost) then
			player.attack_state.count = player.attack_state.count + 1
			next_animation(player, stats)
		elseif player.attack_state.remaining_time <= -HOLD_TIME then
			player:set_state(player.states.idle)
			player.attack_cooldown = ATTACK_COOLDOWN
		end
	end
end

--- Renders the player in attack animation with optional debug hitbox.
--- Wide animations (40px) need X offset to center properly.
---@param player table The player object
function attack.draw(player)
	local stats = player.attack_state.cached_stats
	local x_offset = 0
	if stats and stats.animation == "wide" and player.direction == -1 then
		x_offset = -0.5  -- 8px left when facing left
	end
	common.draw(player, nil, x_offset)
	common.draw_debug_hitbox(player.attack_state.cached_hitbox, "#FF00FF")
end

return attack
