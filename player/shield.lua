local Animation = require('Animation')
local audio = require('audio')
local canvas = require('canvas')
local common = require('player.common')
local config = require('config')
local sprites = require('sprites')
local world = require('world')

--- Shield module: Consolidates all player shield logic.
--- Handles shield lifecycle, damage blocking, knockback, and state management.
local shield = {}

-- Shield dimensions: 4px (0.25 tiles) wide, matches player height
shield.BOX = { w = 0.25, h = 0.85 }

-- Block stamina cost: 1.5 stamina per point of damage blocked (5 stamina blocks ~3 damage)
shield.STAMINA_COST_PER_DAMAGE = 1.5

-- Knockback speed when absorbing a hit with shield
shield.KNOCKBACK_SPEED = 8

-- Knockback decay rate (per 60fps frame, applied with dt scaling)
shield.KNOCKBACK_DECAY = 0.85

-- Knockback threshold below which velocity is zeroed
shield.KNOCKBACK_THRESHOLD = 0.1

-- Perfect block window: 4 frames at 60fps
shield.PERFECT_BLOCK_WINDOW = 4 / 60

-- Perfect block cooldown: 6 frames at 60fps (~100ms) - prevents spam
shield.PERFECT_BLOCK_COOLDOWN = 6 / 60

-- Shield lifecycle (wraps world.lua)

--- Creates a shield collider for the player.
--- Idempotent: removes existing shield before creating new one.
---@param player table The player object
function shield.create(player)
	world.add_shield(player, shield.BOX)
end

--- Updates shield position based on player position and direction.
---@param player table The player object
function shield.update(player)
	world.update_shield(player, shield.BOX)
end

--- Removes the shield collider for the player.
---@param player table The player object
function shield.remove(player)
	world.remove_shield(player)
end

--- Attempts to block incoming damage with the shield.
--- Checks if blocking and facing the damage source. If blocked: drains stamina,
--- applies knockback, plays sound. If guard break: removes shield.
--- Perfect block: if in stationary block state with active window, no stamina cost.
---@param player table The player object
---@param damage number Amount of damage being blocked
---@param source_x number|nil X position of damage source
---@return boolean blocked True if damage was successfully blocked
---@return boolean guard_break True if guard was broken (out of stamina)
---@return boolean perfect True if this was a perfect block (no stamina cost)
function shield.try_block(player, damage, source_x)
	-- Check if in block state
	local is_blocking = player.state == player.states.block or player.state == player.states.block_move
	if not is_blocking or not source_x then
		return false, false, false
	end

	-- Check if facing the damage source
	-- Uses >= / <= to match Enemy:check_player_overlap's directional_shield check
	-- (enemy_on_left == player_facing_left includes the == case)
	local from_front = (player.direction == 1 and source_x >= player.x) or
	                   (player.direction == -1 and source_x <= player.x)
	if not from_front then
		return false, false, false
	end

	-- Perfect block check: must be in stationary block state (not block_move) with active window
	local is_stationary = player.state == player.states.block
	local window = player.block_state.perfect_window or 0
	local is_perfect = is_stationary and window > 0

	if is_perfect then
		-- Perfect block: no stamina cost, apply knockback, play sound
		shield.apply_knockback(player, source_x)
		audio.play_solid_sound()
		return true, false, true
	end

	local current_stamina = player.max_stamina - player.stamina_used

	if current_stamina > 0 then
		-- Successful block: drain stamina (reduced by doubled defence, capped at 100%), apply knockback
		local shield_defense = math.min(100, player:defense_percent() * 2)
		local reduction = 1 - (shield_defense / 100)
		local stamina_cost = damage * shield.STAMINA_COST_PER_DAMAGE * reduction
		player.stamina_used = player.stamina_used + stamina_cost
		player.stamina_regen_timer = 0
		-- Trigger fatigue if shield drain pushed past max stamina
		if player.stamina_used > player.max_stamina and not player:is_fatigued() then
			player.fatigue_remaining = common.FATIGUE_DURATION
		end

		-- Knockback away from source
		shield.apply_knockback(player, source_x)
		audio.play_solid_sound()
		return true, false, false
	else
		-- Guard break: no stamina remaining, remove shield
		shield.remove(player)
		return false, true, false
	end
end

