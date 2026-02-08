--- Gnomo Axe Thrower: A ground-based enemy that throws arcing axes at the player.
--- States: idle (face player), throw (launch axes), hit (take damage),
---         run_away (tactical retreat), death
--- Health: 4 HP. Contact damage: 1. Axe damage: 1.
local Animation = require('Animation')
local sprites = require('sprites')
local canvas = require('canvas')
local config = require('config')
local combat = require('combat')
local common = require('Enemies/common')
local prop_common = require('Prop/common')
local world = require('world')
local audio = require('audio')
local Effects = require('Effects')

local gnomo = {}

-- Behavior constants
local IDLE_DURATION = 2.5            -- Seconds before attacking
local RUN_SPEED = 4                  -- Tiles/sec
local RUN_AWAY_DURATION = 2.0        -- Seconds max run time

-- Axe constants
local AXE_VX = 8                     -- Tiles/sec horizontal speed
local AXE_VY_MIN = -10               -- Tiles/sec min initial vertical speed (negative = up)
local AXE_VY_MAX = -6                -- Tiles/sec max initial vertical speed
local AXE_GRAVITY = 20               -- Tiles/sec^2
local AXE_MAX_FALL_SPEED = 20        -- Tiles/sec
local AXE_DAMAGE = 1
local AXE_WALL_CHECK_INTERVAL = 0.05 -- Seconds between wall collision checks

-- Static tables (hoisted to avoid per-call allocation)
local RUN_AWAY_DISTANCES = { 5, 6, 4, 7, 3 }

-- Animation definitions (using combined spritesheet)
local sheet = sprites.enemies.gnomo.sheet

gnomo.animations = {
	ATTACK = Animation.create_definition(sheet, 8, { ms_per_frame = 60, loop = false }),
	IDLE = Animation.create_definition(sheet, 5, { ms_per_frame = 150, row = 1 }),
	JUMP = Animation.create_definition(sheet, 9, { ms_per_frame = 80, loop = false, row = 2 }),
	RUN = Animation.create_definition(sheet, 6, { ms_per_frame = 100, row = 3 }),
	HIT = Animation.create_definition(sheet, 5, { ms_per_frame = 120, loop = false, row = 4 }),
	DEATH = Animation.create_definition(sheet, 6, { ms_per_frame = 100, loop = false, row = 5 }),
	AXE = Animation.create_definition(sprites.projectiles.axe, 4, { ms_per_frame = 50, width = 8, height = 8 }),
}

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

--- Check if a collision shape is solid world geometry
---@param shape table The collision shape to check
---@param ignore_bridges boolean|nil If true, skip one-way platforms/bridges
---@return boolean True if solid geometry
local function is_solid_geometry(shape, ignore_bridges)
	if shape.is_probe or shape.is_trigger or shape.is_hitbox then
		return false
	end
	local owner = shape.owner
	if owner and (owner.is_enemy or owner.is_player) then
		return false
	end
	if ignore_bridges and owner and owner.is_bridge then
		return false
	end
	return true
end

--- Check if there's a clear path from enemy to target position
---@param enemy table The gnomo enemy
---@param target_x number Target X in tiles
---@return boolean True if path is clear
local function has_clear_path(enemy, target_x)
	local ts = sprites.tile_size
	local enemy_cx = (enemy.x + enemy.box.x + enemy.box.w / 2) * ts
	local enemy_cy = (enemy.y + enemy.box.y + enemy.box.h / 2) * ts
	local target_cx = target_x * ts

	local dx = target_cx - enemy_cx
	local dist = math.abs(dx)
	if dist < 1 then return true end

	local dir_x = dx / dist
	local enemy_shape = world.shape_map[enemy]

	for shape, hits in pairs(world.hc:raycast(enemy_cx, enemy_cy, dir_x, 0, dist)) do
		if shape ~= enemy_shape and is_solid_geometry(shape) and next(hits) then
			return false
		end
	end
	return true
end

