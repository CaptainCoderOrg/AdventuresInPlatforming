local Animation = require('Animation')
local Prop = require('Prop')
local audio = require('audio')
local controls = require('controls')
local prop_common = require('Prop/common')
local sprites = require('sprites')

local common = {}

common.GRAVITY = 1.5
common.JUMP_VELOCITY = common.GRAVITY * 14
common.AIR_JUMP_VELOCITY = common.GRAVITY * 11
common.MAX_COYOTE_TIME = 4 / 60  -- 0.0667 seconds (4 frames at 60 FPS)
common.MAX_FALL_SPEED = 20

-- Animations (converted to delta-time based, milliseconds per frame)
common.animations = {
	IDLE = Animation.create_definition(sprites.player.idle, 6, { ms_per_frame = 240 }),
	BLOCK = Animation.create_definition(sprites.player.block, 1, { ms_per_frame = 17, loop = false }),
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

--- Checks for hammer input and transitions to hammer state if pressed.
---@param player table The player object
function common.handle_hammer(player)
    if controls.hammer_pressed() then
        player:set_state(player.states.hammer)
    end
end

--- Checks for throw input and transitions to throw state or queues if on cooldown.
--- Requires available energy (energy_used < max_energy) to throw.
---@param player table The player object
function common.handle_throw(player)
    if controls.throw_pressed() then
        -- Block throw entirely when out of energy (no cooldown queue needed)
        if player.energy_used >= player.max_energy then return end
        if player.throw_cooldown <= 0 then
            player:set_state(player.states.throw)
        else
            common.queue_input(player, "throw")
        end
    end
end

--- Checks for attack input and transitions to attack state or queues if on cooldown.
--- Requires available stamina to attack (consumed via use_stamina).
---@param player table The player object
function common.handle_attack(player)
	if controls.attack_pressed() then
		if player.attack_cooldown <= 0 then
			if player:use_stamina(1) then
				player:set_state(player.states.attack)
			end
		else
			-- Queue attack during cooldown (stamina checked when queue is processed)
			common.queue_input(player, "attack")
		end
	end
end

--- Checks for block input and transitions to block state if held.
---@param player table The player object
function common.handle_block(player)
    if controls.block_down() then
		player:set_state(player.states.block)
	end
end

--- Checks if the player is touching a campfire prop.
---@param player table The player object
---@return boolean True if player is touching a campfire prop
function common.is_near_campfire(player)
	for prop in pairs(Prop.all) do
		if prop.type_key == "campfire" and prop_common.player_touching(prop, player) then
			return true
		end
	end
	return false
end

--- Checks for rest input (down + attack) and transitions to rest state if near campfire.
---@param player table The player object
---@return boolean True if transitioned to rest state
function common.handle_rest(player)
	if controls.down_down() and controls.attack_pressed() then
		if common.is_near_campfire(player) then
			player:set_state(player.states.rest)
			return true
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

--- Applies gravity and transitions to air state if not grounded.
---@param player table The player object
---@param dt number Delta time in seconds
---@param max_speed number|nil Maximum fall speed (defaults to MAX_FALL_SPEED)
function common.handle_gravity(player, dt, max_speed)
	common.apply_gravity(player, dt, max_speed)
	if not player.is_grounded and
           player.state ~= player.states.block and
           player.state ~= player.states.hit and
		   player.state ~= player.states.throw
		   then
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

function common.check_hit(player, cols)
    local canvas = require('canvas')
    if canvas.is_key_pressed(canvas.keys.Y) and not player:is_invincible() then
        player:take_damage(1)
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
	for _, trigger in pairs(cols.triggers) do
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
		player.ceiling_normal = cols.ceiling_normal
		if player.vy < 0 then
			player.vy = 0
		end
	else
		player.ceiling_normal = nil
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

--- Attempts an air jump if the player has remaining jumps and jump is pressed.
---@param player table The player object
---@return boolean True if air jump was performed
function common.handle_air_jump(player)
	if controls.jump_pressed() and player.jumps > 0 then
		player.vy = -common.AIR_JUMP_VELOCITY
		player.jumps = player.jumps - 1
		player.is_air_jumping = true
		audio.play_air_jump_sound()
		return true
	end
	return false
end

--- Attempts to initiate a dash if off cooldown and dash is pressed.
---@param player table The player object
---@return boolean True if dash was initiated
function common.handle_dash(player)
	if player.dash_cooldown > 0 or not player.has_dash then return false end
	if controls.dash_pressed() then
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
---@param player table The player object
---@return table Tangent vector {x, y}
function common.get_ground_tangent(player)
	local nx = player.ground_normal.x
	local ny = player.ground_normal.y
	-- Tangent perpendicular to normal, pointing right
	return { x = -ny, y = nx }
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

--- Processes queued inputs with priority (attack > throw > jump).
--- Called when exiting locked states (throw, hammer, hit) to chain actions.
--- Respects cooldowns and resource costs - blocked entries persist for check_cooldown_queues.
---@param player table The player object
---@return boolean True if a state transition occurred
function common.process_input_queue(player)
	if player.input_queue.attack and player.attack_cooldown <= 0 then
		if player:use_stamina(1) then
			common.clear_input_queue(player)
			transition_or_restart(player, player.states.attack)
			return true
		end
	end
	if player.input_queue.throw and player.throw_cooldown <= 0 then
		common.clear_input_queue(player)
		transition_or_restart(player, player.states.throw)
		return true
	end
	if player.input_queue.jump then
		-- Jump can't be deferred, clear it regardless of success
		player.input_queue.jump = false
		if player.is_grounded then
			player.vy = -common.JUMP_VELOCITY
			player:set_state(player.states.air)
			return true
		end
	end
	-- Don't clear attack/throw - they persist for check_cooldown_queues
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
--- Also checks stamina for attack and energy for throw.
--- Call this in input() of states that allow attacking/throwing (idle, run, air).
---@param player table The player object
---@return boolean True if a state transition occurred
function common.check_cooldown_queues(player)
	if player.input_queue.attack and player.attack_cooldown <= 0 then
		if player:use_stamina(1) then
			player.input_queue.attack = false
			player:set_state(player.states.attack)
			return true
		end
	end
	if player.input_queue.throw and player.throw_cooldown <= 0 and player.energy_used < player.max_energy then
		player.input_queue.throw = false
		player:set_state(player.states.throw)
		return true
	end
	return false
end

--- Creates a melee weapon hitbox positioned relative to the player.
--- The hitbox extends from the player's front edge in their facing direction.
---@param player table The player object
---@param width number Hitbox width in tiles
---@param height number Hitbox height in tiles
---@param y_offset number Vertical offset from player box top (negative = up)
---@return table Hitbox with x, y, w, h in tile coordinates
function common.create_melee_hitbox(player, width, height, y_offset)
	local hitbox_x
	if player.direction == 1 then
		hitbox_x = player.x + player.box.x + player.box.w
	else
		hitbox_x = player.x + player.box.x - width
	end

	return {
		x = hitbox_x,
		y = player.y + player.box.y + y_offset,
		w = width,
		h = height
	}
end

return common
