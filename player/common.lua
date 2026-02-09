local Animation = require('Animation')
local audio = require('audio')
local canvas = require('canvas')
local combat = require('combat')
local config = require('config')
local controls = require('controls')
local Effects = require('Effects')
local Prop = require('Prop')
local sprites = require('sprites')
local weapon_sync = require('player.weapon_sync')
local upgrade_effects = require('upgrade/effects')
local unique_item_registry = require('Prop.unique_item_registry')

local common = {}

-- Reusable tables to avoid per-frame allocations
local _melee_hitbox = { x = 0, y = 0, w = 0, h = 0 }
local _ground_tangent = { x = 0, y = 0 }
local _map_transition_target = { map = nil, spawn_id = nil }

-- Lazy-loaded to avoid circular dependency (shield requires Animation, common loaded early)
local shield

common.GRAVITY = 1.5
common.JUMP_VELOCITY = common.GRAVITY * 14
common.AIR_JUMP_VELOCITY = common.GRAVITY * 11
common.MAX_COYOTE_TIME = 6 / 60
common.MAX_FALL_SPEED = 20

-- Stamina costs (balanced against max_stamina=3)
-- Attack costs 2: allows 1 full attack before fatigue risk
common.ATTACK_STAMINA_COST = 2
-- Air jump costs 1: double jump only, ground jump stays free
common.AIR_JUMP_STAMINA_COST = 1
-- Dash costs 4: high cost for powerful escape/engage
common.DASH_STAMINA_COST = 4
-- Wall jump costs 1: matches air jump cost
common.WALL_JUMP_STAMINA_COST = 1
-- Fixed fatigue duration in seconds (normal regen continues during fatigue)
common.FATIGUE_DURATION = 1.5
-- Block move speed: 35% of normal speed for slow defensive movement
common.BLOCK_MOVE_SPEED_MULTIPLIER = 0.35

