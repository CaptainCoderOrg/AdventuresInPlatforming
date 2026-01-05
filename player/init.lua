local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local common = require('player.common')

local player = {}

-- Load all states
local states = {
	idle = require('player.idle'),
	run = require('player.run'),
	dash = require('player.dash'),
	air = require('player.air'),
	wall_slide = require('player.wall_slide'),
	wall_jump = require('player.wall_jump'),
	attack = require('player.attack'),
}

-- Expose states for direct reference
player.states = states

-- Player properties
player.x = 2
player.vx = 0
player.vy = 0
player.y = 2
player.is_grounded = true
player.box = { w = 0.7, h = 0.85, x = 0.15, y = 0.15 }
player.speed = 6
player.air_speed = player.speed
player.coyote_frames = 0
player.direction = 1
player.jumps = 2
player.max_jumps = 2
player.is_air_jumping = false
player.has_wall_slide = true
player.wall_direction = 0
player.wall_jump_dir = 0
player.ground_normal = { x = 0, y = -1 }
player.state = nil
player.attacks = 3

player.attack_cooldown = 0

player.dash_cooldown = 0
player.dash_speed = player.speed * 3
player.has_dash = true

player.animation = common.animations.IDLE
player.animation.flipped = 1

local t = 0

world.add_collider(player)

--- Teleports the player to the specified position and updates collision grid.
--- @param x number World x coordinate
--- @param y number World y coordinate
function player.set_position(x, y)
	player.x = x
	player.y = y
	world.sync_position(player)
end

--- Transitions the player to a new state, calling the state's start function.
--- Does nothing if already in the specified state.
--- @param state table A state object with start, input, update, draw functions
function player.set_state(state)
	if player.state == state then return end
	assert(type(state) == "table" and
	       type(state.start) == "function" and
	       type(state.input) == "function" and
	       type(state.update) == "function" and
	       type(state.draw) == "function",
	       "Invalid state: must have start, input, update, draw functions")
	player.state = state
	player.state.start(player)
	t = 0
end

--- Renders the player using the current state's draw function.
--- Also draws debug bounding box if enabled in config.
function player.draw()
	player.state.draw(player)

	if config.bounding_boxes == true then
		canvas.set_color("#FF0000")
		canvas.draw_rect((player.x + player.box.x) * sprites.tile_size, (player.y + player.box.y) * sprites.tile_size,
			player.box.w * sprites.tile_size, player.box.h * sprites.tile_size)
	end
end

--- Processes player input by delegating to the current state's input handler.
function player.input()
	player.state.input(player)
end

--- Updates player physics, state logic, collision detection, and animation.
--- Should be called once per frame.
function player.update()
	local dt = canvas.get_delta()
	player.state.update(player, dt)

	player.animation.flipped = player.direction
	player.dash_cooldown = player.dash_cooldown - 1
	player.attack_cooldown = player.attack_cooldown - 1

	player.x = player.x + (player.vx * dt)
	player.y = player.y + (player.vy * dt)
	local cols = world.move(player)

	-- Check for collisions
	common.check_ground(player, cols)

	t = t + 1
	if t % player.animation.speed == 0 then
		player.animation.frame = (player.animation.frame + 1) % player.animation.frame_count
	end
end

-- Initialize default state
player.set_state(states.idle)

return player
