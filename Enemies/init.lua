local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local combat = require('combat')
local config = require('config')
local common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')
local Collectible = require('Collectible')

local Enemy = {}
Enemy.__index = Enemy
Enemy.all = {}
Enemy.next_id = 1
Enemy.types = {}

-- Shield collision debounce: 3 frames between contact hits to prevent rapid stamina drain
local SHIELD_HIT_COOLDOWN = 3 / 60

-- Skip expensive updates beyond this many tiles off-screen
local UPDATE_CULL_MARGIN = 8

-- Debug color constants (avoid string allocation each frame)
local DEBUG_COLOR_CYAN = "#00FFFF"
local DEBUG_COLOR_MAGENTA = "#FF00FF"

--- Registers an enemy type definition.
---@param key string Type identifier (e.g., "ratto")
---@param definition table Enemy type definition from type module
function Enemy.register(key, definition)
	Enemy.types[key] = definition
end

--- Spawns an enemy of the given type at position.
---@param type_key string Enemy type identifier
---@param x number X position in tiles
---@param y number Y position in tiles
---@param spawn_data table|nil Optional spawn data with waypoints or other properties
---@return table The created enemy instance
function Enemy.spawn(type_key, x, y, spawn_data)
	local definition = Enemy.types[type_key]
	if not definition then
		error("Unknown enemy type: " .. type_key)
	end

	local self = setmetatable({}, Enemy)
	self.id = type_key .. "_" .. Enemy.next_id
	Enemy.next_id = Enemy.next_id + 1

	-- Position and physics (apply spawn offset if defined)
	local offset = definition.spawn_offset
	self.x = x + (offset and offset.x or 0)
	self.y = y + (offset and offset.y or 0)
	self.vx = 0
	self.vy = 0
	self.direction = (spawn_data and spawn_data.flip) and 1 or -1  -- Face left by default, right if flip=true
	self.is_grounded = false
	self.ground_normal = { x = 0, y = -1 }

	-- Type-specific properties
	self.type_key = type_key
	self.box = definition.box
	self.gravity = definition.gravity or 1.5
	self.max_fall_speed = definition.max_fall_speed or 20
	self.rotate_to_slope = definition.rotate_to_slope or false

	-- Store waypoint data if provided (for patrolling enemies)
	if spawn_data and spawn_data.waypoints then
		self.waypoint_a = spawn_data.waypoints.a
		self.waypoint_b = spawn_data.waypoints.b
		self.target_waypoint = spawn_data.waypoints.b  -- Start moving toward second waypoint
	end

	-- State machine
	self.states = definition.states
	self.state = self.states[definition.initial_state] or self.states.idle

	-- Animation
	self.animation = nil
	self.state.start(self, definition)

	-- Combat
	self.max_health = definition.max_health or 1
	self.health = self.max_health
	self.damage = definition.damage or 1
	self.armor = definition.armor or 0
	self.damages_shield = definition.damages_shield or false
	self.directional_shield = definition.directional_shield or false  -- Phasing enemies use direction-based shield check
	self.shield_hit_cooldown = 0  -- Debounce timer for shield contact damage
	self.marked_for_destruction = false

	-- Copy custom get_armor function if defined
	if definition.get_armor then
		self.get_armor = definition.get_armor
	end

	-- Copy custom on_hit function if defined
	if definition.on_hit then
		self.on_hit = definition.on_hit
	end

	-- Mark as enemy (for collision filtering)
	self.is_enemy = true
	-- Persistent collision result table (avoids per-frame allocation)
	self._cols = {
		ground = false, ceiling = false, wall_left = false, wall_right = false,
		ground_normal = { x = 0, y = -1 }, shield = false, shield_owner = nil,
		triggers = {}
	}

	-- Create physical collider (for ground/wall detection)
	-- Slope-rotating enemies use:
	--   1. Circle collider for smooth slope physics
	--   2. Rotatable world hitbox for accurate player contact detection
	-- Non-slope enemies use a single rectangle for both purposes.
	if self.rotate_to_slope then
		self.shape = world.add_circle_collider(self)
		self.hitbox = world.add_hitbox(self)  -- Rotates with sprite for contact damage
	else
		self.shape = world.add_collider(self)
	end

	-- Register in pool
	Enemy.all[self] = true

	-- Add to combat hitbox system (axis-aligned, for weapon sweep detection)
	combat.add(self)

	return self
end

-- Module-level table to avoid allocation each frame
local to_remove = {}

--- Updates physics and collision for ground-based enemies.
---@param enemy table The enemy instance
---@param dt number Delta time in seconds
local function update_ground_enemy(enemy, dt)
	common.apply_gravity(enemy, dt)
	enemy.x = enemy.x + enemy.vx * dt
	enemy.y = enemy.y + enemy.vy * dt

	local cols = world.move(enemy, enemy._cols)
	enemy:check_ground(cols)
	enemy.wall_left = cols.wall_left
	enemy.wall_right = cols.wall_right

	-- Only check edge in direction of movement (saves 1-2 collision queries per frame)
	if enemy.is_grounded and enemy.vx ~= 0 then
		local probe_y = enemy.y + enemy.box.y + enemy.box.h + 0.5
		if enemy.vx < 0 then
			enemy.edge_left = not world.point_has_ground(enemy.x + enemy.box.x - 0.1, probe_y)
			enemy.edge_right = false
		else
			enemy.edge_left = false
			enemy.edge_right = not world.point_has_ground(enemy.x + enemy.box.x + enemy.box.w + 0.1, probe_y)
		end
	else
		enemy.edge_left = false
		enemy.edge_right = false
	end
