local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local combat = require('combat')
local common = require('player.common')
local shield = require('player.shield')
local Animation = require('Animation')
local Projectile = require('Projectile')
local controls = require('controls')
local weapon_sync = require('player.weapon_sync')
local Effects = require('Effects')
local audio = require('audio')
local stats = require('player.stats')

local Player = {}
Player.__index = Player

-- Load all states (shared across instances)
local states = {
	idle = require('player.idle'),
	run = require('player.run'),
	dash = require('player.dash'),
	air = require('player.air'),
	wall_slide = require('player.wall_slide'),
	wall_jump = require('player.wall_jump'),
	attack = require('player.attack'),
	climb = require('player.climb'),
	block = require('player.block'),
	block_move = require('player.block_move'),
	hammer = require('player.hammer'),
	throw = require('player.throw'),
	hit = require('player.hit'),
	death = require('player.death'),
	rest = require('player.rest'),
	stairs_up = require('player.stairs_up'),
	stairs_down = require('player.stairs_down'),
}

-- Expose states for direct reference
Player.states = states

-- Fatigue system constants
-- 75% speed is noticeable but still allows escape/repositioning
local FATIGUE_SPEED_MULTIPLIER = 0.75
-- 1/4 regen rate creates ~4 second recovery window as punishment for overcommitting
local FATIGUE_REGEN_MULTIPLIER = 0.25
-- Extra debt ensures player can't immediately attack again after recovering
local FATIGUE_ENTRY_PENALTY = 1
-- Seconds between sweat particle spawns (50ms = rapid dripping effect)
local FATIGUE_PARTICLE_INTERVAL = 0.05