--- Find a valid run-away position away from player
---@param enemy table The gnomo enemy
---@return number|nil Target X position, or nil if none found
local function find_run_away_position(enemy)
	if not enemy.target_player then return nil end

	local player = enemy.target_player
	local player_x = player.x
	local gnomo_x = enemy.x
	local gnomo_y = enemy.y + enemy.box.y + enemy.box.h

	local best_x = nil
	local best_dist = math.huge

	for _, dist in ipairs(RUN_AWAY_DISTANCES) do
		-- Try both sides of player (inline to avoid table allocation)
		for sign = 1, -1, -2 do
			local test_x = player_x + dist * sign
			if world.point_has_ground(test_x, gnomo_y + 1) then
				if has_clear_path(enemy, test_x) then
					local dist_to_gnomo = math.abs(test_x - gnomo_x)
					if dist_to_gnomo < best_dist then
						best_dist = dist_to_gnomo
						best_x = test_x
					end
				end
			end
		end
	end

	return best_x
end

--------------------------------------------------------------------------------
-- GnomoAxe projectile pool
--------------------------------------------------------------------------------
local GnomoAxe = {}
GnomoAxe.all = {}

-- Dirty flags for single-pass update/draw
GnomoAxe.needs_update = true
GnomoAxe.needs_draw = false

-- Shared box (8x8 sprite, centered)
local AXE_BOX = { x = 0, y = 0, w = 0.5, h = 0.5 }
local axe_anim_opts = { flipped = 1 }