--- Applies knockback decay to block_state.knockback_velocity when grounded.
---@param player table The player object
---@param dt number Delta time in seconds
---@return number Updated knockback velocity
function shield.decay_knockback(player, dt)
	local kb = player.block_state.knockback_velocity
	if kb == 0 then return 0 end

	if player.is_grounded then
		kb = kb * (shield.KNOCKBACK_DECAY ^ (dt * 60))
		if math.abs(kb) < shield.KNOCKBACK_THRESHOLD then
			kb = 0
		end
		player.block_state.knockback_velocity = kb
	end
	return kb
end

--- Applies knockback away from the damage source.
---@param player table The player object
---@param source_x number X position of damage source
function shield.apply_knockback(player, source_x)
	local knockback_dir = source_x > player.x and -1 or 1
	player.block_state.knockback_velocity = knockback_dir * shield.KNOCKBACK_SPEED
end

--- Clears knockback velocity.
---@param player table The player object
function shield.clear_knockback(player)
	player.block_state.knockback_velocity = 0
end

--- Initializes block state: sets animation, clears knockback, creates shield.
--- Shared by block and block_move states.
--- Initializes perfect block window only on fresh block session (not returning from block_move).
---@param player table The player object
---@param animation table Animation definition to use
function shield.init_state(player, animation)
	player.animation = Animation.new(animation)
	shield.clear_knockback(player)
	shield.create(player)

	-- Only init perfect window if nil (fresh block session)
	-- Returning from block_move keeps window at 0 (invalidated)
	if player.block_state.perfect_window == nil then
		local cooldown = player.block_state.cooldown or 0
		if cooldown > 0 then
			-- On cooldown from recent block, no perfect block
			player.block_state.perfect_window = 0
		else
			-- Fresh entry, allow perfect block
			player.block_state.perfect_window = shield.PERFECT_BLOCK_WINDOW
		end
	end
end

--- Exits block state: removes shield, clears knockback, transitions to idle.
--- Resets perfect window and starts cooldown.
---@param player table The player object
function shield.exit_state(player)
	shield.remove(player)
	shield.clear_knockback(player)
	-- Reset perfect window (nil = fresh session next time)
	player.block_state.perfect_window = nil
	-- Start cooldown to prevent perfect block spam
	player.block_state.cooldown = shield.PERFECT_BLOCK_COOLDOWN
	player:set_state(player.states.idle)
end

--- Updates perfect block window timer (decrement each frame).
--- Call from block.update() only (not block_move).
---@param player table The player object
---@param dt number Delta time in seconds
function shield.update_perfect_window(player, dt)
	local w = player.block_state.perfect_window
	if w and w > 0 then
		player.block_state.perfect_window = math.max(0, w - dt)
	end
end

--- Updates perfect block cooldown timer (decrement when not blocking).
--- Call from Player:update() when not in block/block_move states.
---@param player table The player object
---@param dt number Delta time in seconds
function shield.update_cooldown(player, dt)
	local c = player.block_state.cooldown
	if c and c > 0 then
		player.block_state.cooldown = math.max(0, c - dt)
	end
end

--- Invalidates the perfect block window (sets to 0, not nil).
--- Call when moving or attacking from block state.
--- Setting to 0 (not nil) prevents re-initialization when returning to block.
---@param player table The player object
function shield.clear_perfect_window(player)
	player.block_state.perfect_window = 0
end

--- Checks if player should guard break due to fatigue.
--- If fatigued, exits block state and returns true.
---@param player table The player object
---@return boolean True if guard break occurred
function shield.check_guard_break(player)
	if player:is_fatigued() then
		shield.exit_state(player)
		return true
	end
	return false
end

--- Draws debug shield bounding box (blue) when config.bounding_boxes is enabled.
---@param player table The player object
function shield.draw_debug(player)
	if not config.bounding_boxes then return end

	local x_offset
	if player.direction == 1 then
		x_offset = player.box.x + player.box.w
	else
		x_offset = player.box.x - shield.BOX.w
	end
	local sx = (player.x + x_offset) * sprites.tile_size
	local sy = (player.y + player.box.y) * sprites.tile_size
	canvas.set_color("#0088FF")
	canvas.draw_rect(sx, sy, shield.BOX.w * sprites.tile_size, shield.BOX.h * sprites.tile_size)
end

return shield