-- Animations (converted to delta-time based, milliseconds per frame)
common.animations = {
	IDLE = Animation.create_definition(sprites.player.idle, 6, { ms_per_frame = 240 }),
	BLOCK = Animation.create_definition(sprites.player.block, 1, { ms_per_frame = 17, loop = false }),
	BLOCK_MOVE = Animation.create_definition(sprites.player.block_step, 4, { ms_per_frame = 160 }),
	RUN = Animation.create_definition(sprites.player.run, 8 ),
	TURN = Animation.create_definition(sprites.player.turn, 4, { loop = false }),
	DASH = Animation.create_definition(sprites.player.dash, 4, { loop = false }),
	FALL = Animation.create_definition(sprites.player.fall, 3 ),
	JUMP = Animation.create_definition(sprites.player.jump_up, 3, { loop = false }),
	AIR_JUMP = Animation.create_definition(sprites.player.double_jump, 4 ),
	WALL_SLIDE = Animation.create_definition(sprites.player.wall_slide, 3, { loop = false }),

	CLIMB_UP = Animation.create_definition(sprites.player.climb_up, 6),
	CLIMB_DOWN = Animation.create_definition(sprites.player.climb_down, 6),

	ATTACK_0 = Animation.create_definition(sprites.player.attack_0, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_1 = Animation.create_definition(sprites.player.attack_1, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_2 = Animation.create_definition(sprites.player.attack_2, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_SHORT_0 = Animation.create_definition(sprites.player.attack_short_0, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_SHORT_1 = Animation.create_definition(sprites.player.attack_short_1, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_SHORT_2 = Animation.create_definition(sprites.player.attack_short_2, 5, { ms_per_frame = 60, width = 32, loop = false }),
	ATTACK_WIDE_0 = Animation.create_definition(sprites.player.attack_wide_0, 5, { ms_per_frame = 60, width = 40, loop = false }),
	ATTACK_WIDE_1 = Animation.create_definition(sprites.player.attack_wide_1, 5, { ms_per_frame = 60, width = 40, loop = false }),
	ATTACK_WIDE_2 = Animation.create_definition(sprites.player.attack_wide_2, 5, { ms_per_frame = 60, width = 40, loop = false }),
	HAMMER = Animation.create_definition(sprites.player.attack_hammer, 7, { ms_per_frame = 150, width = 32, loop = false }),
	THROW = Animation.create_definition(sprites.player.throw, 7, { ms_per_frame = 33, loop = false }),

	HIT = Animation.create_definition(sprites.player.hit, 3, { ms_per_frame = 80, loop = false }),
	DEATH = Animation.create_definition(sprites.player.death, 12, { ms_per_frame = 80, loop = false }),
	REST = Animation.create_definition(sprites.player.rest, 1, { ms_per_frame = 1000, loop = false }),
}

--- Attempts to consume throw stamina cost from the given projectile spec.
--- Returns true if no cost required or if stamina was successfully consumed.
---@param player table The player object
---@param spec table The projectile spec
---@return boolean True if throw is allowed (no cost or stamina consumed)
function common.try_use_throw_stamina(player, spec)
	local stamina_cost = spec.stamina_cost or 0
	return stamina_cost == 0 or player:use_stamina(stamina_cost)
end

--- Checks if the player has enough energy for the given projectile's energy cost.
---@param player table The player object
---@param spec table The projectile spec
---@param sec_id string|nil Secondary item ID for upgrade lookup
---@return boolean True if player has sufficient energy to throw
function common.has_throw_energy(player, spec, sec_id)
	local base_cost = spec.energy_cost or 1
	local energy_cost = sec_id and upgrade_effects.get_energy_cost(player, sec_id, base_cost) or base_cost
	return player.energy_used + energy_cost <= player.max_energy
end

--- Attempts to activate the hammer from an ability slot.
--- Checks unlock status and consumes stamina (with upgrade modifiers).
---@param player table The player object
---@param slot number Ability slot (1-6) containing the hammer
---@return boolean True if activation succeeded (unlocked and stamina consumed)
function common.try_use_hammer(player, slot)
	if not weapon_sync.is_secondary_unlocked(player, slot) then return false end
	local cost = upgrade_effects.get_stamina_cost(player, "hammer", unique_item_registry.hammer.stats.stamina_cost)
	return player:use_stamina(cost)
end

-- Footstep timing: two footsteps per run animation cycle
local FOOTSTEP_COOLDOWN_TIME = nil  -- Computed lazily after animations are defined

--- Updates footstep sound timing. Call each frame while the player is walking/running.
--- Plays footstep sounds synchronized with the run animation.
---@param player table The player object
---@param dt number Delta time in seconds
function common.update_footsteps(player, dt)
	-- Lazy init cooldown time (animations must be defined first)
	if not FOOTSTEP_COOLDOWN_TIME then
		FOOTSTEP_COOLDOWN_TIME = (common.animations.RUN.frame_count * common.animations.RUN.ms_per_frame) / 2000
	end

	if player.footstep_cooldown <= 0 then
		audio.play_footstep()
		player.footstep_cooldown = FOOTSTEP_COOLDOWN_TIME
	else
		player.footstep_cooldown = player.footstep_cooldown - dt
	end
end

--- Resets the footstep cooldown timer. Call when entering a walking/running state.
---@param player table The player object
function common.reset_footsteps(player)
	player.footstep_cooldown = 0
end

--- Checks for weapon swap input and cycles to the next equipped weapon.
--- Shows weapon name text and plays swap sound on successful swap.
---@param player table The player object
function common.handle_weapon_swap(player)
	if not controls.swap_weapon_pressed() then return end
	local weapon_name = weapon_sync.cycle_weapon(player)
	if weapon_name then
		audio.play_swap_sound()
		Effects.create_text(player.x, player.y, weapon_name)
	end
end

--- Checks for ability input and transitions to throw/hammer state or queues if on cooldown.
--- Routes melee secondaries (hammer) directly, queries weapon_sync for projectile specs.
--- Dash and shield are handled by their dedicated handlers (handle_dash/handle_block).
--- Non-projectile secondaries (e.g., minor_healing) return nil spec and are skipped here.
---@param player table The player object
function common.handle_ability(player)
	local slot = controls.any_ability_pressed()
	if not slot then return end

	local sec_id = weapon_sync.get_slot_secondary(player, slot)

	-- Dash and shield are handled by dedicated handlers, not here
	if sec_id == "dash_amulet" or sec_id == "shield" or sec_id == "adepts_shield" then return end

	-- Melee secondary (hammer): consumes stamina, enters hammer state
	if sec_id == "hammer" then
		if common.try_use_hammer(player, slot) then
			shield = shield or require('player.shield')
			shield.clear_perfect_window(player)
			player.active_ability_slot = slot
			player:set_state(player.states.hammer)
		end
		return
	end

	-- Get projectile spec from the pressed slot (nil for non-projectile abilities)
	local spec = weapon_sync.get_secondary_spec(player, slot)
	if not spec then return end
	if not weapon_sync.is_secondary_unlocked(player, slot) then return end

	-- Block ability when no charges available
	if not weapon_sync.has_throw_charges(player, slot) then
		Effects.create_text(player.x, player.y, "Cooldown")
		return
	end

	-- Block ability when insufficient energy (no cooldown queue needed)
	if not common.has_throw_energy(player, spec, sec_id) then
		local current_energy = player.max_energy - player.energy_used
		Effects.create_energy_text(player.x, player.y, current_energy)
		player.energy_flash_requested = true
		return
	end

	if player.throw_cooldown <= 0 then
		if common.try_use_throw_stamina(player, spec) then
			player.active_ability_slot = slot
			player:set_state(player.states.throw)
		end
	else
		common.queue_input(player, "ability", slot)
	end
end

--- Checks for attack input and transitions to attack state.
--- Shows "No Weapon" effect if no weapon equipped.
--- Invalidates perfect block window when attacking from block state.
---@param player table The player object
---@return boolean True if transitioned to attack state
function common.handle_attack(player)
	if not controls.attack_pressed() then return false end

	local stats = weapon_sync.get_weapon_stats(player)

	-- No weapon equipped
	if not stats then
		Effects.create_text(player.x, player.y, "No Weapon")
		return false
	end

	if player.attack_cooldown <= 0 then
		local stamina_cost = upgrade_effects.get_stamina_cost(player, player.active_weapon, stats.stamina_cost)
		if player:use_stamina(stamina_cost) then
			-- Invalidate perfect block window when attacking from block
			shield = shield or require('player.shield')
			shield.clear_perfect_window(player)
			player:set_state(player.states.attack)
			return true
		end
	else
		-- Queue attack during cooldown (stamina checked when queue is processed)
		common.queue_input(player, "attack")
	end
	return false
end

--- Checks for block input and transitions to block state if held.
--- Requires shield ability to be unlocked.
--- Requires positive stamina (cannot block while fatigued).
--- Shows "TIRED" text on first press when fatigued.
---@param player table The player object
function common.handle_block(player)
	if not player.shield_slot then return end
	local block_down = controls.ability_down(player.shield_slot)
	if block_down and not player:is_fatigued() then
		player:set_state(player.states.block)
	elseif block_down and player:is_fatigued() and not player.block_was_down then
		Effects.create_fatigue_text(player.x, player.y)
	end
	player.block_was_down = block_down
end

--- Checks for interact input (up) and handles prop interactions.
--- Tries all overlapping interactable entities until one succeeds.
---@param player table The player object
---@return boolean True if interaction occurred (prevents attack)
function common.handle_interact(player)
	if not controls.up_pressed() then
		return false
	end

	local hit = combat.query_rect(
		player.x + player.box.x,
		player.y + player.box.y,
		player.box.w,
		player.box.h
	)
	for i = 1, #hit do
		local entity = hit[i]
		local state = entity.states and entity.states[entity.state_name]
		local interact_fn = (state and state.interact) or (entity.definition and entity.definition.interact)
		if interact_fn then
			local result = interact_fn(entity, player)
			if result then
				if type(result) == "table" and result.player_state then
					player:set_state(player.states[result.player_state])
				end
				return true
			end
		end
	end
	return false
end

--- Applies gravity acceleration to the player without state transitions.
---@param player table The player object
---@param dt number Delta time in seconds
---@param max_speed number|nil Maximum fall speed (defaults to MAX_FALL_SPEED)
function common.apply_gravity(player, dt, max_speed)
	max_speed = max_speed or common.MAX_FALL_SPEED
	player.vy = math.min(max_speed, player.vy + common.GRAVITY * dt * 60)
end

--- Returns true if the player is in a state that prevents air transition.
---@param player table The player object
---@return boolean True if in a locked state
local function is_locked_state(player)
	local state = player.state
	return state == player.states.block
		or state == player.states.block_move
		or state == player.states.hit
		or state == player.states.throw
end

--- Applies gravity and transitions to air state if not grounded.
---@param player table The player object
---@param dt number Delta time in seconds
---@param max_speed number|nil Maximum fall speed (defaults to MAX_FALL_SPEED)
function common.handle_gravity(player, dt, max_speed)
	common.apply_gravity(player, dt, max_speed)
	if not player.is_grounded and not is_locked_state(player) then
		player:set_state(player.states.air)
	end
end

--- Checks for ladder climb entry conditions and transitions to climb state.
--- Entry points: standing on ladder top + down, grounded + up, in air + up (falling only).
---@param player table The player object
function common.handle_climb(player)
	-- Entry from top of ladder (down while standing on ladder top)
	if player.standing_on_ladder_top and player.is_grounded then
		if controls.down_down() then
			player:set_state(player.states.climb)
		end
		return  -- Don't allow up to enter climb from top
	end
	-- Entry from middle of ladder (up while overlapping ladder)
	-- Grounded + UP = start climbing from bottom
	-- In air + UP = grab ladder once falling (vy >= 0), not at top to prevent flicker
	local up_pressed_on_ground = controls.up_down() and player.is_grounded
	local up_pressed_in_air = controls.up_down() and not player.is_grounded and not player.on_ladder_top and player.vy >= 0
	if (up_pressed_on_ground or up_pressed_in_air) and player.can_climb then
		player:set_state(player.states.climb)
	end
end

--- Debug function to test hit state via Y key press.
--- Applies 1 damage to player if not invincible.
--- Also handles '8' key to grant 8000 experience for testing.
---@param player table The player object
---@param _cols table Collision results (unused, kept for interface consistency)
function common.check_hit(player, _cols)
    if config.DEV_MODE and canvas.is_key_pressed(canvas.keys.Y) and not player:is_invincible() then
        player:take_damage(1)
    end
    if config.DEV_MODE and canvas.is_key_pressed(canvas.keys.DIGIT_8) then
        player.experience = player.experience + 8000
    end
end

--- Updates ladder-related player flags based on trigger collisions.
--- Sets can_climb, current_ladder, on_ladder_top from overlapping ladder triggers.
---@param player table The player object
---@param cols table Collision results from world.move()
function common.check_ladder(player, cols)
	player.can_climb = false
	player.current_ladder = nil
	player.on_ladder_top = false
	local triggers = cols.triggers
	for i = 1, #triggers do
		local trigger = triggers[i]
		if trigger.owner.is_ladder then
			player.can_climb = true
			player.current_ladder = trigger.owner
			if trigger.owner.is_top then
				player.on_ladder_top = true
			end
		end
	end
	if not player.can_climb then
		player.is_climbing = false
	end
end

--- Updates map transition target based on trigger collisions.
--- Sets player.map_transition_target when overlapping a map transition zone.
--- Note: Returns a reused table - do not store the reference long-term.
---@param player table The player object
---@param cols table Collision results from world.move()
function common.check_map_transition(player, cols)
	local triggers = cols.triggers
	for i = 1, #triggers do
		local trigger = triggers[i]
		if trigger.owner.is_map_transition then
			_map_transition_target.map = trigger.owner.target_map
			_map_transition_target.spawn_id = trigger.owner.target_id
			player.map_transition_target = _map_transition_target
			return
		end
	end
end

-- Lazy-loaded triggers module to avoid circular dependency
local triggers_module

--- Checks event trigger collisions and fires registered handlers.
--- Call after movement to process trigger zone overlaps.
---@param player table The player object
---@param cols table Collision results from world.move()
function common.check_triggers(player, cols)
	triggers_module = triggers_module or require("triggers")
	triggers_module.check(cols, player)
end

--- Processes collision flags to update grounded state, wall contact, and coyote time.
--- Uses separated X/Y collision pass results from world.move().
---@param player table The player object
---@param cols table Collision flags {ground, ceiling, wall_left, wall_right}
---@param dt number Delta time
function common.check_ground(player, cols, dt)
	-- Ground detection from Y collision pass
	if cols.ground then
		if not player.is_climbing then
			-- Update recovery point when grounded (not climbing, to avoid ladder positions)
			player.last_safe_position.x = player.x
			player.last_safe_position.y = player.y
			player.is_grounded = true
			player.ground_normal = cols.ground_normal
			player.coyote_time = 0
			player.jumps = player.max_jumps
			player.vy = 0
			player.is_air_jumping = false
			player.climb_touching_ground = false  -- Clear when not climbing
			-- Track if standing on ladder top
			player.standing_on_ladder_top = cols.is_ladder_top or false
			-- Track if standing on bridge
			player.standing_on_bridge = cols.is_bridge or false
			-- Set ladder info when standing on ladder top (for entering climb from top)
			if cols.is_ladder_top and cols.ladder_from_top then
				player.current_ladder = cols.ladder_from_top
				player.can_climb = true
			end
		else
			-- Climbing but touching ground - store for climb state to check
			player.climb_touching_ground = true
		end
	else
		player.climb_touching_ground = false
		-- Check for ladder top even when ground collision was skipped (one-way platform)
		if cols.is_ladder_top and cols.ladder_from_top then
			player.standing_on_ladder_top = true
			player.current_ladder = cols.ladder_from_top
			player.can_climb = true
		else
			player.standing_on_ladder_top = false
		end
		-- Clear bridge flag when not grounded
		player.standing_on_bridge = false
		player.coyote_time = player.coyote_time + dt
		if player.is_grounded and player.coyote_time > common.MAX_COYOTE_TIME then
			player.is_grounded = false
			player.jumps = player.max_jumps - 1
		end
	end

	-- Ceiling detection
	if cols.ceiling then
		player.has_ceiling = true
		if cols.has_ceiling_normal then
			player.ceiling_normal.x = cols.ceiling_normal.x
			player.ceiling_normal.y = cols.ceiling_normal.y
		end
		if player.vy < 0 then
			player.vy = 0
		end
	else
		player.has_ceiling = false
	end

	-- Wall detection for wall slide/jump
	player.wall_direction = 0
	if cols.wall_left then player.wall_direction = 1 end
	if cols.wall_right then player.wall_direction = -1 end
end

--- Attempts a ground jump if the player is grounded and jump is pressed.
--- Suppresses jump when on bridge + holding down (to allow drop-through).
---@param player table The player object
---@return boolean True if jump was performed
function common.handle_jump(player)
	if controls.jump_pressed() and (player.is_grounded or player.is_climbing) then
		-- Suppress jump when on bridge + down to allow drop-through
		if player.standing_on_bridge and controls.down_down() then
			player.wants_drop_through = true
			-- Store the Y position of the bridge we're dropping through
			player.drop_through_y = player.y + player.box.y + player.box.h
			player.drop_through_timer = 0.5  -- 0.5 second fallback timer
			return false
		end
		player.vy = -common.JUMP_VELOCITY
		player.jumps = player.jumps - 1
		audio.play_jump_sound()
		return true
	end
	return false
end

--- Attempts an air jump if the player has remaining jumps, stamina, and jump is pressed.
--- Requires double jump ability to be unlocked (first jump is always available).
---@param player table The player object
---@return boolean True if air jump was performed
function common.handle_air_jump(player)
	if controls.jump_pressed() and player.jumps > 0 then
		-- Block double jump if ability not unlocked (only first air jump after coyote time allowed)
		if player.jumps < player.max_jumps and not player.has_double_jump then return false end
		if player:use_stamina(common.AIR_JUMP_STAMINA_COST) then
			player.vy = -common.AIR_JUMP_VELOCITY
			player.jumps = player.jumps - 1
			player.is_air_jumping = true
			audio.play_air_jump_sound()
			return true
		end
	end
	return false
end

--- Attempts to initiate a dash if charges available, has stamina, and dash key is pressed.
--- Requires dash_amulet assigned to an ability slot. Uses the charge system for cooldown.
---@param player table The player object
---@return boolean True if dash was initiated
function common.handle_dash(player)
	if not player.dash_slot then return false end
	if not controls.ability_pressed(player.dash_slot) then return false end
	if not weapon_sync.has_throw_charges(player, player.dash_slot) then
		Effects.create_text(player.x, player.y, "Cooldown")
		return false
	end
	if player:use_stamina(upgrade_effects.get_stamina_cost(player, "dash_amulet", common.DASH_STAMINA_COST)) then
		player.active_ability_slot = player.dash_slot
		player:set_state(player.states.dash)
		return true
	end
	return false
end

--- Checks if the player is pressing movement input toward a wall they're touching.
---@param player table The player object
---@return boolean True if pressing into wall
function common.is_pressing_into_wall(player)
	return (controls.left_down() and player.wall_direction == 1) or
	       (controls.right_down() and player.wall_direction == -1)
end

--- Returns the tangent vector of the ground the player is standing on.
--- Tangent points right along the surface.
--- Note: Returns a reused table - do not store the reference.
---@param player table The player object
---@return table Tangent vector {x, y}
function common.get_ground_tangent(player)
	-- Tangent perpendicular to normal, pointing right
	_ground_tangent.x = -player.ground_normal.y
	_ground_tangent.y = player.ground_normal.x
	return _ground_tangent
end

-- Input Queue System

--- Queues an input for later execution.
---@param player table The player object
---@param input_name string The input to queue ("jump", "attack", or "ability")
---@param slot number|nil Ability slot (1-6) when input_name is "ability"
function common.queue_input(player, input_name, slot)
	if input_name == "ability" then
		player.input_queue.ability_slot = slot
	else
		player.input_queue[input_name] = true
	end
end

--- Clears all queued inputs.
---@param player table The player object
function common.clear_input_queue(player)
	player.input_queue.jump = false
	player.input_queue.attack = false
	player.input_queue.ability_slot = nil
end

--- Transitions to a state, restarting if already in that state.
--- Note: The restart branch is defensive code for future-proofing; current usage
--- always transitions to a different state, but this handles same-state queueing.
---@param player table The player object
---@param state table The target state
local function transition_or_restart(player, state)
	if player.state == state then
		state.start(player)
	else
		player:set_state(state)
	end
end

--- Attempts to process queued attack or ability input.
--- Clears queue entry when cooldown ready, returns target state on successful stamina use.
---@param player table The player object
---@return table|nil Target state if action succeeded, nil otherwise
local function try_queued_combat_action(player)
	if player.input_queue.attack and player.attack_cooldown <= 0 then
		player.input_queue.attack = false
		local stats = weapon_sync.get_weapon_stats(player)
		if stats then
			local stamina_cost = upgrade_effects.get_stamina_cost(player, player.active_weapon, stats.stamina_cost)
			if player:use_stamina(stamina_cost) then
				return player.states.attack
			end
		end
	end
	local queued_slot = player.input_queue.ability_slot
	if queued_slot then
		player.input_queue.ability_slot = nil
		local sec_id = weapon_sync.get_slot_secondary(player, queued_slot)
		-- Dash and shield are handled by dedicated handlers, skip here
		if sec_id == "dash_amulet" or sec_id == "shield" or sec_id == "adepts_shield" then return nil end
		-- Melee secondary (hammer)
		if sec_id == "hammer" and common.try_use_hammer(player, queued_slot) then
			player.active_ability_slot = queued_slot
			return player.states.hammer
		end
		-- Projectile secondaries (require throw_cooldown)
		if player.throw_cooldown <= 0 then
			local spec = weapon_sync.get_secondary_spec(player, queued_slot)
			if spec and weapon_sync.is_secondary_unlocked(player, queued_slot)
			   and weapon_sync.has_throw_charges(player, queued_slot) and common.has_throw_energy(player, spec, sec_id) then
				if common.try_use_throw_stamina(player, spec) then
					player.active_ability_slot = queued_slot
					return player.states.throw
				end
			end
		end
	end
	return nil
end

--- Processes queued inputs with priority (attack > ability > jump).
--- Called when exiting locked states (throw, hammer, hit) to chain actions.
--- Respects cooldowns and resource costs. Queued actions are cleared once cooldown
--- is ready, regardless of stamina availability, to prevent infinite retry loops.
---@param player table The player object
---@return boolean True if a state transition occurred
function common.process_input_queue(player)
	local state = try_queued_combat_action(player)
	if state then
		common.clear_input_queue(player)
		transition_or_restart(player, state)
		return true
	end
	if player.input_queue.jump then
		player.input_queue.jump = false
		if player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player:set_state(player.states.air)
			return true
		end
	end
	return false
end

--- Standard queue input handler for locked states.
--- Call this in the input() function of locked states.
---@param player table The player object
function common.queue_inputs(player)
	if controls.jump_pressed() then
		common.queue_input(player, "jump")
	end
	if controls.attack_pressed() then
		common.queue_input(player, "attack")
	end
	local slot = controls.any_ability_pressed()
	if slot then
		common.queue_input(player, "ability", slot)
	end
end

--- Checks for queued attack or ability that were waiting on cooldown.
--- Also checks stamina for attack and energy/stamina for ability.
--- Call this in input() of states that allow attacking/ability use (idle, run, air).
---@param player table The player object
---@return boolean True if a state transition occurred
function common.check_cooldown_queues(player)
	local state = try_queued_combat_action(player)
	if state then
		player:set_state(state)
		return true
	end
	return false
end

--- Creates a melee weapon hitbox positioned relative to the player.
--- The hitbox extends from the player's front edge in their facing direction.
--- Note: Returns a reused table - do not store the reference.
---@param player table The player object
---@param width number Hitbox width in tiles
---@param height number Hitbox height in tiles
---@param y_offset number Vertical offset from player box top (negative = up)
---@return table Hitbox with x, y, w, h in tile coordinates
function common.create_melee_hitbox(player, width, height, y_offset)
	if player.direction == 1 then
		_melee_hitbox.x = player.x + player.box.x + player.box.w
	else
		_melee_hitbox.x = player.x + player.box.x - width
	end
	_melee_hitbox.y = player.y + player.box.y + y_offset
	_melee_hitbox.w = width
	_melee_hitbox.h = height
	return _melee_hitbox
end

--- Draws player animation and shield debug box.
--- Shared by block and block_move states.
---@param player table The player object
function common.draw_blocking(player)
	common.draw(player)
	shield = shield or require('player.shield')
	shield.draw_debug(player)
end

--- Standard draw helper that applies pressure plate lift.
--- Call this instead of player.animation:draw() in state draw functions.
---@param player table The player object
---@param y_offset number|nil Optional Y offset in tiles (e.g., 0.25 for sitting pose)
---@param x_offset number|nil Optional X offset in tiles (e.g., for wide attack sprites)
function common.draw(player, y_offset, x_offset)
	local lift = Prop.get_pressure_plate_lift(player)
	local x = player.x + (x_offset or 0)
	local y = player.y + (y_offset or 0)
	player.animation:draw(sprites.px(x), sprites.stable_y(player, y, -lift))
end

--- Draws a debug hitbox when bounding boxes are enabled.
--- Used by attack and hammer states to visualize weapon reach.
---@param hitbox table|nil Hitbox with x, y, w, h in tile coordinates (nil = no draw)
---@param color string Hex color string for the hitbox
function common.draw_debug_hitbox(hitbox, color)
	if not config.bounding_boxes or not hitbox then return end
	canvas.set_color(color)
	canvas.draw_rect(
		hitbox.x * sprites.tile_size,
		hitbox.y * sprites.tile_size,
		hitbox.w * sprites.tile_size,
		hitbox.h * sprites.tile_size)
end

return common
