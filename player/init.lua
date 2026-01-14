local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local common = require('player.common')
local Animation = require('Animation')
local Projectile = require('Projectile')
local controls = require('controls')

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
	hammer = require('player.hammer'),
	throw = require('player.throw'),
	hit = require('player.hit'),
	death = require('player.death')
}

-- Expose states for direct reference
Player.states = states

--- Creates a new player instance.
--- @return table A new player object
function Player.new()
	local self = setmetatable({}, Player)

	-- Player Health
	self.max_health = 3
	self.damage = 0
	self.invincible_time = 0

	-- Position and velocity
	self.x = 2
	self.y = 2
	self.vx = 0
	self.vy = 0
	self.box = { w = 0.7, h = 0.85, x = 0.15, y = 0.15 }
	self.is_player = true

	-- Movement
	self.speed = 6
	self.air_speed = self.speed
	self.direction = 1
	self.is_grounded = true
	self.ground_normal = { x = 0, y = -1 }

	-- Jumping
	self.jumps = 2
	self.max_jumps = 2
	self.is_air_jumping = false
	self.coyote_time = 0

	-- Wall movement
	self.has_wall_slide = true
	self.wall_direction = 0
	self.wall_jump_dir = 0

	-- Climbing
	self.can_climb = false
	self.is_climbing = false
	self.current_ladder = nil
	self.on_ladder_top = false
	self.standing_on_ladder_top = false
	self.climb_touching_ground = false
	self.climb_speed = self.speed / 2

	-- Combat
	self.attacks = 3
	self.attack_cooldown = 0

	-- Dash
	self.dash_cooldown = 0
	self.dash_speed = self.speed * 3
	self.has_dash = true

	-- Animation
	self.animation = Animation.new(common.animations.IDLE)

	-- State machine
	self.state = nil
	self.states = states  -- Reference for state transitions

	-- Projectile Selected
	self.projectile_options = { Projectile.get_axe(), Projectile.get_shuriken() }
	
	self.projectile_ix = 1
	self.projectile = self.projectile_options[self.projectile_ix]

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
		queued = false
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
		remaining_time = 0
	}
	self.hit_state = {
		knockback_speed = 2,
		remaining_time = 0
	}

	-- Register with collision system
	world.add_collider(self)

	-- Initialize default state
	self:set_state(states.idle)

	return self
end

function Player:next_projectile()
	self.projectile_ix = self.projectile_ix + 1
	if self.projectile_ix > #self.projectile_options then self.projectile_ix = 1 end
	self.projectile = self.projectile_options[self.projectile_ix]
end

function Player:is_invincible()
	return self.invincible_time > 0
end

function Player:health()
	return math.max(0, self.max_health - self.damage)
end

function Player:take_damage(amount)
	if amount <= 0 then return end
	self.damage = self.damage + amount
	if self:health() > 0 then
		self:set_state(self.states.hit)
	else
		self:set_state(self.states.death)
	end
end

--- Teleports the player to the specified position and updates collision grid.
--- @param x number World x coordinate
--- @param y number World y coordinate
function Player:set_position(x, y)
	self.x = x
	self.y = y
	world.sync_position(self)
end

--- Transitions the player to a new state, calling the state's start function.
--- Does nothing if already in the specified state.
--- @param state table A state object with start, input, update, draw functions
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
	self.state.draw(self)

	if config.bounding_boxes == true then
		canvas.set_color("#FF0000")
		canvas.draw_rect((self.x + self.box.x) * sprites.tile_size, (self.y + self.box.y) * sprites.tile_size,
			self.box.w * sprites.tile_size, self.box.h * sprites.tile_size)
	end
end

--- Processes player input by delegating to the current state's input handler.
function Player:input()
	self.state.input(self)
	if controls.next_projectile_pressed() then self:next_projectile() end
end

--- Updates player physics, state logic, collision detection, and animation.
--- Should be called once per frame.
function Player:update(dt)
	self.invincible_time = math.max(0, self.invincible_time - dt)
	self.state.update(self, dt)

	self.animation.flipped = self.direction
	self.animation:play(dt)  -- Self-managing delta-time based animation
	self.dash_cooldown = self.dash_cooldown - dt
	self.attack_cooldown = self.attack_cooldown - dt

	self.x = self.x + (self.vx * dt)
	self.y = self.y + (self.vy * dt)
	local cols = world.move(self)

	-- Check for collisions
	common.check_ground(self, cols, dt)
	common.check_ladder(self, cols)
	common.check_hit(self, cols)
end

return Player