--- Creates a new player instance
---@return table player A new player object
function Player.new()
	local self = setmetatable({}, Player)

	-- Player Health
	self.max_health = 3
	self.damage = 0
	self.invincible_time = 0

	-- Player Stamina
	-- Consumed by attacks and abilities, regenerates gradually after delay
	self.max_stamina = 3
	self.stamina_used = 0
	self.stamina_regen_rate = 5       -- Stamina regenerated per second
	self.stamina_regen_cooldown = 0.5 -- Seconds before regen begins after use
	self.stamina_regen_timer = 0      -- Time since last stamina use (seconds)
	self.was_fatigued = false         -- Tracks previous fatigue state for transition detection
	self.fatigue_particle_timer = 0   -- Timer for spawning fatigue particles

	-- Player Energy
	-- Consumed by thrown weapons (1 per throw), restored when resting at campfire
	self.max_energy = 3
	self.energy_used = 0
	self.energy_flash_requested = false  -- Flag for UI to trigger energy bar flash

	-- Progression / RPG Stats
	self.level = 1              -- Player level, gates content and affects base stats
	self.experience = 0         -- XP toward next level
	self.gold = 0               -- Currency for purchases
	self.defense = 0            -- Reduces incoming damage (points, diminishing returns)
	self.recovery = 0           -- Increases stamina recovery rate (points, diminishing returns)
	self.critical_chance = 2    -- Percent chance for critical hit damage (2 points = 5% base)
	self.stat_upgrades = {      -- Track how many times each stat was upgraded (for refunds)
		Health = 0,
		Stamina = 0,
		Energy = 0,
		Defence = 0,
		Recovery = 0,
		Critical = 0,
	}
	self.unique_items = {}      -- Permanently collected key items (for locked doors, etc.)
	self.equipped_items = {}    -- Set of equipped item_ids (item_id -> true)
	self.active_weapon = nil    -- item_id of currently active weapon (for quick swap)
	self.active_secondary = nil -- item_id of currently active secondary (for ability swap)

	-- Position and velocity
	self.x = 2
	self.y = 2
	self.vx = 0
	self.vy = 0
	self.box = { w = 0.60, h = 0.85, x = 0.2, y = 0.15 }
	self.is_player = true
	-- Tracks last grounded position for out-of-bounds recovery
	self.last_safe_position = { x = self.x, y = self.y }

	-- Movement
	self._base_speed = 6
	self.direction = 1
	self.is_grounded = true
	self.ground_normal = { x = 0, y = -1 }
	self.has_ceiling = false
	self.ceiling_normal = { x = 0, y = 1 }
	-- Persistent collision result table (avoids per-frame allocation)
	self._cols = {
		ground = false, ceiling = false, wall_left = false, wall_right = false,
		ground_normal = { x = 0, y = -1 },
		ceiling_normal = { x = 0, y = 1 },
		has_ceiling_normal = false,
		triggers = {}
	}

	-- Jumping
	self.jumps = 2
	self.max_jumps = 2
	self.is_air_jumping = false
	self.coyote_time = 0
	self.has_double_jump = false

	-- Wall movement
	self.has_wall_slide = false
	self.wall_direction = 0
	self.wall_jump_dir = 0

	-- Climbing
	self.can_climb = false
	self.is_climbing = false
	self.current_ladder = nil
	self.on_ladder_top = false
	self.standing_on_ladder_top = false
	self.standing_on_bridge = false
	self.wants_drop_through = false
	self.drop_through_y = nil
	self.climb_touching_ground = false
	self.climb_speed = self._base_speed / 2

	-- Combat
	self.attacks = 3
	self.attack_cooldown = 0
	self.throw_cooldown = 0
	self.attack_speed_multiplier = 1.0  -- For future speed upgrades
	self.has_hammer = false             -- Legacy flag (combat now uses equipped_items)
	self.has_axe = false
	self.has_shuriken = false
	self.has_shield = false

	-- Dash
	self.dash_cooldown = 0
	self.dash_speed = self._base_speed * 3
	self.has_dash = true       -- Cooldown flag (resets on ground)
	self.can_dash = false      -- Unlock flag (progression)

	-- Animation
	self.animation = Animation.new(common.animations.IDLE)

	-- State machine
	self.state = nil
	self.states = states  -- Reference for state transitions

	-- Active projectile spec (synced by weapon_sync from active_secondary)
	self.projectile = nil

	-- State-specific storage (for states with module-level variables)
	self.run_state = {
		footstep_cooldown = 0,
		is_turning = false,
		turn_remaining_frames = 0,
		previous_direction = nil,
		turn_visual_direction = nil
	}
	self.dash_state = {
		direction = 1,
		elapsed_time = 0
	}
	self.attack_state = {
		count = 0,
		next_anim_ix = 1,
		remaining_time = 0,
		queued = false,
		hit_enemies = {}
	}
	self.climb_state = {
		last_ladder = nil
	}
	self.wall_slide_state = {
		grace_time = 0,
		holding_wall = false
	}
	self.wall_jump_state = {
		locked_direction = 0
	}
	self.hammer_state = {
		remaining_time = 0,
		hit_enemies = {},
		hit_button = false,
		sound_played = false
	}
	self.throw_state = {
		remaining_time = 0
	}
	self.hit_state = {
		knockback_speed = 2,
		remaining_time = 0
	}
	self.block_state = {
		knockback_velocity = 0,
		perfect_window = nil,  -- nil = fresh session, 0 = invalidated, >0 = active window
		cooldown = 0,          -- Time until next perfect block is allowed
	}

	-- Centralized input queue for locked states (hit, throw, attack).
	-- Inputs are queued during locked states and processed on state exit.
	-- Attack/throw entries persist across state transitions until cooldown expires,
	-- allowing check_cooldown_queues() to execute them in idle/run/air states.
	self.input_queue = {
		jump = false,
		attack = false,
		throw = false
	}

	-- Register with collision system
	world.add_collider(self)

	-- Register with combat hitbox system
	combat.add(self)

	-- Initialize default state
	self:set_state(states.idle)

	return self
end

--- Returns whether a projectile type is unlocked (legacy check based on ability flags).
---@param proj table Projectile definition
---@return boolean True if unlocked
function Player:is_projectile_unlocked(proj)
	if proj.name == "Axe" then return self.has_axe end
	if proj.name == "Shuriken" then return self.has_shuriken end
	return true  -- Unknown projectile types default to unlocked
end

--- Cycles to the next equipped secondary ability.
--- Uses the active_secondary system from weapon_sync.
--- Updates self.projectile to maintain compatibility with throw state.
---@return string|nil name The new active secondary's display name, or nil if not switched
function Player:next_projectile()
	local name = weapon_sync.cycle_secondary(self)
	-- Keep legacy projectile reference in sync
	local spec = weapon_sync.get_secondary_spec(self)
	if spec then
		self.projectile = spec
	end
	return name
end

--- Returns whether player is currently invincible (post-hit immunity frames).
---@return boolean True if invincible
function Player:is_invincible()
	return self.invincible_time > 0
end

