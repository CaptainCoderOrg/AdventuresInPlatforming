local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local config = require('config')

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

	-- State machine
	self.states = definition.states
	self.state = self.states.idle

	-- Animation
	self.animation = nil
	self.state.start(self, definition)

	-- Combat
	self.max_health = definition.max_health or 1
	self.health = self.max_health
	self.damage = definition.damage or 1
	self.marked_for_destruction = false

	-- Mark as enemy (for collision filtering)
	self.is_enemy = true

	-- Create physical collider (for ground/wall detection)
	self.shape = world.add_collider(self)

	-- Register in pool
	Enemy.all[self] = true

	return self
end

--- Updates all enemies.
--- @param dt number Delta time in seconds
--- @param player table The player object (for overlap detection)
function Enemy.update(dt, player)
	local to_remove = {}

	for enemy, _ in pairs(Enemy.all) do
		-- Apply gravity
		enemy.vy = math.min(enemy.max_fall_speed, enemy.vy + enemy.gravity)

		-- Apply velocity
		enemy.x = enemy.x + enemy.vx * dt
		enemy.y = enemy.y + enemy.vy * dt

		-- Resolve collisions
		local cols = world.move(enemy)
		enemy:check_ground(cols)
		enemy.wall_left = cols.wall_left
		enemy.wall_right = cols.wall_right

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
			table.insert(to_remove, enemy)
		end
	end

	-- Cleanup destroyed enemies
	for _, enemy in ipairs(to_remove) do
		world.remove_collider(enemy)
		Enemy.all[enemy] = nil
	end
end

--- Draws all enemies.
function Enemy.draw()
	canvas.save()
	for enemy, _ in pairs(Enemy.all) do
		enemy.state.draw(enemy)

		-- Draw debug hitbox in cyan
		if config.bounding_boxes then
			canvas.set_color("#00FFFF")  -- Cyan for enemies
			canvas.draw_rect(
				(enemy.x + enemy.box.x) * sprites.tile_size,
				(enemy.y + enemy.box.y) * sprites.tile_size,
				enemy.box.w * sprites.tile_size,
				enemy.box.h * sprites.tile_size)
		end
	end
	canvas.restore()
end

--- Clears all enemies (for level reloading).
function Enemy.clear()
	for enemy, _ in pairs(Enemy.all) do
		world.remove_collider(enemy)
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

--- Checks if enemy overlaps with player and triggers on_hit.
--- @param player table The player object
function Enemy:check_player_overlap(player)
	local player_shape = world.shape_map[player]
	if not player_shape or not self.shape then return end

	local collides, _ = self.shape:collidesWith(player_shape)
	if collides then
		self:on_hit("player", player)
	end
end

--- Called when enemy is hit by something.
--- @param source_type string "player", "weapon", or "projectile"
--- @param source table The object that hit this enemy
function Enemy:on_hit(source_type, source)
	-- Determine damage amount from source
	local damage = 1
	if source and source.damage then
		damage = source.damage
	end

	self.health = self.health - damage

	-- Determine knockback direction (opposite of hit source)
	if source then
		if source.vx then
			-- Projectile: knockback in direction projectile was traveling
			self.hit_direction = source.vx > 0 and 1 or -1
		elseif source.x then
			-- Player/other: knockback away from source
			self.hit_direction = source.x < self.x and 1 or -1
		else
			self.hit_direction = -1
		end
	else
		self.hit_direction = -1
	end

	if self.health <= 0 then
		self:die()
	elseif source_type == "projectile" and self.states.hit then
		self:set_state(self.states.hit)
	end
end

--- Called when enemy health reaches 0.
function Enemy:die()
	-- Remove collider immediately so nothing else can hit it
	world.remove_collider(self)
	self.shape = nil

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
