local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local combat = require('combat')
local config = require('config')
local common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')

local Enemy = {}
Enemy.__index = Enemy
Enemy.all = {}
Enemy.next_id = 1
Enemy.types = {}

--- Registers an enemy type definition.
--- @param key string Type identifier (e.g., "ratto")
--- @param definition table Enemy type definition from type module
function Enemy.register(key, definition)
	Enemy.types[key] = definition
end

--- Spawns an enemy of the given type at position.
--- @param type_key string Enemy type identifier
--- @param x number X position in tiles
--- @param y number Y position in tiles
--- @return table The created enemy instance
function Enemy.spawn(type_key, x, y)
	local definition = Enemy.types[type_key]
	if not definition then
		error("Unknown enemy type: " .. type_key)
	end

	local self = setmetatable({}, Enemy)
	self.id = type_key .. "_" .. Enemy.next_id
	Enemy.next_id = Enemy.next_id + 1

	-- Position and physics
	self.x = x
	self.y = y
	self.vx = 0
	self.vy = 0
	self.direction = -1  -- Face left by default
	self.is_grounded = false
	self.ground_normal = { x = 0, y = -1 }

	-- Type-specific properties
	self.type_key = type_key
	self.box = definition.box
	self.gravity = definition.gravity or 1.5
	self.max_fall_speed = definition.max_fall_speed or 20
	self.rotate_to_slope = definition.rotate_to_slope or false

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
	self.marked_for_destruction = false

	-- Copy custom get_armor function if defined
	if definition.get_armor then
		self.get_armor = definition.get_armor
	end

	-- Mark as enemy (for collision filtering)
	self.is_enemy = true

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

--- Updates all enemies.
--- @param dt number Delta time in seconds
--- @param player table The player object (for overlap detection)
function Enemy.update(dt, player)
	-- Clear module-level table instead of allocating new one
	for i = 1, #to_remove do to_remove[i] = nil end

	local enemy = next(Enemy.all)
	while enemy do
		common.apply_gravity(enemy, dt)

		-- Apply velocity
		enemy.x = enemy.x + enemy.vx * dt
		enemy.y = enemy.y + enemy.vy * dt

		-- Resolve collisions
		local cols = world.move(enemy)
		enemy:check_ground(cols)
		enemy.wall_left = cols.wall_left
		enemy.wall_right = cols.wall_right

		local probe_y = enemy.y + enemy.box.y + enemy.box.h + 0.5  -- tiles below feet
		enemy.edge_left = enemy.is_grounded and not world.point_has_ground(enemy.x + enemy.box.x - 0.1, probe_y)
		enemy.edge_right = enemy.is_grounded and not world.point_has_ground(enemy.x + enemy.box.x + enemy.box.w + 0.1, probe_y)

		-- Update slope rotation (visual only)
		common.update_slope_rotation(enemy, dt)

		-- Update combat hitbox position and rotation
		local y_offset = common.get_slope_y_offset(enemy)
		combat.update(enemy, y_offset)
		if enemy.hitbox then
			world.update_hitbox(enemy, y_offset)
		end

		-- Store player reference for state logic
		enemy.target_player = player

		-- Check for player overlap
		if player then
			enemy:check_player_overlap(player)
		end

		-- Update state
		enemy.state.update(enemy, dt)

		-- Update animation
		if enemy.animation then
			enemy.animation:play(dt)
		end

		-- Check for destruction
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
function Enemy.draw()
	canvas.save()
	local enemy = next(Enemy.all)
	while enemy do
		enemy.state.draw(enemy)

		-- Draw debug shapes
		if config.bounding_boxes then
			-- Draw physics shape (cyan) - for world collision
			canvas.set_color("#00FFFF")  -- Cyan
			if enemy.shape and enemy.shape.is_circle then
				-- Circle collider
				local cx = (enemy.x + enemy.box.x + enemy.box.w / 2) * sprites.tile_size
				local cy = (enemy.y + enemy.box.y + enemy.box.h / 2) * sprites.tile_size
				canvas.draw_circle(cx, cy, enemy.shape.radius)
			else
				-- Rectangle collider
				canvas.draw_rect(
					(enemy.x + enemy.box.x) * sprites.tile_size,
					(enemy.y + enemy.box.y) * sprites.tile_size,
					enemy.box.w * sprites.tile_size,
					enemy.box.h * sprites.tile_size)
			end

			-- Draw combat hitbox (magenta) - rotates with sprite
			if enemy.hitbox then
				canvas.set_color("#FF00FF")  -- Magenta
				local y_offset = common.get_slope_y_offset(enemy)
				local box_x = (enemy.x + enemy.box.x) * sprites.tile_size
				local box_y = (enemy.y + enemy.box.y) * sprites.tile_size + y_offset
				local box_w = enemy.box.w * sprites.tile_size
				local box_h = enemy.box.h * sprites.tile_size
				local rotation = -(enemy.slope_rotation or 0)  -- Negate to match hitbox

				if rotation ~= 0 then
					canvas.save()
					local cx = box_x + box_w / 2
					local cy = box_y + box_h / 2
					canvas.translate(cx, cy)
					canvas.rotate(rotation)
					canvas.draw_rect(-box_w / 2, -box_h / 2, box_w, box_h)
					canvas.restore()
				else
					canvas.draw_rect(box_x, box_y, box_w, box_h)
				end
			end
		end
		enemy = next(Enemy.all, enemy)
	end
	canvas.restore()
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
--- @param cols table Collision flags from world.move()
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
--- @param player table The player object
function Enemy:check_player_overlap(player)
	local player_shape = world.shape_map[player]
	if not player_shape then return end

	-- Use combat hitbox if available, otherwise fall back to physics shape
	local enemy_shape = self.hitbox or self.shape
	if not enemy_shape then return end

	local collides, _ = enemy_shape:collidesWith(player_shape)
	if collides then
		player:take_damage(self.damage)
	end
end

--- Returns the enemy's current armor value.
--- Can be overridden per-enemy for dynamic armor (e.g., spike_slug defending).
--- @return number armor value
function Enemy:get_armor()
	return self.armor
end

--- Called when enemy is hit by something.
--- @param source_type string "player", "weapon", or "projectile"
--- @param source table Hit source with optional .damage (number), .x (number), .vx (number)
function Enemy:on_hit(source_type, source)
	local damage = 1
	if source and source.damage then
		damage = source.damage
	end

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

	-- Transition to death state if available, otherwise destroy immediately
	if self.states.death then
		self:set_state(self.states.death)
	else
		self.marked_for_destruction = true
	end
end

--- Changes the enemy's state.
--- @param new_state table State object with start, update, draw functions
function Enemy:set_state(new_state)
	self.state = new_state
	local definition = Enemy.types[self.type_key]
	self.state.start(self, definition)
end

return Enemy
