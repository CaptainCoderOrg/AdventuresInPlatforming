local Animation = require('Animation')
local audio = require('audio')
local canvas = require('canvas')
local combat = require('combat')
local config = require('config')
local controls = require('controls')
local Effects = require('Effects')
local sprites = require('sprites')
local world = require('world')
local Prop = require('Prop')

local common = {}

-- Reusable tables to avoid per-frame allocations
local _melee_hitbox = { x = 0, y = 0, w = 0, h = 0 }
local _ground_tangent = { x = 0, y = 0 }

common.GRAVITY = 1.5
common.JUMP_VELOCITY = common.GRAVITY * 14
common.AIR_JUMP_VELOCITY = common.GRAVITY * 11
common.MAX_COYOTE_TIME = 6 / 60
common.MAX_FALL_SPEED = 20

-- Stamina costs (balanced against max_stamina=5)
-- Attack costs 2: allows 2 full attacks before fatigue
common.ATTACK_STAMINA_COST = 2
-- Hammer costs 5: single use depletes bar, high-risk/high-reward
common.HAMMER_STAMINA_COST = 5
-- Air jump costs 1: double jump only, ground jump stays free
common.AIR_JUMP_STAMINA_COST = 1
-- Dash costs 2.5: high cost for powerful escape/engage
common.DASH_STAMINA_COST = 2.5
-- Wall jump costs 1: matches air jump cost
common.WALL_JUMP_STAMINA_COST = 1
-- Block stamina cost: 1.5 stamina per point of damage blocked (5 stamina blocks ~3 damage)
common.BLOCK_STAMINA_COST_PER_DAMAGE = 1.5
-- Block move speed: 35% of normal speed for slow defensive movement
common.BLOCK_MOVE_SPEED_MULTIPLIER = 0.35

-- Shield dimensions: 4px (0.25 tiles) wide, matches player height
common.SHIELD_BOX = { w = 0.25, h = 0.85 }

-- Knockback decay rate (per 60fps frame, applied with dt scaling)
common.KNOCKBACK_DECAY = 0.85
-- Knockback threshold below which velocity is zeroed
common.KNOCKBACK_THRESHOLD = 0.1

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

	ATTACK_0 = Animation.create_definition(sprites.player.attack_0, 5, { ms_per_frame = 50, width = 32, loop = false }),
	ATTACK_1 = Animation.create_definition(sprites.player.attack_1, 5, { ms_per_frame = 67, width = 32, loop = false }),
	ATTACK_2 = Animation.create_definition(sprites.player.attack_2, 5, { ms_per_frame = 83, width = 32, loop = false }),
	HAMMER = Animation.create_definition(sprites.player.attack_hammer, 7, { ms_per_frame = 150, width = 32, loop = false }),
	THROW = Animation.create_definition(sprites.player.throw, 7, { ms_per_frame = 33, loop = false }),

	HIT = Animation.create_definition(sprites.player.hit, 3, { ms_per_frame = 80, loop = false }),
	DEATH = Animation.create_definition(sprites.player.death, 12, { ms_per_frame = 80, loop = false }),
	REST = Animation.create_definition(sprites.player.rest, 1, { ms_per_frame = 1000, loop = false }),
}

--- Attempts to consume throw stamina cost from the player's current projectile.
--- Returns true if no cost required or if stamina was successfully consumed.
---@param player table The player object
---@return boolean True if throw is allowed (no cost or stamina consumed)
local function try_use_throw_stamina(player)
    local stamina_cost = player.projectile.stamina_cost or 0
    return stamina_cost == 0 or player:use_stamina(stamina_cost)
end

--- Checks if the player has enough energy for the current projectile's energy cost.
---@param player table The player object
---@return boolean True if player has sufficient energy to throw
local function has_throw_energy(player)
    local energy_cost = player.projectile.energy_cost or 1
    return player.energy_used + energy_cost <= player.max_energy
end