--- Attempts to consume stamina for an ability.
--- Allows use as long as available stamina >= 0 (can push into fatigue).
--- Blocks use when already fatigued (available < 0).
--- Adds 1 extra stamina penalty when entering fatigue state.
--- Resets regen timer on successful use.
---@param amount number Amount of stamina to consume
---@return boolean True if stamina was consumed, false if fatigued
function Player:use_stamina(amount)
	local available = self.max_stamina - self.stamina_used

	-- Block stamina use while fatigued (available < 0)
	if available < 0 then
		return false
	end

	-- Consume stamina (can push into fatigue)
	self.stamina_used = self.stamina_used + amount

	-- Entry penalty stacks with overspend (e.g., 4 used + 2 attack + 1 penalty = 7 debt)
	-- This scales punishment: bigger overspends = longer recovery
	if self.stamina_used > self.max_stamina then
		self.stamina_used = self.stamina_used + FATIGUE_ENTRY_PENALTY
	end

	self.stamina_regen_timer = 0
	return true
end

--- Returns whether player is currently fatigued (stamina debt).
---@return boolean True if stamina_used > max_stamina
function Player:is_fatigued()
	return self.stamina_used > self.max_stamina
end

--- Returns effective movement speed, accounting for fatigue penalty.
---@return number Effective speed (pixels/frame)
function Player:get_speed()
	if self:is_fatigued() then
		return self._base_speed * FATIGUE_SPEED_MULTIPLIER
	end
	return self._base_speed
end

--- Returns current health (max_health minus accumulated damage, clamped to 0).
---@return number Current health value
function Player:health()
	return math.max(0, self.max_health - self.damage)
end

--- Returns defence as a percentage (diminishing returns per point).
---@return number Defence percentage
function Player:defense_percent()
	return stats.calculate_percent(self.defense, "defence")
end

--- Returns recovery bonus as a percentage (diminishing returns per point).
---@return number Recovery percentage bonus
function Player:recovery_percent()
	return stats.calculate_percent(self.recovery, "recovery")
end

--- Returns critical chance as a percentage (diminishing returns per point).
---@return number Critical chance percentage
function Player:critical_percent()
	return stats.calculate_percent(self.critical_chance, "critical")
end

--- Applies damage to player, transitioning to hit or death state.
--- Ignored if amount <= 0, player is invincible, or already in hit state.
--- When blocking and facing the source: drains stamina proportional to damage,
--- applies knockback, and stays in block state. Guard breaks if out of stamina.
--- Perfect block: if timed correctly, no stamina cost and enemy receives on_perfect_blocked callback.
---@param amount number Damage amount to apply
---@param source_x number|nil X position of damage source (for shield check)
---@param source_enemy table|nil Enemy that dealt the damage (for perfect block callback)
function Player:take_damage(amount, source_x, source_enemy)
	if amount <= 0 then return end
	if self:is_invincible() then return end
	if self.state == self.states.hit then return end

	-- Shield check: block damage from front when in block or block_move state
	local blocked, _guard_break, perfect = shield.try_block(self, amount, source_x)
	if blocked then
		-- Perfect block: show text effect and notify enemy for custom reaction
		if perfect then
			Effects.create_perfect_block_text(self.x, self.y)
			if source_enemy and source_enemy.on_perfect_blocked then
				source_enemy:on_perfect_blocked(self)
			end
		end
		return
	end

	-- Apply defence reduction
	local reduction = 1 - (self:defense_percent() / 100)
	amount = amount * reduction

	self.damage = math.min(self.damage + amount, self.max_health)
	audio.play_squish_sound()
	if self:health() > 0 then
		self:set_state(self.states.hit)
	else
		self:set_state(self.states.death)
	end
end

--- Teleports the player to the specified position and updates collision grid.
--- Also resets last_safe_position to prevent immediate re-triggering of recovery.
---@param x number World x coordinate (tile units)
---@param y number World y coordinate (tile units)
function Player:set_position(x, y)
	self.x = x
	self.y = y
	self.last_safe_position.x = x
	self.last_safe_position.y = y
	world.sync_position(self)
end

--- Transitions the player to a new state, calling the state's start function.
--- Does nothing if already in the specified state.
---@param state table A state object with start, input, update, draw functions
function Player:set_state(state)
	if self.state == state then return end
	assert(type(state) == "table" and
	       type(state.start) == "function" and
	       type(state.input) == "function" and
	       type(state.update) == "function" and
	       type(state.draw) == "function",
	       "Invalid state: must have start, input, update, draw functions")
	self.state = state
	self.state.start(self)
