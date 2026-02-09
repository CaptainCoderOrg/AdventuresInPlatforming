--- Shared factory for magician enemy variants.
--- Creates magician definitions with variant-specific sprites and configurable stats.
--- All variants share a single MagicBolt pool and particle systems.
local Animation = require("Animation")
local sprites = require("sprites")
local canvas = require("canvas")
local config = require("config")
local combat = require("combat")
local common = require("Enemies/common")
local prop_common = require("Prop/common")
local world = require("world")
local Effects = require("Effects")
local audio = require("audio")
local Projectile = require("Projectile")

local magician_common = {}

-- Detection/behavior constants
local FACE_PLAYER_RANGE = 10      -- Tiles: face player when within this range
local ATTACK_RANGE = 8            -- Tiles: attack when within range + LOS
local FLY_MIN_DISTANCE = 6        -- Tiles: minimum distance to maintain from player
local FLY_MAX_DISTANCE = 8        -- Tiles: maximum distance to maintain from player
local FLY_DURATION_MIN = 2.0      -- Seconds: minimum fly state duration
local FLY_DURATION_MAX = 3.0      -- Seconds: maximum fly state duration
local FLY_MIN_TIME = 0.25         -- Seconds: minimum time before exiting fly state
local FLY_SPEED = 4               -- Tiles/sec: flight movement speed
local PROJECTILE_DODGE_RANGE = 4  -- Tiles: detect incoming projectiles within this range
local TOO_FAR_DISTANCE = 12       -- Tiles: if farther than this, use disappear to catch up
local FADE_OUT_DURATION = 0.2     -- Seconds: quick fade out to dodge projectiles
local INVISIBLE_DURATION = 0.8    -- Seconds: stay invisible before reappearing
local FADE_IN_DURATION = 0.5      -- Seconds: fade in after teleport
local UNSTUCK_TELEPORT_DELAY = 0.2 -- Seconds: pause at safe position before fade-in
local RETURN_TELEPORT_DELAY = 0.3  -- Seconds: pause at spawn before fade-in

-- MagicBolt constants
local BOLT_SPEED = 10             -- Tiles/sec
local BOLT_DAMAGE = 2
local BOLT_HOMING_STRENGTH = 1.5  -- Radians/sec: how fast bolt turns toward player
local BOLT_MAX_LIFETIME = 5       -- Seconds: bolt self-destructs after this duration

-- Spread shot constants (blue magician)
local SPREAD_ANGLE = math.pi / 4      -- 45 degrees offset for outer bolts
local SPREAD_BOLT_SPEED = 8           -- Slightly slower than homing for balance
local SPREAD_OFFSETS = { 0, SPREAD_ANGLE, -SPREAD_ANGLE }

-- Burst shot constants (purple magician)
local BURST_COUNT = 3                 -- Number of bolts in a burst sequence

-- Visual bob constants
local BOB_SPEED = 3               -- Radians/sec for oscillation
local BOB_AMPLITUDE = 0.08        -- Tiles amplitude (up/down distance)

-- Throttle intervals for expensive checks
local DODGE_CHECK_INTERVAL = 0.05   -- Seconds between projectile dodge checks
local WALL_CHECK_INTERVAL = 0.15    -- Seconds between is_in_wall checks
local BOLT_WALL_CHECK_INTERVAL = 0.05 -- Seconds between bolt wall collision checks
local PATH_CHECK_INTERVAL = 0.08    -- Seconds between fly path-clear raycasts
local LOS_CHECK_INTERVAL = 0.12     -- Seconds between line-of-sight raycasts in idle

-- Pre-computed squared distance (avoids sqrt in projectile dodge check)
local PROJECTILE_DODGE_RANGE_SQ = PROJECTILE_DODGE_RANGE * PROJECTILE_DODGE_RANGE

-- Static table literals moved to module scope (avoids per-call allocation)
local SAFE_POSITION_DISTANCES = { 5, 6, 7, 4, 8, 3 }
local SAFE_POSITION_ANGLES = { 0, math.pi, math.pi/2, -math.pi/2, math.pi/4, -math.pi/4, 3*math.pi/4, -3*math.pi/4 }
-- Pre-computed direction unit vectors for safe position search (avoids per-call trig)
local SAFE_POSITION_DIRS = {}
for i, angle in ipairs(SAFE_POSITION_ANGLES) do
	SAFE_POSITION_DIRS[i] = { x = math.cos(angle), y = math.sin(angle) }
end
local FLY_HEIGHTS = { -2, -1, 0, 1, 2 }

--------------------------------------------------------------------------------
-- Helper functions (defined early for use throughout module)
--------------------------------------------------------------------------------

--- Check if a collision shape is solid world geometry (not a probe, trigger, hitbox, or entity)
---@param shape table The collision shape to check
---@return boolean True if solid geometry
local function is_solid_geometry(shape)
	if shape.is_probe or shape.is_trigger or shape.is_hitbox then
		return false
	end
	local owner = shape.owner
	return not (owner and (owner.is_enemy or owner.is_player or owner.is_bridge))
end

--- Check if a collision shape has no overlap with solid world geometry
---@param shape table The collision shape to test
---@return boolean True if position is clear of walls
local function is_position_clear(shape)
	for other, _ in pairs(world.hc:collisions(shape)) do
		if is_solid_geometry(other) then
			return false
		end
	end
	return true
end

--- Check if a position is within the enemy's activation bounds
---@param enemy table The magician enemy
---@param x number Top-left X in tiles
---@param y number Top-left Y in tiles
---@return boolean True if within bounds (or no bounds exist)
local function is_within_bounds(enemy, x, y)
	local b = enemy.activation_bounds
	if not b then return true end
	return x >= b.x and x + enemy.box.w <= b.x + b.width
	   and y >= b.y and y + enemy.box.h <= b.y + b.height
end

--- Clamp enemy position to stay within activation bounds
---@param enemy table The magician enemy
local function clamp_to_bounds(enemy)
	local b = enemy.activation_bounds
	if not b then return end
	local margin = 0.25
	local min_x = b.x + margin
	local max_x = b.x + b.width - enemy.box.w - margin
	local min_y = b.y + margin
	local max_y = b.y + b.height - enemy.box.h - margin
	if enemy.x < min_x then enemy.x = min_x; enemy.vx = 0 end
	if enemy.x > max_x then enemy.x = max_x; enemy.vx = 0 end
	if enemy.y < min_y then enemy.y = min_y; enemy.vy = 0 end
	if enemy.y > max_y then enemy.y = max_y; enemy.vy = 0 end
end

