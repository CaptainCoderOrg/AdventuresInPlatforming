local common = require('player.common')
local sprites = require('sprites')
local Animation = require('Animation')
local Prop = require('Prop')
local config = require('config')
local canvas = require('canvas')
local audio = require('audio')
local combat = require('combat')
local world = require('world')

local hammer = { name = "hammer" }

-- Hammer hitbox dimensions (centered relative to player box)
local HAMMER_WIDTH = 1.15
local HAMMER_HEIGHT = 1.1
local HAMMER_Y_OFFSET = -0.1  -- Center vertically relative to player box

-- Active frames for hammer hitbox (impact frames)
-- Hammer has 7 frames (0-6) at 150ms each
-- Frames 2-5 = swing through impact (600ms active window)
local MIN_ACTIVE_FRAME = 2
local MAX_ACTIVE_FRAME = 5

--- Get the hammer hitbox if on active frames, nil otherwise
---@param player table The player object
---@return table|nil Hitbox with x, y, w, h in tile coordinates
local function get_hammer_hitbox(player)
	if player.animation.frame < MIN_ACTIVE_FRAME or player.animation.frame > MAX_ACTIVE_FRAME then
		return nil
	end
	return common.create_melee_hitbox(player, HAMMER_WIDTH, HAMMER_HEIGHT, HAMMER_Y_OFFSET)
end

--- Check for enemy hits with the hammer
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
local function check_hammer_hits(player, hitbox)
	local hits = combat.query_rect(hitbox.x, hitbox.y, hitbox.w, hitbox.h, function(entity)
		return entity.is_enemy
			and entity.shape
			and not player.hammer_state.hit_enemies[entity]
	end)

	for _, enemy in ipairs(hits) do
		enemy:on_hit("weapon", { damage = 5, x = player.x })
		player.hammer_state.hit_enemies[enemy] = true
	end
end

--- Check for button hits with the hammer
---@param player table The player object
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
local function check_button_hits(player, hitbox)
	-- Only check if we haven't already hit a button this swing
	if not player.hammer_state.hit_button then
		local button = Prop.check_hit("button", hitbox, function(prop)
			return not prop.is_pressed
		end)
		if button then
			button.definition.press(button)
			player.hammer_state.hit_button = true
		end
	end
end


--- Initializes hammer attack state. Sets animation, timing, and clears input queue.
--- Removes shield if transitioning from block/block_move state.
---@param player table The player object
function hammer.start(player)
	world.remove_shield(player)
	player.animation = Animation.new(common.animations.HAMMER)
	player.hammer_state.remaining_time = (common.animations.HAMMER.frame_count * common.animations.HAMMER.ms_per_frame) / 1000
	player.hammer_state.hit_button = false
	-- Clear existing table instead of allocating new one
	local hit_enemies = player.hammer_state.hit_enemies
	for k in pairs(hit_enemies) do hit_enemies[k] = nil end
	player.hammer_state.sound_played = false
	common.clear_input_queue(player)
	audio.play_hammer_grunt()
end

--- Updates hammer state. Checks for button hits, locks movement, and handles timing.
---@param player table The player object
---@param dt number Delta time in seconds
function hammer.update(player, dt)
	-- Compute hitbox once and pass to both check functions
	local hitbox = get_hammer_hitbox(player)
	if hitbox then
		check_hammer_hits(player, hitbox)
		check_button_hits(player, hitbox)
	end
	player.vx = 0
	player.vy = 0
	player.hammer_state.remaining_time = player.hammer_state.remaining_time - dt
	if player.animation.frame >= 3 and not player.hammer_state.sound_played then
		audio.play_hammer_hit()
		player.hammer_state.sound_played = true
	end
	if player.hammer_state.remaining_time < 0 then
		if not common.process_input_queue(player) then
			player:set_state(player.states.idle)
		end
	end
end

--- Handles input during hammer state. Queues inputs for later execution.
---@param player table The player object
function hammer.input(player)
	common.queue_inputs(player)
end

--- Renders the player in hammer animation with optional debug hitbox.
---@param player table The player object
function hammer.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)

	local hitbox = get_hammer_hitbox(player)
	if config.bounding_boxes and hitbox then
		canvas.set_color("#FF00FF")
		canvas.draw_rect(
			hitbox.x * sprites.tile_size,
			hitbox.y * sprites.tile_size,
			hitbox.w * sprites.tile_size,
			hitbox.h * sprites.tile_size)
	end
end

return hammer
