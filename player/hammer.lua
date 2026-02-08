local Animation = require('Animation')
local audio = require('audio')
local combat = require('combat')
local common = require('player.common')
local Effects = require('Effects')
local prop_common = require('Prop.common')
local Prop = require('Prop')
local shield = require('player.shield')
local upgrade_effects = require('upgrade.effects')
local unique_item_registry = require('Prop.unique_item_registry')

--- Hammer state: Player performs a heavy overhead attack.
--- High damage, hits buttons, but consumes full stamina bar.
local hammer = { name = "hammer" }

-- Stats read from registry (hammer is a secondary, not a weapon)
local HAMMER_STATS = unique_item_registry.hammer.stats

-- Default hitbox dimensions (used if weapon has no hitbox stats)
local DEFAULT_WIDTH = 1.15
local DEFAULT_HEIGHT = 1.3
local DEFAULT_Y_OFFSET = -0.2

-- Default active frames for hammer hitbox (impact frames)
-- Hammer has 7 frames (0-6) at 150ms each
-- Frames 3-4 = impact window (300ms active window)
local DEFAULT_MIN_ACTIVE_FRAME = 3
local DEFAULT_MAX_ACTIVE_FRAME = 4

local SHIELD_KNOCKBACK = 5  -- Stronger knockback for hammer hitting shield

-- Reusable state for filters (avoids closure allocation per frame)
local filter_player = nil
local hammer_hit_source = { damage = 5, x = 0, is_crit = false }
local _query_results = {}  -- Reusable output table for combat.query_rect

--- Filter function for enemy hits (uses module-level state to avoid closure allocation)
---@param entity table Entity to check
---@return boolean True if entity is a valid target
local function enemy_filter(entity)
	return entity.is_enemy
		and entity.shape
		and not filter_player.hammer_state.hit_enemies[entity]
end

--- Filter function for button hits (avoids closure allocation)
---@param prop table Prop to check
---@return boolean True if button is not pressed
local function button_filter(prop)
	return not prop.is_pressed
end

--- Get the weapon hitbox if on active frames, nil otherwise
---@param player table The player object
---@param stats table|nil Pre-fetched weapon stats (avoids redundant lookup)
---@return table|nil Hitbox with x, y, w, h in tile coordinates
local function get_hammer_hitbox(player, stats)
	local active_frames = stats and stats.active_frames
	local min_frame = active_frames and active_frames.min or DEFAULT_MIN_ACTIVE_FRAME
	local max_frame = active_frames and active_frames.max or DEFAULT_MAX_ACTIVE_FRAME

	if player.animation.frame < min_frame or player.animation.frame > max_frame then
		return nil
	end

	local hitbox = stats and stats.hitbox
	local width = hitbox and hitbox.width or DEFAULT_WIDTH
	local height = hitbox and hitbox.height or DEFAULT_HEIGHT
	local y_offset = hitbox and hitbox.y_offset or DEFAULT_Y_OFFSET

	return common.create_melee_hitbox(player, width, height, y_offset)
end

--- Check for enemy hits with the hammer
--- Blocked by enemy shields (plays solid sound, no damage, knockback).
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@param stats table|nil Pre-fetched weapon stats
local function check_hammer_hits(player, hitbox, stats)
	local blocked_by, shield_x, shield_y = combat.check_shield_block(hitbox.x, hitbox.y, hitbox.w, hitbox.h)
	if blocked_by then
		if not player.hammer_state.hit_shield then
			audio.play_solid_sound()
			Effects.create_hit(shield_x - 0.5, shield_y - 0.5, player.direction)
			blocked_by.vx = player.direction * SHIELD_KNOCKBACK
			player.hammer_state.hit_shield = true
		end
		return
	end

	local damage = upgrade_effects.get_weapon_damage(player, "hammer", stats and stats.damage or 5)
	filter_player = player
	local hits = combat.query_rect(hitbox.x, hitbox.y, hitbox.w, hitbox.h, enemy_filter, _query_results)
	local crit_threshold = player:critical_percent()

	for i = 1, #hits do
		local enemy = hits[i]
		local is_crit = math.random() * 100 < crit_threshold
		hammer_hit_source.damage = damage
		hammer_hit_source.x = player.x
		hammer_hit_source.is_crit = is_crit
		enemy:on_hit("weapon", hammer_hit_source)
		player.hammer_state.hit_enemies[enemy] = true
	end
end

--- Check for button hits with the hammer (only if weapon allows it)
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@param stats table|nil Pre-fetched weapon stats
local function check_button_hits(player, hitbox, stats)
	if player.hammer_state.hit_button then return end
	if not stats or not stats.can_hit_buttons then return end

	local button = Prop.check_hit("button", hitbox, button_filter)
	if button then
		button.definition.press(button)
		player.hammer_state.hit_button = true
	end
end

--- Check for lever hits with the hammer
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
local function check_lever_hits(player, hitbox)
	if player.hammer_state.hit_lever then return end
	if prop_common.check_lever_hit(hitbox) then
		player.hammer_state.hit_lever = true
	end
end

--- Initializes hammer attack state. Sets animation, timing, and clears input queue.
--- Removes shield if transitioning from block/block_move state.
---@param player table The player object
function hammer.start(player)
	shield.remove(player)
	local speed = upgrade_effects.get_attack_speed(player, "hammer", common.animations.HAMMER.ms_per_frame)
	player.animation = Animation.new(common.animations.HAMMER, { ms_per_frame = speed })
	player.hammer_state.remaining_time = (common.animations.HAMMER.frame_count * speed) / 1000
	player.hammer_state.hit_button = false
	player.hammer_state.hit_lever = false
	player.hammer_state.hit_shield = false
	-- Clear existing table instead of allocating new one
	local hit_enemies = player.hammer_state.hit_enemies
	for k in pairs(hit_enemies) do hit_enemies[k] = nil end
	player.hammer_state.sound_played = false
	common.clear_input_queue(player)
	audio.play_hammer_grunt()
end

--- Updates hammer state. Checks for button hits, locks movement, and handles timing.
---@param player table The player object
---@param dt number Delta time in seconds
function hammer.update(player, dt)
	local hitbox = get_hammer_hitbox(player, HAMMER_STATS)
	player.hammer_state.cached_hitbox = hitbox
	if hitbox then
		check_hammer_hits(player, hitbox, HAMMER_STATS)
		check_button_hits(player, hitbox, HAMMER_STATS)
		check_lever_hits(player, hitbox)
	end
	player.vx = 0
	player.vy = 0
	player.hammer_state.remaining_time = player.hammer_state.remaining_time - dt
	if player.animation.frame >= 3 and not player.hammer_state.sound_played then
		audio.play_hammer_hit()
		player.hammer_state.sound_played = true
	end
	if player.hammer_state.remaining_time < 0 then
		if not common.process_input_queue(player) then
			player:set_state(player.states.idle)
		end
	end
end

--- Handles input during hammer state. Queues inputs for later execution.
---@param player table The player object
function hammer.input(player)
	common.queue_inputs(player)
end

--- Renders the player in hammer animation with optional debug hitbox.
---@param player table The player object
function hammer.draw(player)
	common.draw(player)
	common.draw_debug_hitbox(player.hammer_state.cached_hitbox, "#FF00FF")
end

return hammer