--- Check if a raycast from a point hits solid geometry
---@param x number Start X in pixels
---@param y number Start Y in pixels
---@param dir_x number Normalized X direction
---@param dir_y number Normalized Y direction
---@param dist number Distance in pixels
---@param ignore_shape table|nil Shape to exclude from checks
---@return boolean True if raycast hits solid geometry
local function raycast_hits_solid(x, y, dir_x, dir_y, dist, ignore_shape)
	for shape, hits in pairs(world.hc:raycast(x, y, dir_x, dir_y, dist)) do
		if shape ~= ignore_shape and is_solid_geometry(shape) and next(hits) then
			return true
		end
	end
	return false
end

-- Pre-computed hex lookup table (avoids string.format per frame)
local HEX_LOOKUP = {}
for i = 0, 255 do
	HEX_LOOKUP[i] = string.format("%02X", i)
end

--- Calculate fade-out alpha (1 -> 0 over duration)
---@param timer number Current fade timer
---@param duration number Total fade duration
---@return number Alpha value 0-1
local function fade_out_alpha(timer, duration)
	return math.max(0, 1 - timer / duration)
end

--- Calculate fade-in alpha (0 -> 1 over duration)
---@param timer number Current fade timer
---@param duration number Total fade duration
---@return number Alpha value 0-1
local function fade_in_alpha(timer, duration)
	return math.min(1, timer / duration)
end

--- Make enemy intangible (removes from combat and collision detection)
---@param enemy table The magician enemy
local function make_intangible(enemy)
	combat.remove(enemy)
	enemy._intangible_shape = enemy.shape
	world.shape_map[enemy] = nil
end

--- Restore enemy tangibility (re-adds to combat and collision detection)
---@param enemy table The magician enemy
local function restore_tangible(enemy)
	if enemy._intangible_shape then
		world.shape_map[enemy] = enemy._intangible_shape
		enemy.shape = enemy._intangible_shape
		enemy._intangible_shape = nil
		world.sync_position(enemy)
	end
	combat.add(enemy)
end

--------------------------------------------------------------------------------
-- Bolt trail particle pool (shared across all variants)
--------------------------------------------------------------------------------
local BoltParticle = {}
BoltParticle.all = {}
BoltParticle.count = 0

local PARTICLE_LIFETIME = 0.5        -- Seconds before particle fades completely
local PARTICLE_SPAWN_RATE = 0.04     -- Seconds between particle spawns
local PARTICLE_SPAWN_COUNT = 3       -- Number of particles per spawn
local PARTICLE_SIZE = 3              -- Pixels
local PARTICLE_SPREAD_PX = 12        -- Pixels: radius for random spawn offset
local PARTICLE_POOL_SIZE = 250       -- Pre-allocated particle pool size
local PARTICLE_ALPHA_STEPS = 10      -- Number of alpha gradient steps

-- Cyan to white color range (hex base colors without alpha)
local PARTICLE_CYAN_COLORS = { "00FFFF", "66FFFF", "AAFFFF", "FFFFFF" }
-- Yellow to white color range
local PARTICLE_YELLOW_COLORS = { "FFFF00", "FFFF66", "FFFFAA", "FFFFFF" }
-- Green to white color range
local PARTICLE_GREEN_COLORS = { "00FF00", "66FF66", "AAFFAA", "FFFFFF" }

-- Pre-compute color+alpha combinations (eliminates per-frame string allocation)
local PARTICLE_COLOR_CACHE = {}
local function cache_color_set(colors)
	for _, base_color in ipairs(colors) do
		if not PARTICLE_COLOR_CACHE[base_color] then
			PARTICLE_COLOR_CACHE[base_color] = {}
			for alpha_step = 0, PARTICLE_ALPHA_STEPS do
				local alpha = alpha_step / PARTICLE_ALPHA_STEPS
				local a = math.floor(alpha * 255 + 0.5)
				PARTICLE_COLOR_CACHE[base_color][alpha_step] = "#" .. base_color .. HEX_LOOKUP[a]
			end
		end
	end
end
cache_color_set(PARTICLE_CYAN_COLORS)
cache_color_set(PARTICLE_YELLOW_COLORS)
cache_color_set(PARTICLE_GREEN_COLORS)

-- Pre-allocate particle pool (avoids per-spawn table allocation)
local particle_pool = {}
for i = 1, PARTICLE_POOL_SIZE do
	particle_pool[i] = { x = 0, y = 0, lifetime = 0, color = "" }
end
local particle_pool_index = 0