end

--- Updates physics for flying enemies (no gravity or collision).
---@param enemy table The enemy instance
---@param dt number Delta time in seconds
local function update_flying_enemy(enemy, dt)
	enemy.x = enemy.x + enemy.vx * dt
	enemy.y = enemy.y + enemy.vy * dt
	world.sync_position(enemy)
	enemy.is_grounded = false
	enemy.wall_left = false
	enemy.wall_right = false
	enemy.edge_left = false
	enemy.edge_right = false
end

--- Performs full update for enemies within camera range.
---@param enemy table The enemy instance
---@param dt number Delta time in seconds
---@param player table The player object
local function update_active_enemy(enemy, dt, player)
	if enemy.gravity > 0 then
		update_ground_enemy(enemy, dt)
	else
		update_flying_enemy(enemy, dt)
	end

	common.update_slope_rotation(enemy, dt)

	enemy._cached_y_offset = common.get_slope_y_offset(enemy)
	combat.update(enemy, enemy._cached_y_offset)
	if enemy.hitbox then
		world.update_hitbox(enemy, enemy._cached_y_offset)
	end

	enemy.target_player = player
	if player then
		enemy:check_player_overlap(player)
	end

	enemy.state.update(enemy, dt)
end

--- Updates all enemies.
---@param dt number Delta time in seconds
---@param player table The player object (for overlap detection)
---@param camera table Camera instance for update culling
function Enemy.update(dt, player, camera)
	for i = 1, #to_remove do to_remove[i] = nil end

	local enemy = next(Enemy.all)
	while enemy do
		enemy.pressure_plate_lift = 0
		enemy.shield_hit_cooldown = math.max(0, enemy.shield_hit_cooldown - dt)
		enemy.camera = camera
		if enemy.animation then
			enemy.animation:play(dt)
		end

		if camera:is_visible(enemy, sprites.tile_size, UPDATE_CULL_MARGIN) then
			update_active_enemy(enemy, dt, player)
		else
			-- Keep combat hitbox synced for weapon queries (skip physics/state logic)
			enemy._cached_y_offset = 0
			combat.update(enemy, 0)
		end

		if enemy.marked_for_destruction then
			to_remove[#to_remove + 1] = enemy
		end
		enemy = next(Enemy.all, enemy)
	end

	for i = 1, #to_remove do
		local e = to_remove[i]
		world.remove_collider(e)
		world.remove_hitbox(e)
		Enemy.all[e] = nil
	end
end

--- Draws all enemies and their debug bounding boxes when config.bounding_boxes is enabled.
---@param camera table Camera instance for viewport culling
function Enemy.draw(camera)
	local debug_mode = config.bounding_boxes
	local ts = sprites.tile_size
	-- Only save/restore canvas state when drawing debug visuals (avoid overhead in release)
	if debug_mode then canvas.save() end

	local enemy = next(Enemy.all)
	while enemy do
		if camera:is_visible(enemy, ts) then
			enemy.state.draw(enemy)

			if debug_mode then
				local box = enemy.box
				local box_x = (enemy.x + box.x) * ts
				local box_y = (enemy.y + box.y) * ts
				local box_w = box.w * ts
				local box_h = box.h * ts

				-- Draw physics shape (cyan) - for world collision
				canvas.set_color(DEBUG_COLOR_CYAN)
				if enemy.shape and enemy.shape.is_circle then
					canvas.draw_circle(box_x + box_w / 2, box_y + box_h / 2, enemy.shape.radius)
				else
					canvas.draw_rect(box_x, box_y, box_w, box_h)
				end

				-- Draw combat hitbox (magenta) - rotates with sprite
				if enemy.hitbox then
					canvas.set_color(DEBUG_COLOR_MAGENTA)
					local y_offset = enemy._cached_y_offset or 0
					local rotation = -(enemy.slope_rotation or 0)

					if rotation ~= 0 then
						canvas.save()
						canvas.translate(box_x + box_w / 2, box_y + y_offset + box_h / 2)
						canvas.rotate(rotation)
						canvas.draw_rect(-box_w / 2, -box_h / 2, box_w, box_h)
						canvas.restore()
					else
						canvas.draw_rect(box_x, box_y + y_offset, box_w, box_h)
					end
				end
			end
		end
		enemy = next(Enemy.all, enemy)
	end

	if debug_mode then canvas.restore() end
end

--- Clears all enemies and their collision shapes.
--- Call when reloading levels to prevent orphaned colliders.
function Enemy.clear()
	local enemy = next(Enemy.all)
	while enemy do
		world.remove_collider(enemy)
		world.remove_hitbox(enemy)
		combat.remove(enemy)
		enemy = next(Enemy.all, enemy)
	end
	Enemy.all = {}
end

--- Processes collision flags to update grounded state.
---@param cols table Collision flags from world.move()
function Enemy:check_ground(cols)
	if cols.ground then
		self.is_grounded = true
		self.ground_normal = cols.ground_normal
		self.vy = 0
	else
		self.is_grounded = false
	end
end

--- Checks if enemy overlaps with player and triggers contact damage.
--- Uses world hitbox system (not combat system) because contact damage needs
--- the rotated hitbox for slope-following enemies, while combat.query_rect()
--- uses axis-aligned boxes for weapon sweeps.
---@param player table The player object
function Enemy:check_player_overlap(player)
	local player_shape = world.shape_map[player]
	if not player_shape then return end

	-- Use combat hitbox if available, otherwise fall back to physics shape
	local enemy_shape = self.hitbox or self.shape
	if not enemy_shape then return end

	-- Check shield collision first (independent of body overlap).
	-- Ground enemies get pushed away by physics before this runs, so their
	-- shape no longer overlaps the shield. Use the physics flag from world.move
	-- to detect the contact, with shape-overlap fallback for flying enemies.
	if self.damages_shield and self.shield_hit_cooldown <= 0 then
		local shield_hit = false

		-- Phasing enemies (ghosts) use directional check since they ignore collision shapes
		if self.directional_shield then
			local is_blocking = player.state == player.states.block or player.state == player.states.block_move
			if is_blocking then
				local enemy_on_left = self.x < player.x
				local player_facing_left = player.direction == -1
				shield_hit = enemy_on_left == player_facing_left
			end
		else
			-- Non-phasing enemies: physics flag + shape overlap fallback
			local shield_shape = world.shield_map[player]
			shield_hit = (self._cols.shield and self._cols.shield_owner == player)
				or (shield_shape and enemy_shape:collidesWith(shield_shape))
		end

		if shield_hit then
			player:take_damage(self.damage, self.x)
			self.shield_hit_cooldown = SHIELD_HIT_COOLDOWN
			self.hit_shield = true  -- Flag for states to react to shield collision
			return  -- Don't also check body collision
		end
	end
	self.hit_shield = false

	-- Body collision (only reached if shield didn't absorb the hit)
	local collides, _ = enemy_shape:collidesWith(player_shape)
	if not collides then return end

	-- No shield block - take damage
	player:take_damage(self.damage, self.x)
end

--- Returns the enemy's current armor value.
--- Can be overridden per-enemy for dynamic armor (e.g., spike_slug defending).
---@return number armor value
function Enemy:get_armor()
	return self.armor
end

--- Called when enemy is hit by something.
---@param source_type string "player", "weapon", or "projectile"
---@param source table Hit source with optional .damage (number), .x (number), .vx (number)
function Enemy:on_hit(source_type, source)
	if self.invulnerable then return end

	local damage = (source and source.damage) or 1

	-- Apply armor reduction (minimum 0 damage)
	damage = math.max(0, damage - self:get_armor())

	-- Create floating damage text (centered on enemy hitbox)
	Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage)

	if damage <= 0 then
		audio.play_solid_sound()
		return
	end

	self.health = self.health - damage
	audio.play_squish_sound()

	-- Determine knockback direction from hit source
	if source and source.vx then
		-- Projectile: knockback in direction projectile was traveling
		self.hit_direction = source.vx > 0 and 1 or -1
	elseif source and source.x then
		-- Player/other: knockback away from source
		self.hit_direction = source.x < self.x and 1 or -1
	else
		self.hit_direction = -1
	end

	if self.health <= 0 then
		self:die()
	elseif (source_type == "projectile" or source_type == "weapon") and self.states.hit then
		self:set_state(self.states.hit)
	end
end

--- Called when enemy health reaches 0.
function Enemy:die()
	-- Remove colliders immediately so nothing else can hit it
	world.remove_collider(self)
	world.remove_hitbox(self)
	combat.remove(self)
	self.shape = nil
	self.hitbox = nil

	local definition = Enemy.types[self.type_key]
	audio.play_death_sound(definition.death_sound)

	-- Spawn loot at enemy center (explodes away from player)
	if definition.loot and self.target_player then
		local cx = self.x + self.box.x + self.box.w / 2
		local cy = self.y + self.box.y + self.box.h / 2
		Collectible.spawn_loot(cx, cy, definition.loot, self.target_player)
	end

	-- Transition to death state if available, otherwise destroy immediately
	if self.states.death then
		self:set_state(self.states.death)
	else
		self.marked_for_destruction = true
	end
end

--- Changes the enemy's state.
---@param new_state table State object with start, update, draw functions
function Enemy:set_state(new_state)
	self.state = new_state
	local definition = Enemy.types[self.type_key]
	self.state.start(self, definition)
end

return Enemy