end

--- Renders the player using the current state's draw function.
--- Also draws debug bounding box if enabled in config.
function Player:draw()
	if self:is_invincible() then
		canvas.set_global_alpha(0.75 + 0.25 * math.sin(self.invincible_time * 20))
	end

	self.state.draw(self)

	if self:is_invincible() then
		canvas.set_global_alpha(1)
	end

	if config.bounding_boxes == true then
		canvas.set_color("#FF0000")
		canvas.draw_rect((self.x + self.box.x) * sprites.tile_size, (self.y + self.box.y) * sprites.tile_size,
			self.box.w * sprites.tile_size, self.box.h * sprites.tile_size)
	end
end

--- Processes player input by delegating to the current state's input handler.
function Player:input()
	self.state.input(self)
	if controls.swap_ability_pressed() then
		local name = self:next_projectile()
		if name then
			audio.play_swap_sound()
			Effects.create_text(self.x, self.y, name)
		end
	end
end

--- Updates player physics, state logic, collision detection, and animation.
--- Should be called once per frame.
function Player:update(dt)
	self.pressure_plate_lift = 0  -- Clear before pressure plates set it
	self.invincible_time = math.max(0, self.invincible_time - dt)
	self.state.update(self, dt)

	self.animation.flipped = self.direction
	self.animation:play(dt)  -- Self-managing delta-time based animation
	self.dash_cooldown = self.dash_cooldown - dt
	self.attack_cooldown = self.attack_cooldown - dt
	self.throw_cooldown = self.throw_cooldown - dt

	-- Stamina regeneration (after cooldown period, reduced while fatigued or blocking)
	self.stamina_regen_timer = self.stamina_regen_timer + dt
	local is_blocking = self.state == self.states.block or self.state == self.states.block_move
	if self.stamina_regen_timer >= self.stamina_regen_cooldown and self.stamina_used > 0 then
		local is_fatigued = self:is_fatigued()
		local is_slowed = is_fatigued or is_blocking
		local regen_multiplier = is_slowed and FATIGUE_REGEN_MULTIPLIER or 1
		-- Recovery bonus doubled while fatigued (helps escape fatigue faster)
		local recovery_percent = self:recovery_percent()
		if is_fatigued then
			recovery_percent = recovery_percent * 2
		end
		local recovery_bonus = 1 + (recovery_percent / 100)
		self.stamina_used = math.max(0, self.stamina_used - self.stamina_regen_rate * regen_multiplier * recovery_bonus * dt)
	end

	-- Perfect block cooldown decrement (only outside block states)
	if not is_blocking then
		shield.update_cooldown(self, dt)
	end

	-- Check for fatigue state transition (show "TIRED" text when entering fatigue)
	local is_now_fatigued = self:is_fatigued()
	if is_now_fatigued and not self.was_fatigued then
		Effects.create_fatigue_text(self.x, self.y)
	end
	self.was_fatigued = is_now_fatigued

	-- Spawn fatigue particles while fatigued
	if is_now_fatigued then
		self.fatigue_particle_timer = self.fatigue_particle_timer + dt
		while self.fatigue_particle_timer >= FATIGUE_PARTICLE_INTERVAL do
			self.fatigue_particle_timer = self.fatigue_particle_timer - FATIGUE_PARTICLE_INTERVAL
			Effects.create_fatigue_particle(self.x + 0.5, self.y + 0.5)
		end
	else
		self.fatigue_particle_timer = 0
	end

	self.x = self.x + (self.vx * dt)
	self.y = self.y + (self.vy * dt)
	local cols = world.move(self, self._cols)
	combat.update(self)

	-- Check for collisions
	common.check_ground(self, cols, dt)

	-- Clear drop-through flag: either by distance OR by timer expiry
	if self.wants_drop_through then
		local player_top = self.y + self.box.y
		local cleared_by_distance = self.drop_through_y and player_top > self.drop_through_y + 0.5

		-- Decrement timer
		if self.drop_through_timer then
			self.drop_through_timer = self.drop_through_timer - dt
		end
		local cleared_by_timer = self.drop_through_timer and self.drop_through_timer <= 0

		if cleared_by_distance or cleared_by_timer then
			self.wants_drop_through = false
			self.drop_through_y = nil
			self.drop_through_timer = nil
		end
	end

	common.check_ladder(self, cols)
	common.check_map_transition(self, cols)
	common.check_hit(self, cols)
end

return Player
