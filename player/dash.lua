local Animation = require('Animation')
local audio = require('audio')
local canvas = require('canvas')
local config = require('config')
local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local weapon_sync = require('player.weapon_sync')

--- Dash state: Player performs a quick horizontal burst of speed.
--- Ignores gravity during dash. Can be cancelled by jumping or changing direction.
--- Uses the charge system on dash_amulet for cooldown (recharges over time).
local dash = { name = "dash" }

local DASH_DURATION = 12 / 60
local GHOST_TRAIL_LIFETIME = 0.25
local GHOST_TRAIL_INTERVAL = 0.05

--------------------------------------------------------------------------------
-- Ghost trail system (fading afterimages during dash)
--------------------------------------------------------------------------------

local ghost_trails = {}

-- Ghost trail table pool (avoids per-spawn allocation)
local ghost_pool = {}
local ghost_pool_count = 0

local function acquire_ghost()
	if ghost_pool_count > 0 then
		local ghost = ghost_pool[ghost_pool_count]
		ghost_pool[ghost_pool_count] = nil
		ghost_pool_count = ghost_pool_count - 1
		return ghost
	end
	return {}
end

local function release_ghost(ghost)
	ghost_pool_count = ghost_pool_count + 1
	ghost_pool[ghost_pool_count] = ghost
end

local function spawn_ghost_trail(player)
	if not player.animation then return end
	local ghost = acquire_ghost()
	ghost.x = player.x
	ghost.y = player.y
	ghost.direction = player.direction
	ghost.definition = player.animation.definition
	ghost.frame = player.animation.frame
	ghost.elapsed = 0
	ghost.lifetime = GHOST_TRAIL_LIFETIME
	ghost_trails[#ghost_trails + 1] = ghost
end

--- Age ghost trail entries and remove expired ones.
---@param dt number Delta time in seconds
function dash.update_ghost_trails(dt)
	local n = #ghost_trails
	local write = 0
	for i = 1, n do
		local ghost = ghost_trails[i]
		ghost.elapsed = ghost.elapsed + dt
		if ghost.elapsed < ghost.lifetime then
			write = write + 1
			ghost_trails[write] = ghost
		else
			release_ghost(ghost)
		end
	end
	for i = write + 1, n do
		ghost_trails[i] = nil
	end
end

--- Draw all active ghost trails with fading alpha.
function dash.draw_ghost_trails()
	for i = 1, #ghost_trails do
		local ghost = ghost_trails[i]
		local alpha = 1 - (ghost.elapsed / ghost.lifetime)
		if alpha > 0 then
			local def = ghost.definition
			local flipped = ghost.direction
			local x = sprites.px(ghost.x)
			local y = sprites.px(ghost.y)

			local x_adjust = 0
			if flipped == 1 then
				x_adjust = def.width
			elseif def.width > config.ui.TILE then
				x_adjust = -config.ui.TILE
			end

			canvas.save()
			canvas.set_global_alpha(alpha * 0.5)
			canvas.translate(x + (x_adjust * config.ui.SCALE), y)
			canvas.scale(-flipped, 1)

			local sheet_frame = ghost.frame + (def.frame_offset or 0)
			local source_y = (def.row or 0) * def.height
			canvas.draw_image(def.name, 0, 0,
				def.width * config.ui.SCALE, def.height * config.ui.SCALE,
				sheet_frame * def.width, source_y,
				def.width, def.height)

			canvas.restore()
		end
	end
end

--- Clear all ghost trails (returns tables to pool).
function dash.clear_ghost_trails()
	for i = #ghost_trails, 1, -1 do
		release_ghost(ghost_trails[i])
		ghost_trails[i] = nil
	end
end

--- Called when entering dash state. Locks direction, cancels vertical velocity, consumes charge.
---@param player table The player object
function dash.start(player)
	player.dash_state.direction = player.direction
	player.dash_state.elapsed_time = 0
	player.dash_state.trail_timer = 0
	player.vy = 0
	weapon_sync.consume_charge(player)
	player.animation = Animation.new(common.animations.DASH)
	audio.play_sfx(audio.dash, 0.15)
end

--- Handles input during dash. Direction change or jump cancels the dash.
---@param player table The player object
function dash.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end

	-- Direction change cancels dash
	if player.dash_state.direction ~= player.direction then
		player.dash_state.elapsed_time = DASH_DURATION
	end

	-- Jump cancels dash (ground or air)
	if player.is_grounded then
		if common.handle_jump(player) then
			player.dash_state.elapsed_time = DASH_DURATION
		end
	elseif common.handle_air_jump(player) then
		player.dash_state.elapsed_time = DASH_DURATION
	end

	-- Attack cancels dash
	if common.handle_attack(player) then
		player.dash_state.elapsed_time = DASH_DURATION
	end
end

--- Updates dash state. Moves at dash speed until duration expires.
---@param player table The player object
---@param dt number Delta time
function dash.update(player, dt)
	player.vx = player.direction * player.dash_speed

	if player.dash_state.elapsed_time < DASH_DURATION then
		if player.is_grounded then
			local is_slope = math.abs(player.ground_normal.x) > 0.01
			if is_slope then
				local tangent = common.get_ground_tangent(player)
				player.vy = player.direction * player.dash_speed * (tangent.y / tangent.x)
			else
				-- Small downward velocity keeps player snapped to ground during dash
			player.vy = common.GRAVITY
			end
		else
			-- Air/ceiling: horizontal only, collision handles vertical positioning
			player.vy = 0
		end
	end

	-- Spawn ghost trail snapshots at regular intervals during dash
	if player.dash_state.elapsed_time < DASH_DURATION then
		player.dash_state.trail_timer = player.dash_state.trail_timer + dt
		while player.dash_state.trail_timer >= GHOST_TRAIL_INTERVAL do
			player.dash_state.trail_timer = player.dash_state.trail_timer - GHOST_TRAIL_INTERVAL
			spawn_ghost_trail(player)
		end
	end

	player.dash_state.elapsed_time = player.dash_state.elapsed_time + dt

	if player.dash_state.elapsed_time >= DASH_DURATION then
		if not player.is_grounded then
			player:set_state(player.states.air)
		elseif controls.left_down() or controls.right_down() then
			player:set_state(player.states.run)
		else
			player:set_state(player.states.idle)
		end
	end
end

--- Renders the player in dash animation.
---@param player table The player object
function dash.draw(player)
	common.draw(player)
end

return dash