--- Spawn a new gnomo axe projectile
---@param x number X position in tiles
---@param y number Y position in tiles
---@param direction number -1 or 1 for left/right
---@return table axe The created GnomoAxe instance
function GnomoAxe.spawn(x, y, direction)
	axe_anim_opts.flipped = direction

	-- Random vy for trajectory variation
	local vy = AXE_VY_MIN + math.random() * (AXE_VY_MAX - AXE_VY_MIN)

	local axe = {
		x = x,
		y = y,
		vx = direction * AXE_VX,
		vy = vy,
		direction = direction,
		box = AXE_BOX,
		animation = Animation.new(gnomo.animations.AXE, axe_anim_opts),
		marked_for_destruction = false,
		debug_color = "#FFFF00",  -- Yellow for projectile
		wall_check_timer = 0,
	}

	world.add_trigger_collider(axe)
	combat.add(axe)

	GnomoAxe.all[#GnomoAxe.all + 1] = axe
	return axe
end

--- Spawn a gnomo axe with explicit velocity components (used by boss phase 1)
--- These axes travel in a straight line (no gravity) and ignore one-way platforms.
---@param x number X position in tiles
---@param y number Y position in tiles
---@param vx number Horizontal velocity in tiles/sec
---@param vy number Vertical velocity in tiles/sec
---@return table axe The created GnomoAxe instance
function GnomoAxe.spawn_with_velocity(x, y, vx, vy)
	local direction = vx >= 0 and 1 or -1
	axe_anim_opts.flipped = direction

	local axe = {
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		direction = direction,
		box = AXE_BOX,
		animation = Animation.new(gnomo.animations.AXE, axe_anim_opts),
		marked_for_destruction = false,
		debug_color = "#FFFF00",  -- Yellow for projectile
		wall_check_timer = 0,
		no_gravity = true,        -- Straight line trajectory
	}

	world.add_trigger_collider(axe)
	combat.add(axe)

	GnomoAxe.all[#GnomoAxe.all + 1] = axe
	return axe
end

--- Check if axe hit a wall
---@param axe table GnomoAxe instance
---@return boolean True if hit solid geometry
local function axe_hit_wall(axe)
	local shape = world.trigger_map[axe]
	if not shape then return false end

	local ts = sprites.tile_size
	local px = (axe.x + axe.box.x) * ts
	local py = (axe.y + axe.box.y) * ts
	shape:moveTo(px + axe.box.w * ts / 2, py + axe.box.h * ts / 2)

	for other, _ in pairs(world.hc:collisions(shape)) do
		if is_solid_geometry(other, true) then
			return true
		end
	end
	return false
end

--- Update all gnomo axes
---@param dt number Delta time in seconds
---@param player table Player instance for collision
---@param level_info table Level dimensions
function GnomoAxe.update_all(dt, player, level_info)
	if not GnomoAxe.needs_update then return end
	GnomoAxe.needs_update = false
	GnomoAxe.needs_draw = true

	local i = 1
	while i <= #GnomoAxe.all do
		local axe = GnomoAxe.all[i]
		if axe.marked_for_destruction then
			world.remove_trigger_collider(axe)
			combat.remove(axe)
			GnomoAxe.all[i] = GnomoAxe.all[#GnomoAxe.all]
			GnomoAxe.all[#GnomoAxe.all] = nil
		else
			-- Apply gravity (unless no_gravity flag is set)
			if not axe.no_gravity then
				axe.vy = math.min(AXE_MAX_FALL_SPEED, axe.vy + AXE_GRAVITY * dt)
			end

			-- Move
			axe.x = axe.x + axe.vx * dt
			axe.y = axe.y + axe.vy * dt

			-- Update combat position
			combat.update(axe)

			-- Animate
			axe.animation:play(dt)

			-- Check bounds (remove if off-screen)
			if level_info then
				if axe.x < -2 or axe.x > level_info.width + 2 or
				   axe.y < -2 or axe.y > level_info.height + 2 then
					axe.marked_for_destruction = true
				end
			end

			-- Wall collision check (throttled to reduce HC queries)
			axe.wall_check_timer = axe.wall_check_timer + dt
			if not axe.marked_for_destruction and axe.wall_check_timer >= AXE_WALL_CHECK_INTERVAL then
				axe.wall_check_timer = 0
				if axe_hit_wall(axe) then
					axe.marked_for_destruction = true
					Effects.create_hit(axe.x, axe.y, axe.direction)
					audio.play_solid_sound()
				end
			end

			-- Check player damage
			if not axe.marked_for_destruction and prop_common.damage_player(axe, player, AXE_DAMAGE) then
				axe.marked_for_destruction = true
			end

			i = i + 1
		end
	end
end

--- Draw all gnomo axes.
--- Called from main.lua after Enemy.draw to render axes independently of gnomo visibility.
function GnomoAxe.draw_all()
	if not GnomoAxe.needs_draw then return end
	GnomoAxe.needs_draw = false
	GnomoAxe.needs_update = true

	for i = 1, #GnomoAxe.all do
		local axe = GnomoAxe.all[i]
		if not axe.marked_for_destruction then
			axe.animation:draw(sprites.px(axe.x), sprites.px(axe.y))

			-- Debug bounding box
			if config.bounding_boxes and axe.box then
				local bx = (axe.x + axe.box.x) * sprites.tile_size
				local by = (axe.y + axe.box.y) * sprites.tile_size
				local bw = axe.box.w * sprites.tile_size
				local bh = axe.box.h * sprites.tile_size
				canvas.draw_rect(bx, by, bw, bh, axe.debug_color)
			end
		end
	end
end

--- Clear all gnomo axes and remove their colliders.
--- Called from cleanup_level in main.lua to prevent orphaned colliders.
function GnomoAxe.clear_all()
	for i = 1, #GnomoAxe.all do
		local axe = GnomoAxe.all[i]
		world.remove_trigger_collider(axe)
		combat.remove(axe)
	end
	GnomoAxe.all = {}
	GnomoAxe.needs_update = true
	GnomoAxe.needs_draw = false
end

--------------------------------------------------------------------------------
-- State helper functions
--------------------------------------------------------------------------------

--- Face the player
---@param enemy table The gnomo enemy
local function face_player(enemy)
	enemy.direction = common.direction_to_player(enemy)
	if enemy.animation then
		enemy.animation.flipped = enemy.direction
	end
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

gnomo.states = {}

gnomo.states.idle = {
	name = "idle",
	start = function(enemy, _)
		common.set_animation(enemy, gnomo.animations.IDLE)
		enemy.vx = 0
		enemy.idle_timer = IDLE_DURATION
	end,
	update = function(enemy, dt)
		common.apply_gravity(enemy, dt)
		face_player(enemy)

		enemy.idle_timer = enemy.idle_timer - dt
		if enemy.idle_timer <= 0 then
			enemy:set_state(gnomo.states.throw)
		end
	end,
	draw = common.draw,
}

gnomo.states.throw = {
	name = "throw",
	start = function(enemy, _)
		common.set_animation(enemy, gnomo.animations.ATTACK)
		enemy.vx = 0
		face_player(enemy)
		enemy.axes_to_throw = 3
		enemy.axes_thrown = 0
		enemy.axe_spawned_this_anim = false
	end,
	update = function(enemy, dt)
		common.apply_gravity(enemy, dt)

		-- Spawn axe on frame 6 (index 5)
		if not enemy.axe_spawned_this_anim and enemy.animation.frame >= 5 then
			enemy.axe_spawned_this_anim = true
			enemy.axes_thrown = enemy.axes_thrown + 1
			GnomoAxe.spawn(enemy.x + 0.25, enemy.y + 0.5, enemy.direction)
			audio.play_axe_throw_sound()
		end

		if enemy.animation:is_finished() then
			if enemy.axes_thrown < enemy.axes_to_throw then
				common.set_animation(enemy, gnomo.animations.ATTACK)
				enemy.axe_spawned_this_anim = false
				face_player(enemy)
			else
				enemy:set_state(gnomo.states.idle)
			end
		end
	end,
	draw = common.draw,
}

gnomo.states.hit = {
	name = "hit",
	start = function(enemy, _)
		common.set_animation(enemy, gnomo.animations.HIT)
		enemy.vx = 0
	end,
	update = function(enemy, dt)
		common.apply_gravity(enemy, dt)
		if enemy.animation:is_finished() then
			enemy:set_state(gnomo.states.run_away)
		end
	end,
	draw = common.draw,
}

gnomo.states.run_away = {
	name = "run_away",
	start = function(enemy, _)
		common.set_animation(enemy, gnomo.animations.RUN)
		enemy.invulnerable = true
		enemy.run_away_timer = RUN_AWAY_DURATION
		combat.remove(enemy)

		local target_x = find_run_away_position(enemy)
		if target_x then
			enemy.run_away_target_x = target_x
			enemy.run_away_direction = target_x < enemy.x and -1 or 1
		elseif enemy.target_player then
			enemy.run_away_target_x = nil
			enemy.run_away_direction = enemy.target_player.x < enemy.x and 1 or -1
		else
			enemy.run_away_target_x = nil
			enemy.run_away_direction = -enemy.direction
		end

		enemy.direction = enemy.run_away_direction
		enemy.animation.flipped = enemy.direction
	end,
	update = function(enemy, dt)
		common.apply_gravity(enemy, dt)

		enemy.vx = enemy.run_away_direction * RUN_SPEED
		if common.is_blocked(enemy) then
			enemy.vx = 0
		end

		local reached = enemy.run_away_target_x and math.abs(enemy.x - enemy.run_away_target_x) < 0.5
		enemy.run_away_timer = enemy.run_away_timer - dt

		if reached or enemy.run_away_timer <= 0 then
			enemy.vx = 0
			enemy.invulnerable = false
			combat.add(enemy)
			face_player(enemy)
			enemy:set_state(gnomo.states.throw)
		end
	end,
	draw = common.draw,
}

gnomo.states.death = common.create_death_state(gnomo.animations.DEATH)

--------------------------------------------------------------------------------
-- Custom on_hit handler (doesn't reset animation if already in hit state)
--------------------------------------------------------------------------------

---@param self table The gnomo enemy
---@param _source_type string "player", "weapon", or "projectile" (unused)
---@param source table Hit source with optional .damage, .vx, .x, .is_crit
local function gnomo_on_hit(self, _source_type, source)
	if self.invulnerable then return end

	local damage = (source and source.damage) or 1
	local is_crit = source and source.is_crit

	-- Apply armor reduction, then crit multiplier
	damage = math.max(0, damage - self:get_armor())
	if is_crit then
		damage = damage * 2
	end

	Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage, is_crit)

	if damage <= 0 then
		audio.play_solid_sound()
		return
	end

	self.health = self.health - damage
	audio.play_squish_sound()

	-- Determine knockback direction
	if source and source.vx then
		self.hit_direction = source.vx > 0 and 1 or -1
	elseif source and source.x then
		self.hit_direction = source.x < self.x and 1 or -1
	else
		self.hit_direction = -1
	end

	if self.health <= 0 then
		self:die()
	elseif self.state ~= gnomo.states.hit then
		-- Only transition to hit state if not already in it
		self:set_state(gnomo.states.hit)
	end
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

return {
	box = { w = 0.775, h = 0.775, x = 0.1125, y = 0.175 },
	gravity = 1.5,
	max_fall_speed = 20,
	max_health = 4,
	damage = 1,
	loot = { xp = 6, gold = { min = 3, max = 5 } },
	states = gnomo.states,
	animations = gnomo.animations,
	initial_state = "idle",
	on_hit = gnomo_on_hit,
	update_axes = GnomoAxe.update_all,
	draw_axes = GnomoAxe.draw_all,
	clear_axes = GnomoAxe.clear_all,
	spawn_axe_with_velocity = GnomoAxe.spawn_with_velocity,
}