--- Checks for hammer input and transitions to hammer state if pressed.
---@param player table The player object
function common.handle_hammer(player)
    if controls.hammer_pressed() then
        if player:use_stamina(common.HAMMER_STAMINA_COST) then
            player:set_state(player.states.hammer)
        end
    end
end

--- Checks for throw input and transitions to throw state or queues if on cooldown.
--- Requires sufficient energy and stamina (based on projectile costs) to throw.
---@param player table The player object
function common.handle_throw(player)
    if controls.throw_pressed() then
        -- Block throw entirely when insufficient energy (no cooldown queue needed)
        if not has_throw_energy(player) then
            -- Show visual feedback for insufficient energy
            local current_energy = player.max_energy - player.energy_used
            Effects.create_energy_text(player.x, player.y, current_energy)
            player.energy_flash_requested = true
            return
        end
        if player.throw_cooldown <= 0 then
            if try_use_throw_stamina(player) then
                player:set_state(player.states.throw)
            end
        else
            common.queue_input(player, "throw")
        end
    end
end

--- Checks for attack input and transitions to attack state or queues if on cooldown.
--- Requires available stamina to attack (consumed via use_stamina).
---@param player table The player object
---@return boolean True if transitioned to attack state
function common.handle_attack(player)
	if controls.attack_pressed() then
		if player.attack_cooldown <= 0 then
			if player:use_stamina(common.ATTACK_STAMINA_COST) then
				player:set_state(player.states.attack)
				return true
			end
		else
			-- Queue attack during cooldown (stamina checked when queue is processed)
			common.queue_input(player, "attack")
		end
	end
	return false
end

--- Checks for block input and transitions to block state if held.
--- Requires positive stamina (cannot block while fatigued).
--- Shows "TIRED" text on first press when fatigued.
---@param player table The player object
function common.handle_block(player)
	local block_down = controls.block_down()
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
--- Entry points: standing on ladder top + down, grounded + up, in air + down/up.
---@param player table The player object
function common.handle_climb(player)
	-- Entry from top of ladder (down while standing on ladder top)
	if player.standing_on_ladder_top and player.is_grounded then
		if controls.down_down() then
			player:set_state(player.states.climb)
		end
		return  -- Don't allow up to enter climb from top
	end
	-- Entry from middle of ladder (up or down while overlapping ladder)
	-- Grounded + UP = start climbing from bottom
	-- In air + DOWN = grab ladder while falling
	-- In air + UP = grab ladder while jumping (but not at top, to prevent flicker)
	local up_pressed_on_ground = controls.up_down() and player.is_grounded
	local down_pressed_in_air = controls.down_down() and not player.is_grounded
	local up_pressed_in_air = controls.up_down() and not player.is_grounded and not player.on_ladder_top
	if (up_pressed_on_ground or down_pressed_in_air or up_pressed_in_air) and player.can_climb then
		player:set_state(player.states.climb)
	end
end

--- Debug function to test hit state via Y key press.
--- Applies 1 damage to player if not invincible.
--- Also handles '8' key to grant 8000 experience for testing.
---@param player table The player object
---@param _cols table Collision results (unused, kept for interface consistency)
function common.check_hit(player, _cols)
    if canvas.is_key_pressed(canvas.keys.Y) and not player:is_invincible() then
        player:take_damage(1)
    end
    if canvas.is_key_pressed(canvas.keys.DIGIT_8) then
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
			player.has_dash = true
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
---@param player table The player object
---@return boolean True if air jump was performed
function common.handle_air_jump(player)
	if controls.jump_pressed() and player.jumps > 0 then
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

--- Attempts to initiate a dash if off cooldown, has stamina, and dash is pressed.
---@param player table The player object
---@return boolean True if dash was initiated
function common.handle_dash(player)
	if player.dash_cooldown > 0 or not player.has_dash then return false end
	if controls.dash_pressed() then
		if player:use_stamina(common.DASH_STAMINA_COST) then
			player:set_state(player.states.dash)
			return true
		end
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
---@param input_name string The input to queue ("jump", "attack", or "throw")
function common.queue_input(player, input_name)
	player.input_queue[input_name] = true
