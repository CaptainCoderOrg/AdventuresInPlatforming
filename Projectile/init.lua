local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local Animation = require('Animation')
local config = require('config')
local Effects = require("Effects")
local audio = require('audio')
local prop_common = require('Prop.common')
local upgrade_effects = require('upgrade/effects')

local Projectile = {}

Projectile.__index = Projectile
Projectile.all = {}
Projectile.next_id = 1

-- Module-level tables to avoid allocation each frame
local to_remove = {}
local lever_hitbox = { x = 0, y = 0, w = 0, h = 0 }
local _projectile_hit_source = { damage = 0, vx = 0, is_crit = false }

-- Debug color constant (avoid string allocation each frame)
local DEBUG_COLOR_YELLOW = "#FFFF00"

Projectile.animations = {
	AXE = Animation.create_definition(sprites.projectiles.axe, 4, {
		width = 8,
		height = 8,
	}),

    SHURIKEN = Animation.create_definition(sprites.projectiles.shuriken, 5, {
        width = 8,
        height = 8,
    }),
}

-- Cached projectile specs (populated after create functions are defined below)
local _axe_spec
local _shuriken_spec

--- Returns the cached Axe projectile specification.
--- Axe has an arcing trajectory with gravity, costs 2 stamina and 0 energy to throw.
---@return table Projectile spec with name, sprite, icon, damage, stamina_cost, energy_cost, create
function Projectile.get_axe()
    return _axe_spec
end

--- Returns the cached Shuriken projectile specification.
--- Shuriken travels in a straight line with no gravity, costs no stamina and 1 energy.
---@return table Projectile spec with name, sprite, icon, damage, stamina_cost, energy_cost, create
function Projectile.get_shuriken()
    return _shuriken_spec
end

--- Check if projectile hits a lever using combat spatial index
---@param projectile table The projectile to check
---@return boolean True if lever was hit
local function check_lever_hit(projectile)
    lever_hitbox.x = projectile.x + projectile.box.x
    lever_hitbox.y = projectile.y + projectile.box.y
    lever_hitbox.w = projectile.box.w
    lever_hitbox.h = projectile.box.h
    if prop_common.check_lever_hit(lever_hitbox) then
        local direction = projectile.vx >= 0 and 1 or -1
        projectile.create_effect(projectile.x, projectile.y, direction)
        projectile.marked_for_destruction = true
        return true
    end
    return false
end