--- Spawn a trail particle at the given position
---@param x number X position in tiles
---@param y number Y position in tiles
---@param colors table Array of hex color strings to pick from
local function spawn_particle(x, y, colors)
	particle_pool_index = particle_pool_index + 1
	if particle_pool_index > PARTICLE_POOL_SIZE then particle_pool_index = 1 end

	local color = colors[math.random(#colors)]
	local angle = math.random() * 2 * math.pi
	local radius = math.random() * PARTICLE_SPREAD_PX / sprites.tile_size

	local particle = particle_pool[particle_pool_index]
	particle.x = x + math.cos(angle) * radius
	particle.y = y + math.sin(angle) * radius
	particle.lifetime = PARTICLE_LIFETIME
	particle.color = color

	BoltParticle.count = BoltParticle.count + 1
	BoltParticle.all[BoltParticle.count] = particle
end

--- Update all particles
---@param dt number Delta time in seconds
local function update_particles(dt)
	local i = 1
	while i <= BoltParticle.count do
		local p = BoltParticle.all[i]
		p.lifetime = p.lifetime - dt
		if p.lifetime <= 0 then
			BoltParticle.all[i] = BoltParticle.all[BoltParticle.count]
			BoltParticle.all[BoltParticle.count] = nil
			BoltParticle.count = BoltParticle.count - 1
		else
			i = i + 1
		end
	end
end

--- Draw all particles
local function draw_particles()
	local ts = sprites.tile_size
	local half_size = PARTICLE_SIZE / 2
	for i = 1, BoltParticle.count do
		local p = BoltParticle.all[i]
		local alpha_step = math.floor((p.lifetime / PARTICLE_LIFETIME) * PARTICLE_ALPHA_STEPS + 0.5)
		local color_with_alpha = PARTICLE_COLOR_CACHE[p.color][alpha_step]
		canvas.set_color(color_with_alpha)
		canvas.fill_rect(p.x * ts - half_size, p.y * ts - half_size, PARTICLE_SIZE, PARTICLE_SIZE)
	end
	canvas.set_color("#FFFFFF")
end

--- Clear all particles
local function clear_particles()
	BoltParticle.all = {}
	BoltParticle.count = 0
end

--------------------------------------------------------------------------------
-- Puff particle effect (disappear effect, shared across all variants)
--------------------------------------------------------------------------------
local PuffParticle = {}
PuffParticle.all = {}
PuffParticle.count = 0

local PUFF_PARTICLE_COUNT = 50       -- Number of particles in puff
local PUFF_PARTICLE_LIFETIME = 0.25  -- Seconds for puff to complete
local PUFF_RING_RADIUS = 1           -- Tiles: starting ring radius
local PUFF_PARTICLE_SIZE = 2         -- Pixels
local PUFF_POOL_SIZE = 200           -- Pre-allocated puff pool size
local PUFF_ALPHA_STEPS = 10          -- Number of alpha gradient steps

-- Pre-compute white alpha gradient (eliminates per-frame string allocation)
local PUFF_ALPHA_CACHE = {}
for alpha_step = 0, PUFF_ALPHA_STEPS do
	local alpha = alpha_step / PUFF_ALPHA_STEPS
	local a = math.floor(alpha * 255 + 0.5)
	PUFF_ALPHA_CACHE[alpha_step] = "#FFFFFF" .. HEX_LOOKUP[a]
end

-- Pre-allocate puff particle pool
local puff_pool = {}
for i = 1, PUFF_POOL_SIZE do
	puff_pool[i] = { x = 0, y = 0, target_x = 0, target_y = 0, lifetime = 0 }
end
local puff_pool_index = 0

--- Spawn a puff effect at the given center position
---@param cx number Center X position in tiles
---@param cy number Center Y position in tiles
local function spawn_puff(cx, cy)
	local two_pi = 2 * math.pi
	for i = 1, PUFF_PARTICLE_COUNT do
		puff_pool_index = puff_pool_index + 1
		if puff_pool_index > PUFF_POOL_SIZE then puff_pool_index = 1 end

		local angle = (i / PUFF_PARTICLE_COUNT) * two_pi
		angle = angle + (math.random() - 0.5) * 0.2
		local radius = PUFF_RING_RADIUS + (math.random() - 0.5) * 0.3

		local particle = puff_pool[puff_pool_index]
		particle.x = cx + math.cos(angle) * radius
		particle.y = cy + math.sin(angle) * radius
		particle.target_x = cx
		particle.target_y = cy
		particle.lifetime = PUFF_PARTICLE_LIFETIME

		PuffParticle.count = PuffParticle.count + 1
		PuffParticle.all[PuffParticle.count] = particle
	end
end

--- Update all puff particles
---@param dt number Delta time in seconds
local function update_puff_particles(dt)
	local lerp_factor = dt * 5
	local i = 1
	while i <= PuffParticle.count do
		local p = PuffParticle.all[i]
		p.lifetime = p.lifetime - dt
		if p.lifetime <= 0 then
			PuffParticle.all[i] = PuffParticle.all[PuffParticle.count]
			PuffParticle.all[PuffParticle.count] = nil
			PuffParticle.count = PuffParticle.count - 1
		else
			p.x = p.x + (p.target_x - p.x) * lerp_factor
			p.y = p.y + (p.target_y - p.y) * lerp_factor
			i = i + 1
		end
	end
end

--- Draw all puff particles
local function draw_puff_particles()
	local ts = sprites.tile_size
	local half_size = PUFF_PARTICLE_SIZE / 2
	for i = 1, PuffParticle.count do
		local p = PuffParticle.all[i]
		local alpha_step = math.floor((p.lifetime / PUFF_PARTICLE_LIFETIME) * PUFF_ALPHA_STEPS + 0.5)
		canvas.set_color(PUFF_ALPHA_CACHE[alpha_step])
		canvas.fill_rect(p.x * ts - half_size, p.y * ts - half_size, PUFF_PARTICLE_SIZE, PUFF_PARTICLE_SIZE)
	end
	canvas.set_color("#FFFFFF")
end

--- Clear all puff particles
local function clear_puff_particles()
	PuffParticle.all = {}
	PuffParticle.count = 0
end

--------------------------------------------------------------------------------
-- MagicBolt projectile pool (shared across all variants)
--------------------------------------------------------------------------------
local MagicBolt = {}
MagicBolt.all = {}

-- Shared across all bolts (dimensions never change per-bolt)
local BOLT_BOX = { x = 0, y = 0, w = 6/16, h = 6/16 }
local bolt_anim_opts = { flipped = 1 }

--- Spawn a new magic bolt projectile
---@param x number X position in tiles (top-left of sprite)
---@param y number Y position in tiles (top-left of sprite)
---@param target_x number Target X position in tiles
---@param target_y number Target Y position in tiles
---@param bolt_anim_def table Animation definition for the bolt sprite
---@param bolt_hit_anim_def table Animation definition for the bolt hit effect
---@return table bolt The created MagicBolt instance
function MagicBolt.spawn(x, y, target_x, target_y, bolt_anim_def, bolt_hit_anim_def)
	local dx = target_x - x
	local dy = target_y - y
	local dist = math.sqrt(dx * dx + dy * dy)

	local vx, vy = 0, 0
	if dist > 0 then
		vx = (dx / dist) * BOLT_SPEED
		vy = (dy / dist) * BOLT_SPEED
	end

	bolt_anim_opts.flipped = vx >= 0 and 1 or -1

	local bolt = {
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		homing = true,
		is_bolt = true,
		particle_colors = PARTICLE_CYAN_COLORS,
		box = BOLT_BOX,
		animation = Animation.new(bolt_anim_def, bolt_anim_opts),
		hit_anim_def = bolt_hit_anim_def,
		marked_for_destruction = false,
		debug_color = "#FFFF00",
		particle_timer = 0,
		wall_check_timer = 0,
		lifetime = 0,
	}

	-- Add trigger collider for wall detection
	world.add_trigger_collider(bolt)
	-- Add to combat system for player collision
	combat.add(bolt)

	MagicBolt.all[#MagicBolt.all + 1] = bolt
	return bolt
end

--- Spawn a non-homing magic bolt with explicit velocity
---@param x number X position in tiles
---@param y number Y position in tiles
---@param vx number X velocity in tiles/sec
---@param vy number Y velocity in tiles/sec
---@param bolt_anim_def table Animation definition for the bolt sprite
---@param bolt_hit_anim_def table Animation definition for the bolt hit effect
---@param colors table|nil Particle color set (defaults to cyan)
---@return table bolt The created MagicBolt instance
function MagicBolt.spawn_with_velocity(x, y, vx, vy, bolt_anim_def, bolt_hit_anim_def, colors)
	bolt_anim_opts.flipped = vx >= 0 and 1 or -1

	local bolt = {
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		homing = false,
		is_bolt = true,
		particle_colors = colors or PARTICLE_CYAN_COLORS,
		box = BOLT_BOX,
		animation = Animation.new(bolt_anim_def, bolt_anim_opts),
		hit_anim_def = bolt_hit_anim_def,
		marked_for_destruction = false,
		debug_color = "#FFFF00",
		particle_timer = 0,
		wall_check_timer = 0,
		lifetime = 0,
	}

	world.add_trigger_collider(bolt)
	combat.add(bolt)

	MagicBolt.all[#MagicBolt.all + 1] = bolt
	return bolt
end

--- Creates hit effect at bolt position and marks bolt for destruction
---@param bolt table MagicBolt instance
local function bolt_impact(bolt)
	-- Create centered 16x16 effect at impact point
	local effect_x = bolt.x + bolt.box.w / 2 - 0.5
	local effect_y = bolt.y + bolt.box.h / 2 - 0.5
	Effects.new("magic_bolt_hit", bolt.hit_anim_def, effect_x, effect_y)
	bolt.marked_for_destruction = true
end

--- Check if bolt hit a wall (ignoring enemies)
---@param bolt table MagicBolt instance
---@return boolean True if hit solid geometry (not an enemy)
local function bolt_hit_wall(bolt)
	local shape = world.trigger_map[bolt]
	if not shape then return false end

	local ts = sprites.tile_size
	local px = (bolt.x + bolt.box.x) * ts
	local py = (bolt.y + bolt.box.y) * ts
	shape:moveTo(px + bolt.box.w * ts / 2, py + bolt.box.h * ts / 2)

	return not is_position_clear(shape)
end

--- Update all magic bolts (called once per frame from Enemy.update)
---@param dt number Delta time in seconds
---@param player table Player instance for collision
function MagicBolt.update_all(dt, player)
	-- Update trail particles and puff particles
	update_particles(dt)
	update_puff_particles(dt)

	local i = 1
	while i <= #MagicBolt.all do
		local bolt = MagicBolt.all[i]
		if bolt.marked_for_destruction then
			world.remove_trigger_collider(bolt)
			combat.remove(bolt)
			MagicBolt.all[i] = MagicBolt.all[#MagicBolt.all]
			MagicBolt.all[#MagicBolt.all] = nil
		else
			-- Homing: gradually turn toward player using vector lerp (avoids trig)
			if bolt.homing and player then
				local bolt_cx = bolt.x + bolt.box.w / 2
				local bolt_cy = bolt.y + bolt.box.h / 2
				local player_cx = player.x + player.box.x + player.box.w / 2
				local player_cy = player.y + player.box.y + player.box.h / 2

				-- Direction to player
				local dx = player_cx - bolt_cx
				local dy = player_cy - bolt_cy
				local dist_sq = dx * dx + dy * dy

				if dist_sq > 0.01 then
					local dist = math.sqrt(dist_sq)
					local target_vx = (dx / dist) * BOLT_SPEED
					local target_vy = (dy / dist) * BOLT_SPEED

					-- Lerp velocity toward target direction
					local lerp = math.min(1, BOLT_HOMING_STRENGTH * dt * 0.5)
					bolt.vx = bolt.vx + (target_vx - bolt.vx) * lerp
					bolt.vy = bolt.vy + (target_vy - bolt.vy) * lerp

					-- Renormalize to maintain constant speed
					local speed = math.sqrt(bolt.vx * bolt.vx + bolt.vy * bolt.vy)
					if speed > 0 then
						bolt.vx = (bolt.vx / speed) * BOLT_SPEED
						bolt.vy = (bolt.vy / speed) * BOLT_SPEED
					end

					-- Update animation flip based on direction
					bolt.animation.flipped = bolt.vx >= 0 and 1 or -1
				end
			end

			bolt.x = bolt.x + bolt.vx * dt
			bolt.y = bolt.y + bolt.vy * dt
			combat.update(bolt)
			bolt.animation:play(dt)

			-- Lifetime check
			bolt.lifetime = bolt.lifetime + dt
			if bolt.lifetime >= BOLT_MAX_LIFETIME then
				bolt_impact(bolt)
			end

			if not bolt.marked_for_destruction then
				-- Spawn trail particles
				bolt.particle_timer = bolt.particle_timer + dt
				if bolt.particle_timer >= PARTICLE_SPAWN_RATE then
					bolt.particle_timer = bolt.particle_timer - PARTICLE_SPAWN_RATE
					local bolt_cx = bolt.x + bolt.box.w / 2
					local bolt_cy = bolt.y + bolt.box.h / 2
					for _ = 1, PARTICLE_SPAWN_COUNT do
						spawn_particle(bolt_cx, bolt_cy, bolt.particle_colors)
					end
				end

				-- Check wall collision (throttled to reduce HC queries)
				bolt.wall_check_timer = bolt.wall_check_timer + dt
				local hit_wall = false
				if bolt.wall_check_timer >= BOLT_WALL_CHECK_INTERVAL then
					bolt.wall_check_timer = 0
					hit_wall = bolt_hit_wall(bolt)
				end

				if hit_wall then
					bolt_impact(bolt)
					audio.play_solid_sound()
				elseif prop_common.damage_player(bolt, player, BOLT_DAMAGE) then
					bolt_impact(bolt)
				end
			end

			i = i + 1
		end
	end
end

--- Draw all magic bolts (called once per frame from Enemy.draw)
function MagicBolt.draw_all()
	-- Draw trail particles behind bolts
	draw_particles()
	draw_puff_particles()

	for i = 1, #MagicBolt.all do
		local bolt = MagicBolt.all[i]
		if not bolt.marked_for_destruction then
			bolt.animation:draw(sprites.px(bolt.x), sprites.px(bolt.y))

			-- Debug bounding box
			if config.bounding_boxes and bolt.box then
				local bx = (bolt.x + bolt.box.x) * sprites.tile_size
				local by = (bolt.y + bolt.box.y) * sprites.tile_size
				local bw = bolt.box.w * sprites.tile_size
				local bh = bolt.box.h * sprites.tile_size
				canvas.draw_rect(bx, by, bw, bh, bolt.debug_color)
			end
		end
	end
end

--- Clear all magic bolts (called on level reload)
function MagicBolt.clear_all()
	for i = 1, #MagicBolt.all do
		local bolt = MagicBolt.all[i]
		world.remove_trigger_collider(bolt)
		combat.remove(bolt)
	end
	MagicBolt.all = {}
	clear_particles()
	clear_puff_particles()
end

--------------------------------------------------------------------------------
-- Shared state helper functions
--------------------------------------------------------------------------------

--- Common update logic for all magician states
---@param enemy table The magician enemy
---@param dt number Delta time in seconds
local function update_common(enemy, dt)
	enemy.bob_timer = enemy.bob_timer + dt
	enemy._dodge_check_timer = math.max(0, (enemy._dodge_check_timer or 0) - dt)
	enemy._wall_check_timer = math.max(0, (enemy._wall_check_timer or 0) - dt)
	enemy._los_check_timer = math.max(0, (enemy._los_check_timer or 0) - dt)
	enemy._path_check_timer = math.max(0, (enemy._path_check_timer or 0) - dt)
end

--- Initialize common state properties: animation, velocity, and damage
---@param enemy table The magician enemy
---@param anim table Animation definition
local function begin_state(enemy, anim)
	common.set_animation(enemy, anim)
	enemy.vx = 0
	enemy.vy = 0
	enemy.damage = 0.5
end

--- Face the player by updating direction and animation flip
---@param enemy table The magician enemy
local function face_player(enemy)
	enemy.direction = common.direction_to_player(enemy)
	enemy.animation.flipped = enemy.direction
end

--- Check if there's a player projectile heading toward the magician
---@param enemy table The magician enemy
---@return boolean True if dodge should be triggered
local function should_dodge_projectile(enemy)
	if not enemy.target_player then return false end

	-- Throttle check (not every frame)
	if (enemy._dodge_check_timer or 0) > 0 then return false end
	enemy._dodge_check_timer = DODGE_CHECK_INTERVAL

	-- Check all player projectiles
	local projectile = next(Projectile.all)
	while projectile do
		local dx = projectile.x - enemy.x
		local dy = projectile.y - enemy.y
		local dist_sq = dx * dx + dy * dy

		if dist_sq <= PROJECTILE_DODGE_RANGE_SQ then
			-- Check if projectile is heading toward the magician using dot product
			local dot = -(dx * projectile.vx + dy * projectile.vy)

			if dot > 0 then
				return true
			end
		end
		projectile = next(Projectile.all, projectile)
	end

	return false
end

--- Check if there's a clear path in the given direction using raycast
---@param enemy table The magician enemy
---@param dir_x number X direction (-1 to 1)
---@param dir_y number Y direction (-1 to 1)
---@param distance number Distance to check in tiles
---@return boolean True if path is clear
local function is_path_clear(enemy, dir_x, dir_y, distance)
	local ts = sprites.tile_size
	local cx = (enemy.x + enemy.box.x + enemy.box.w / 2) * ts
	local cy = (enemy.y + enemy.box.y + enemy.box.h / 2) * ts
	return not raycast_hits_solid(cx, cy, dir_x, dir_y, distance * ts, world.shape_map[enemy])
end

--- Check if enemy is currently inside a wall
---@param enemy table The magician enemy
---@return boolean True if overlapping solid geometry
local function is_in_wall(enemy)
	local shape = world.shape_map[enemy] or enemy._intangible_shape
	if not shape then return false end
	return not is_position_clear(shape)
end

--- Find a safe position near the player that isn't inside a wall
---@param enemy table The magician enemy
---@return number, number Safe x, y position (or current position if none found)
local function find_safe_position(enemy)
	if not enemy.target_player then return enemy.x, enemy.y end

	local player = enemy.target_player
	local ts = sprites.tile_size

	-- Create a temporary test shape
	local test_shape = world.hc:rectangle(0, 0, enemy.box.w * ts, enemy.box.h * ts)
	test_shape.is_probe = true

	for _, dist in ipairs(SAFE_POSITION_DISTANCES) do
		for _, dir in ipairs(SAFE_POSITION_DIRS) do
			local test_x = player.x + dir.x * dist
			local test_y = player.y + dir.y * dist

			local px = (test_x + enemy.box.x) * ts
			local py = (test_y + enemy.box.y) * ts
			test_shape:moveTo(px + enemy.box.w * ts / 2, py + enemy.box.h * ts / 2)

			if is_position_clear(test_shape) and is_within_bounds(enemy, test_x, test_y) then
				world.hc:remove(test_shape)
				return test_x, test_y
			end
		end
	end

	world.hc:remove(test_shape)
	return enemy.x, enemy.y
end

--- Find a valid fly position that maintains distance from the player
---@param enemy table The magician enemy
---@return number, number Target x, y position
local function find_fly_position(enemy)
	if not enemy.target_player then return enemy.x, enemy.y end

	local player = enemy.target_player
	local ts = sprites.tile_size
	local current_side = enemy.x < player.x and -1 or 1
	local random_dist = FLY_MIN_DISTANCE + math.random() * (FLY_MAX_DISTANCE - FLY_MIN_DISTANCE)

	local test_shape = world.hc:rectangle(0, 0, enemy.box.w * ts, enemy.box.h * ts)
	test_shape.is_probe = true

	local enemy_cx = (enemy.x + enemy.box.x + enemy.box.w / 2) * ts
	local enemy_cy = (enemy.y + enemy.box.y + enemy.box.h / 2) * ts
	local enemy_shape = world.shape_map[enemy]

	-- Try same side first, then opposite side
	for side_idx = 1, 2 do
		local side = (side_idx == 1) and current_side or -current_side
		for _, height in ipairs(FLY_HEIGHTS) do
			local test_x = player.x + side * random_dist
			local test_y = player.y + height

			local target_cx = (test_x + enemy.box.x + enemy.box.w / 2) * ts
			local target_cy = (test_y + enemy.box.y + enemy.box.h / 2) * ts
			local ray_dx = target_cx - enemy_cx
			local ray_dy = target_cy - enemy_cy
			local ray_dist = math.sqrt(ray_dx * ray_dx + ray_dy * ray_dy)

			if ray_dist > 0 and raycast_hits_solid(enemy_cx, enemy_cy, ray_dx / ray_dist, ray_dy / ray_dist, ray_dist, enemy_shape) then
				goto next_position
			end

			local px = (test_x + enemy.box.x) * ts
			local py = (test_y + enemy.box.y) * ts
			test_shape:moveTo(px + enemy.box.w * ts / 2, py + enemy.box.h * ts / 2)

			if is_position_clear(test_shape) and is_within_bounds(enemy, test_x, test_y) then
				world.hc:remove(test_shape)
				return test_x, test_y
			end

			::next_position::
		end
	end

	world.hc:remove(test_shape)
	return enemy.x, enemy.y
end

--- Draw magician with bob offset and alpha
---@param enemy table The magician enemy
local function draw_magician(enemy)
	if not enemy.animation then return end

	local bob_offset = math.sin((enemy.bob_timer or 0) * BOB_SPEED) * BOB_AMPLITUDE
	local original_y = enemy.y
	enemy.y = enemy.y + bob_offset

	canvas.set_global_alpha(enemy.alpha or 1)
	common.draw(enemy)
	canvas.set_global_alpha(1)

	enemy.y = original_y
end

--------------------------------------------------------------------------------
-- Factory: create a magician variant definition
--------------------------------------------------------------------------------

--- Create a magician enemy definition for a specific sprite variant
---@param sprite_set table Sprite references { sheet, projectile, projectile_hit }
---@param cfg table|nil Optional config overrides for future stat customization
---@return table Enemy definition for registration
function magician_common.create(sprite_set, cfg)
	cfg = cfg or {}

	-- Variant-specific animation definitions
	local animations = {
		IDLE = Animation.create_definition(sprite_set.sheet, 6, {
			ms_per_frame = 120, width = 16, height = 16, loop = true, row = 1
		}),
		FLY = Animation.create_definition(sprite_set.sheet, 4, {
			ms_per_frame = 100, width = 16, height = 16, loop = true, row = 2
		}),
		ATTACK = Animation.create_definition(sprite_set.sheet, 11, {
			ms_per_frame = cfg.attack_ms_per_frame or 80, width = 16, height = 16, loop = false, row = 0
		}),
		HIT = Animation.create_definition(sprite_set.sheet, 3, {
			ms_per_frame = 60, width = 16, height = 16, loop = false, row = 3
		}),
		DEATH = Animation.create_definition(sprite_set.sheet, 6, {
			ms_per_frame = 100, width = 16, height = 16, loop = false, row = 4
		}),
		BOLT = Animation.create_definition(sprite_set.projectile, 4, {
			ms_per_frame = 80, width = 6, height = 6, loop = true
		}),
		BOLT_HIT = Animation.create_definition(sprite_set.projectile_hit, 5, {
			ms_per_frame = 60, width = 16, height = 16, loop = false
		}),
	}

	-- Forward-declare closures that reference states
	local check_combat_interrupts
	local choose_next_combat_state

	--- Common setup for states that fade out, reposition, and fade back in
	---@param enemy table The magician enemy
	local function begin_fade_state(enemy)
		begin_state(enemy, animations.FLY)
		enemy.damage = 0
		enemy.invulnerable = true
		enemy.fade_timer = 0
		enemy.phase = "fade_out"
		enemy.alpha = 1
	end

	-- Variant-specific state machine
	local states = {}

	states.idle = {
		name = "idle",
		start = function(enemy, _)
			begin_state(enemy, animations.IDLE)
			enemy.alpha = 1
			enemy.bob_timer = enemy.bob_timer or 0
			-- Store spawn position for return state (only set once)
			if not enemy.spawn_x then
				enemy.spawn_x = enemy.x
				enemy.spawn_y = enemy.y
			end
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			if check_combat_interrupts(enemy) then return end

			if common.player_in_range(enemy, FACE_PLAYER_RANGE) then
				face_player(enemy)
			end

			if common.player_in_range(enemy, ATTACK_RANGE) and (enemy._los_check_timer or 0) <= 0 then
				enemy._los_check_timer = LOS_CHECK_INTERVAL
				if common.has_line_of_sight(enemy) then
					enemy:set_state(states.attack)
				end
			end
		end,
		draw = draw_magician,
	}

	states.attack = {
		name = "attack",
		start = function(enemy, _)
			begin_state(enemy, animations.ATTACK)
			enemy.bolt_spawned = false
			enemy.attack_count = 1
			face_player(enemy)

			-- Store target position at attack start (used by default and spread)
			if enemy.target_player then
				enemy.attack_target_x = enemy.target_player.x + enemy.target_player.box.x + enemy.target_player.box.w / 2
				enemy.attack_target_y = enemy.target_player.y + enemy.target_player.box.y + enemy.target_player.box.h / 2
			end
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			if check_combat_interrupts(enemy) then return end

			face_player(enemy)

			-- Spawn bolt on penultimate frame of attack animation (frame 10 of 11)
			if not enemy.bolt_spawned and enemy.animation.frame >= 10 then
				enemy.bolt_spawned = true

				-- Burst: re-read player position each shot
				if cfg.burst_shot and enemy.target_player then
					enemy.attack_target_x = enemy.target_player.x + enemy.target_player.box.x + enemy.target_player.box.w / 2
					enemy.attack_target_y = enemy.target_player.y + enemy.target_player.box.y + enemy.target_player.box.h / 2
				end

				-- Spawn from top corner based on direction
				local spawn_x = enemy.x + (enemy.direction == 1 and 0.75 or -0.125)
				local spawn_y = enemy.y

				if enemy.attack_target_x and enemy.attack_target_y then
					if cfg.spread_shot then
						-- 3-bolt spread: center fires horizontally, outer two at ±45°
						local base_angle = enemy.direction == 1 and 0 or math.pi
						for _, offset in ipairs(SPREAD_OFFSETS) do
							local angle = base_angle + offset
							local bvx = math.cos(angle) * SPREAD_BOLT_SPEED
							local bvy = math.sin(angle) * SPREAD_BOLT_SPEED
							MagicBolt.spawn_with_velocity(spawn_x, spawn_y, bvx, bvy,
								animations.BOLT, animations.BOLT_HIT, PARTICLE_YELLOW_COLORS)
						end
					elseif cfg.burst_shot then
						-- Burst: non-homing bolt aimed at player's current position
						local dx = enemy.attack_target_x - spawn_x
						local dy = enemy.attack_target_y - spawn_y
						local dist = math.sqrt(dx * dx + dy * dy)
						local bvx, bvy = 0, 0
						if dist > 0 then
							bvx = (dx / dist) * BOLT_SPEED
							bvy = (dy / dist) * BOLT_SPEED
						end
						MagicBolt.spawn_with_velocity(spawn_x, spawn_y, bvx, bvy,
							animations.BOLT, animations.BOLT_HIT, PARTICLE_GREEN_COLORS)
					else
						MagicBolt.spawn(spawn_x, spawn_y, enemy.attack_target_x, enemy.attack_target_y,
							animations.BOLT, animations.BOLT_HIT)
					end
				end
			end

			if enemy.animation:is_finished() then
				-- Burst: replay attack animation up to BURST_COUNT times
				if cfg.burst_shot and enemy.attack_count < BURST_COUNT then
					enemy.attack_count = enemy.attack_count + 1
					enemy.bolt_spawned = false
					common.set_animation(enemy, animations.ATTACK)
					face_player(enemy)
				else
					if cfg.attack_cooldown then
						enemy._attack_cooldown = cfg.attack_cooldown
					end
					enemy:set_state(states.fly)
				end
			end
		end,
		draw = draw_magician,
	}

	states.fly = {
		name = "fly",
		start = function(enemy, _)
			begin_state(enemy, animations.FLY)
			enemy.alpha = 1
			enemy.fly_timer = FLY_DURATION_MIN + math.random() * (FLY_DURATION_MAX - FLY_DURATION_MIN)
			enemy.fly_elapsed = 0
			enemy._fly_target_x, enemy._fly_target_y = find_fly_position(enemy)
			face_player(enemy)
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			if check_combat_interrupts(enemy) then return end

			-- Tick down attack cooldown
			if enemy._attack_cooldown and enemy._attack_cooldown > 0 then
				enemy._attack_cooldown = enemy._attack_cooldown - dt
			end

			-- Throttle path-clear raycasts
			local path_check_ready = (enemy._path_check_timer or 0) <= 0
			if path_check_ready then
				enemy._path_check_timer = PATH_CHECK_INTERVAL
			end

			local dir_x, dir_y = 0, 0
			local has_target = false

			if enemy._fly_target_x and enemy._fly_target_y then
				local dx = enemy._fly_target_x - enemy.x
				local dy = enemy._fly_target_y - enemy.y
				local dist = math.sqrt(dx * dx + dy * dy)

				if dist > 0.25 then
					has_target = true
					dir_x = dx / dist
					dir_y = dy / dist

					if path_check_ready and not is_path_clear(enemy, dir_x, dir_y, FLY_SPEED * dt + 0.5) then
						dir_x, dir_y = 0, 0
						has_target = false
					end
				end
			end

			-- If no valid target and player is too far, move toward player
			if not has_target and enemy.target_player then
				local player = enemy.target_player
				local dx = player.x - enemy.x
				local dy = player.y - enemy.y
				local dist_sq = dx * dx + dy * dy

				if dist_sq > FLY_MAX_DISTANCE * FLY_MAX_DISTANCE then
					local dist_to_player = math.sqrt(dist_sq)
					dir_x = dx / dist_to_player
					dir_y = dy / dist_to_player

					if path_check_ready and not is_path_clear(enemy, dir_x, dir_y, FLY_SPEED * dt + 0.5) then
						dir_x, dir_y = 0, 0
					end
				end
			end

			enemy.vx = dir_x * FLY_SPEED
			enemy.vy = dir_y * FLY_SPEED
			clamp_to_bounds(enemy)

			if enemy.target_player then
				face_player(enemy)
			end

			enemy.fly_elapsed = enemy.fly_elapsed + dt

			if enemy._fly_target_x and enemy._fly_target_y and enemy.fly_elapsed >= FLY_MIN_TIME then
				local dx = enemy._fly_target_x - enemy.x
				local dy = enemy._fly_target_y - enemy.y
				if dx * dx + dy * dy <= 0.0625 then  -- 0.25^2
					choose_next_combat_state(enemy)
					return
				end
			end

			enemy.fly_timer = enemy.fly_timer - dt
			if enemy.fly_timer <= 0 then
				choose_next_combat_state(enemy)
			end
		end,
		draw = draw_magician,
	}

	states.disappear = {
		name = "disappear",
		start = function(enemy, _)
			begin_fade_state(enemy)
			local cx = enemy.x + enemy.box.x + enemy.box.w / 2
			local cy = enemy.y + enemy.box.y + enemy.box.h / 2
			spawn_puff(cx, cy)

			-- Record which side of player we're on (to move to opposite side)
			if enemy.target_player then
				enemy._start_side = enemy.x < enemy.target_player.x and -1 or 1
			else
				enemy._start_side = 1
			end

			-- Make intangible so projectiles can't find this enemy
			make_intangible(enemy)
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			enemy.fade_timer = enemy.fade_timer + dt

			if enemy.phase == "fade_out" then
				enemy.alpha = fade_out_alpha(enemy.fade_timer, FADE_OUT_DURATION)
				if enemy.fade_timer >= FADE_OUT_DURATION then
					enemy.phase = "invisible"
					enemy.fade_timer = 0
					enemy.alpha = 0

					-- Calculate random target position on opposite side of player
					if enemy.target_player then
						local target_side = -enemy._start_side
						local random_dist = FLY_MIN_DISTANCE + math.random() * (FLY_MAX_DISTANCE - FLY_MIN_DISTANCE)
						local random_height = (math.random() * 4) - 2  -- -2 to 2 tiles
						enemy._target_x = enemy.target_player.x + target_side * random_dist
						enemy._target_y = enemy.target_player.y + random_height
						-- Clamp target to activation bounds
						local b = enemy.activation_bounds
						if b then
							enemy._target_x = math.max(b.x, math.min(b.x + b.width - enemy.box.w, enemy._target_x))
							enemy._target_y = math.max(b.y, math.min(b.y + b.height - enemy.box.h, enemy._target_y))
						end
					else
						enemy._target_x = enemy.x
						enemy._target_y = enemy.y
					end
				end
			elseif enemy.phase == "invisible" then
				-- Move to random target position on opposite side of player
				local move_speed = FLY_SPEED * 3  -- Fast repositioning
				local dir_x, dir_y = 0, 0

				if enemy._target_x and enemy._target_y then
					local dx = enemy._target_x - enemy.x
					local dy = enemy._target_y - enemy.y
					local dist = math.sqrt(dx * dx + dy * dy)

					if dist > 0.5 then  -- Still need to move
						dir_x = dx / dist
						dir_y = dy / dist
					end
				end

				enemy.vx = dir_x * move_speed
				enemy.vy = dir_y * move_speed

				if enemy._intangible_shape and (enemy.vx ~= 0 or enemy.vy ~= 0) then
					local ts = sprites.tile_size
					local test_x = enemy.x + enemy.vx * dt
					local test_y = enemy.y + enemy.vy * dt
					local target_px = (test_x + enemy.box.x) * ts
					local target_py = (test_y + enemy.box.y) * ts
					local old_x, old_y = enemy._intangible_shape:bbox()
					enemy._intangible_shape:move(target_px - old_x, target_py - old_y)

					-- Throttle wall check to reduce HC allocation frequency
					enemy._invis_wall_timer = (enemy._invis_wall_timer or 0) - dt
					if enemy._invis_wall_timer <= 0 then
						enemy._invis_wall_timer = WALL_CHECK_INTERVAL
						if not is_position_clear(enemy._intangible_shape) then
							enemy._intangible_shape:move(old_x - target_px, old_y - target_py)
							enemy.vx = 0
							enemy.vy = 0
						end
					end
				end
				clamp_to_bounds(enemy)

				if enemy.target_player then
					face_player(enemy)
				end

				if enemy.fade_timer >= INVISIBLE_DURATION then
					enemy.phase = "fade_in"
					enemy.fade_timer = 0
					enemy.vx = 0
					enemy.vy = 0
				end
			elseif enemy.phase == "fade_in" then
				enemy.alpha = fade_in_alpha(enemy.fade_timer, FADE_IN_DURATION)
				if enemy.fade_timer >= FADE_IN_DURATION then
					enemy.alpha = 1
					enemy.invulnerable = false
					restore_tangible(enemy)
					enemy:set_state(states.attack)
				end
			end
		end,
		draw = draw_magician,
	}

	states.unstuck = {
		name = "unstuck",
		start = function(enemy, _)
			begin_fade_state(enemy)
			combat.remove(enemy)
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			enemy.fade_timer = enemy.fade_timer + dt

			if enemy.phase == "fade_out" then
				enemy.alpha = fade_out_alpha(enemy.fade_timer, FADE_OUT_DURATION)
				if enemy.fade_timer >= FADE_OUT_DURATION then
					enemy.phase = "teleport"
					enemy.fade_timer = 0
					enemy.alpha = 0
					local safe_x, safe_y = find_safe_position(enemy)
					enemy.x = safe_x
					enemy.y = safe_y
					world.sync_position(enemy)
					face_player(enemy)
				end
			elseif enemy.phase == "teleport" then
				if enemy.fade_timer >= UNSTUCK_TELEPORT_DELAY then
					enemy.phase = "fade_in"
					enemy.fade_timer = 0
				end
			elseif enemy.phase == "fade_in" then
				enemy.alpha = fade_in_alpha(enemy.fade_timer, FADE_IN_DURATION)
				if enemy.fade_timer >= FADE_IN_DURATION then
					enemy.alpha = 1
					enemy.invulnerable = false
					combat.add(enemy)
					enemy:set_state(states.idle)
				end
			end
		end,
		draw = draw_magician,
	}

	states.hit = {
		name = "hit",
		start = function(enemy, _)
			begin_state(enemy, animations.HIT)
			enemy.invulnerable = true
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			if enemy.animation:is_finished() then
				enemy.invulnerable = false
				enemy:set_state(states.disappear)
			end
		end,
		draw = draw_magician,
	}

	states["return"] = {
		name = "return",
		start = function(enemy, _)
			begin_fade_state(enemy)
			make_intangible(enemy)
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			enemy.fade_timer = enemy.fade_timer + dt

			if enemy.phase == "fade_out" then
				enemy.alpha = fade_out_alpha(enemy.fade_timer, FADE_OUT_DURATION)
				if enemy.fade_timer >= FADE_OUT_DURATION then
					enemy.phase = "teleport"
					enemy.fade_timer = 0
					enemy.alpha = 0
					if enemy.spawn_x and enemy.spawn_y then
						enemy.x = enemy.spawn_x
						enemy.y = enemy.spawn_y
						if enemy._intangible_shape then
							local ts = sprites.tile_size
							local px = (enemy.x + enemy.box.x) * ts
							local py = (enemy.y + enemy.box.y) * ts
							enemy._intangible_shape:moveTo(px + enemy.box.w * ts / 2, py + enemy.box.h * ts / 2)
						end
					end
					face_player(enemy)
				end
			elseif enemy.phase == "teleport" then
				if enemy.fade_timer >= RETURN_TELEPORT_DELAY then
					enemy.phase = "fade_in"
					enemy.fade_timer = 0
				end
			elseif enemy.phase == "fade_in" then
				enemy.alpha = fade_in_alpha(enemy.fade_timer, FADE_IN_DURATION)
				if enemy.fade_timer >= FADE_IN_DURATION then
					enemy.alpha = 1
					enemy.invulnerable = false
					restore_tangible(enemy)
					enemy:set_state(states.idle)
				end
			end
		end,
		draw = draw_magician,
	}

	states.death = {
		name = "death",
		start = function(enemy, _)
			begin_state(enemy, animations.DEATH)
			enemy.damage = 0
			enemy.alpha = 1
		end,
		update = function(enemy, dt)
			update_common(enemy, dt)
			if enemy.animation:is_finished() then
				enemy.marked_for_destruction = true
			end
		end,
		draw = draw_magician,
	}

	-- Define closures that reference states (assigned after states table is built)
	check_combat_interrupts = function(enemy)
		if (enemy._wall_check_timer or 0) <= 0 then
			enemy._wall_check_timer = WALL_CHECK_INTERVAL
			if is_in_wall(enemy) then
				enemy:set_state(states.unstuck)
				return true
			end
		end
		if should_dodge_projectile(enemy) then
			enemy:set_state(states.disappear)
			return true
		end
		return false
	end

	choose_next_combat_state = function(enemy)
		if not enemy.target_player then
			enemy:set_state(states["return"])
			return
		end

		-- Attack cooldown: force fly state until timer expires
		if enemy._attack_cooldown and enemy._attack_cooldown > 0 then
			enemy:set_state(states.fly)
			return
		end

		if common.player_in_range(enemy, ATTACK_RANGE) and common.has_line_of_sight(enemy) then
			enemy:set_state(states.attack)
		elseif not common.player_in_range(enemy, TOO_FAR_DISTANCE) then
			enemy:set_state(states.disappear)
		elseif not common.has_line_of_sight(enemy) then
			enemy:set_state(states["return"])
		else
			enemy:set_state(states.fly)
		end
	end

	--- Custom hit handler that applies damage and transitions to hit state
	---@param self table The magician enemy
	---@param _source_type string "player", "weapon", or "projectile" (unused)
	---@param source table Hit source with optional .damage
	local function on_hit(self, _source_type, source)
		if self.invulnerable then return end

		local damage = (source and source.damage) or 1
		local is_crit = source and source.is_crit

		-- Apply armor reduction, then crit multiplier
		damage = math.max(0, damage - self:get_armor())
		if is_crit then
			damage = damage * 2
		end

		-- Create floating damage text
		Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage, is_crit)

		if damage <= 0 then
			audio.play_solid_sound()
			return
		end

		self.health = self.health - damage
		audio.play_squish_sound()

		if self.health <= 0 then
			self:die()
		else
			self:set_state(states.hit)
		end
	end

	return {
		box = { w = 0.7, h = 0.9, x = 0.15, y = 0.05 },
		gravity = 0,
		max_fall_speed = 0,
		max_health = cfg.max_health or 6,
		armor = cfg.armor or 0.5,
		damage = cfg.damage or 0.5,
		damages_shield = true,
		death_sound = "ratto",
		loot = cfg.loot or { xp = 30, gold = { min = 10, max = 30 }, health = { min = 0, max = 20 }, energy = { min = 0, max = 20 } },
		states = states,
		animations = animations,
		initial_state = "idle",
		on_hit = on_hit,
		clear_bolts = MagicBolt.clear_all,
	}
end

-- Expose bolt update/draw for Enemy.update/draw to call unconditionally
magician_common.update_bolts = MagicBolt.update_all
magician_common.draw_bolts = MagicBolt.draw_all
magician_common.destroy_bolt = bolt_impact

return magician_common