end

--- Clears all queued inputs.
---@param player table The player object
function common.clear_input_queue(player)
	player.input_queue.jump = false
	player.input_queue.attack = false
	player.input_queue.throw = false
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

--- Attempts to process queued attack or throw input.
--- Clears queue entry when cooldown ready, returns target state on successful stamina use.
---@param player table The player object
---@return table|nil Target state if action succeeded, nil otherwise
local function try_queued_combat_action(player)
	if player.input_queue.attack and player.attack_cooldown <= 0 then
		player.input_queue.attack = false
		if player:use_stamina(common.ATTACK_STAMINA_COST) then
			return player.states.attack
		end
	end
	if player.input_queue.throw and player.throw_cooldown <= 0 and has_throw_energy(player) then
		player.input_queue.throw = false
		if try_use_throw_stamina(player) then
			return player.states.throw
		end
	end
	return nil
end

--- Processes queued inputs with priority (attack > throw > jump).
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
	if controls.throw_pressed() then
		common.queue_input(player, "throw")
	end
end

--- Checks for queued attack or throw that were waiting on cooldown.
--- Also checks stamina for attack and energy/stamina for throw.
--- Call this in input() of states that allow attacking/throwing (idle, run, air).
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

--- Applies knockback decay to block_state.knockback_velocity when grounded.
--- Returns updated knockback velocity (also stored in player.block_state).
---@param player table The player object
---@param dt number Delta time in seconds
---@return number Updated knockback velocity
function common.decay_knockback(player, dt)
	local kb = player.block_state.knockback_velocity
	if kb == 0 then return 0 end

	if player.is_grounded then
		kb = kb * (common.KNOCKBACK_DECAY ^ (dt * 60))
		if math.abs(kb) < common.KNOCKBACK_THRESHOLD then
			kb = 0
		end
		player.block_state.knockback_velocity = kb
	end
	return kb
end

--- Initializes block state: sets animation, clears knockback, creates shield.
--- Shared by block and block_move states.
---@param player table The player object
---@param animation table Animation definition to use
function common.init_block_state(player, animation)
	player.animation = Animation.new(animation)
	player.block_state.knockback_velocity = 0
	world.add_shield(player, common.SHIELD_BOX)
end

--- Exits block state: removes shield, clears knockback, transitions to idle.
---@param player table The player object
function common.exit_block(player)
	world.remove_shield(player)
	player.block_state.knockback_velocity = 0
	player:set_state(player.states.idle)
end

--- Draws debug shield bounding box (blue) when config.bounding_boxes is enabled.
---@param player table The player object
local function draw_shield_debug(player)
	if not config.bounding_boxes then return end

	local shield = common.SHIELD_BOX
	local x_offset
	if player.direction == 1 then
		x_offset = player.box.x + player.box.w
	else
		x_offset = player.box.x - shield.w
	end
	local sx = (player.x + x_offset) * sprites.tile_size
	local sy = (player.y + player.box.y) * sprites.tile_size
	canvas.set_color("#0088FF")
	canvas.draw_rect(sx, sy, shield.w * sprites.tile_size, shield.h * sprites.tile_size)
end

--- Draws player animation and shield debug box.
--- Shared by block and block_move states.
---@param player table The player object
function common.draw_blocking(player)
	common.draw(player)
	draw_shield_debug(player)
end

--- Standard draw helper that applies pressure plate lift.
--- Call this instead of player.animation:draw() in state draw functions.
---@param player table The player object
---@param y_offset number|nil Optional Y offset in tiles (e.g., 0.25 for sitting pose)
function common.draw(player, y_offset)
	local lift = Prop.get_pressure_plate_lift(player)
	local y = player.y + (y_offset or 0)
	player.animation:draw(sprites.px(player.x), sprites.stable_y(player, y, -lift))
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