--- Updates all active projectiles. Applies physics, checks collisions, and removes destroyed projectiles.
---@param dt number Delta time in seconds
---@param level_info table Level metadata with width and height for bounds checking
function Projectile.update(dt, level_info)
    -- Clear module-level table instead of allocating new one
    for i = 1, #to_remove do to_remove[i] = nil end

    local projectile = next(Projectile.all)
    while projectile do
        projectile.x = projectile.x + projectile.vx * dt
        projectile.vy = math.min(20, projectile.vy + projectile.gravity_scale * dt)
        projectile.y = projectile.y + projectile.vy * dt

        projectile.animation:play(dt)

        -- Skip collision checks for out-of-bounds projectiles
        if projectile.x < -2 or projectile.x > level_info.width + 2 or projectile.y > level_info.height + 2 then
            projectile.marked_for_destruction = true
        elseif not check_lever_hit(projectile) then
            -- Check world collision only if lever wasn't hit
            -- (triggers can't detect other triggers, so lever check uses combat system)
            local collision = world.move_trigger(projectile)
            if collision then
                projectile:on_collision(collision)
            end
        end

        -- Expire projectiles with a time-to-live (after collision so last frame still collides)
        if projectile.ttl then
            projectile.ttl = projectile.ttl - dt
            if projectile.ttl <= 0 then
                projectile.marked_for_destruction = true
            end
        end

        if projectile.marked_for_destruction then
            to_remove[#to_remove + 1] = projectile
        end
        projectile = next(Projectile.all, projectile)
    end

    for i = 1, #to_remove do
        local p = to_remove[i]
        world.remove_trigger_collider(p)
        Projectile.all[p] = nil
    end
end

--- Renders all active projectiles and their debug hitboxes if enabled.
---@param camera table Camera instance for viewport culling
function Projectile.draw(camera)
    local debug_mode = config.bounding_boxes
    local projectile = next(Projectile.all)
    while projectile do
        -- Smaller margin (1 tile) since projectiles are small and fast-moving
        if camera:is_visible(projectile, sprites.tile_size, 1) then
            projectile.animation:draw(
                sprites.px(projectile.x),
                sprites.px(projectile.y))

            if debug_mode then
                canvas.draw_rect(
                    (projectile.x + projectile.box.x) * sprites.tile_size,
                    (projectile.y + projectile.box.y) * sprites.tile_size,
                    projectile.box.w * sprites.tile_size,
                    projectile.box.h * sprites.tile_size,
                    DEBUG_COLOR_YELLOW)
            end
        end
        projectile = next(Projectile.all, projectile)
    end
end

--- Handles projectile collision. Damages enemies, spawns hit effect, and marks for destruction.
---@param collision table Collision data {other: shape, x: number, y: number}
function Projectile:on_collision(collision)
    local direction = self.vx >= 0 and 1 or -1

    if collision.other and collision.other.is_projectile_collider then
        -- Hit a projectile blocker (e.g., club, shield) - break but no damage
        audio.play_solid_sound()
    elseif collision.other and collision.other.owner and collision.other.owner.is_enemy then
        local enemy = collision.other.owner
        -- Roll for critical hit if owner (player) exists (multiplier applied after armor by enemy)
        local crit_chance = self.owner and self.owner.critical_percent and self.owner:critical_percent() or 0
        local is_crit = math.random() * 100 < crit_chance
        _projectile_hit_source.damage = self.damage
        _projectile_hit_source.vx = self.vx
        _projectile_hit_source.is_crit = is_crit
        enemy:on_hit("projectile", _projectile_hit_source)
    else
        audio.play_solid_sound()
    end

    self.create_effect(collision.x - 0.25, collision.y - 0.25, direction)
    self.marked_for_destruction = true
end

--- Creates a new projectile instance with physics and collision.
---@param name string Identifier prefix for the projectile
---@param animation_def table Animation definition from Projectile.animations
---@param x number Initial X position in tile coordinates
---@param y number Initial Y position in tile coordinates
---@param vx number Horizontal velocity in tiles per second
---@param vy number Vertical velocity in tiles per second
---@param gravity_scale number Gravity multiplier (0 for no gravity)
---@param direction number Facing direction (-1 left, 1 right)
---@param effect_callback function|nil Effect spawner on collision (defaults to Effects.create_hit)
---@param damage number|nil Damage dealt to enemies (defaults to 1)
---@param owner table|nil Player who threw this projectile (for critical hits)
---@param options table|nil Optional overrides: box_w, box_h, ttl, reverse
---@return table Projectile instance
function Projectile.new(name, animation_def, x, y, vx, vy, gravity_scale, direction, effect_callback, damage, owner, options)
	options = options or {}
	local self = setmetatable({}, Projectile)
    self.create_effect = effect_callback or Effects.create_hit
	self.id = name .. "_" .. Projectile.next_id
	Projectile.next_id = Projectile.next_id + 1
	local reverse = options.reverse == nil and true or options.reverse
	self.animation = Animation.new(animation_def, {
		flipped = direction > 0 and 1 or -1,
		reverse = reverse,
	})
	self.x = x
	self.y = y
	self.vx = vx
	self.vy = vy
	self.gravity_scale = gravity_scale
	self.damage = damage or 1
	self.owner = owner
	self.box = { w = options.box_w or 0.5, h = options.box_h or 0.5, x = 0, y = 0 }
	self.ttl = options.ttl
	self.is_projectile = true
	self.marked_for_destruction = false
	self.shape = world.add_trigger_collider(self)
	Projectile.all[self] = true
	return self
end

--- Creates and spawns an axe projectile with arcing trajectory.
---@param x number Spawn X position in tile coordinates
---@param y number Spawn Y position in tile coordinates
---@param direction number Throw direction (-1 left, 1 right)
---@param owner table|nil Player who threw this projectile (for critical hits)
---@return table The created projectile instance
function Projectile.create_axe(x, y, direction, owner)
    audio.play_axe_throw_sound()
    local damage = upgrade_effects.get_projectile_damage(owner, "throwing_axe", 1)
    return Projectile.new("axe", Projectile.animations.AXE, x + 0.5, y + 0.25, direction * 16, -3, 20, direction, nil, damage, owner)
end

--- Creates and spawns a shuriken projectile with straight trajectory.
---@param x number Spawn X position in tile coordinates
---@param y number Spawn Y position in tile coordinates
---@param direction number Throw direction (-1 left, 1 right)
---@param owner table|nil Player who threw this projectile (for critical hits)
---@return table The created projectile instance
function Projectile.create_shuriken(x, y, direction, owner)
    audio.play_shuriken_throw_sound()
    return Projectile.new("shuriken", Projectile.animations.SHURIKEN, x + 0.5, y + 0.25, direction * 24, 0, 0, direction, Effects.create_shuriken_hit, 2, owner)
end

-- Initialize cached projectile specs (after create functions are defined)
_axe_spec = {
    name = "Axe",
    sprite = sprites.projectiles.axe,
    icon = sprites.projectiles.axe_icon,
    damage = 1,
    stamina_cost = 2,
    energy_cost = 0,
    create = Projectile.create_axe,
}
_shuriken_spec = {
    name = "Shuriken",
    sprite = sprites.projectiles.shuriken,
    icon = sprites.projectiles.shuriken_icon,
    damage = 2,
    stamina_cost = 0,
    energy_cost = 1,
    create = Projectile.create_shuriken,
}

return Projectile