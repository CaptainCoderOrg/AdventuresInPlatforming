local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local Animation = require('Animation')
local config = require('config')
local Effects = require("Effects")
local audio = require('audio')

local Projectile = {}

Projectile.__index = Projectile
Projectile.all = {}
Projectile.next_id = 1

-- Module-level table to avoid allocation each frame
local to_remove = {}

Projectile.animations = {
	AXE = Animation.create_definition(sprites.projectiles.axe, 4, {
		width = 8,
		height = 8,
	}),

    SHURIKEN = Animation.create_definition(sprites.projectiles.shuriken, 5, {
        width = 8,
        height = 8,
    })
}

--- Returns the Axe projectile specification.
--- Axe has an arcing trajectory with gravity, costs 1 stamina and 0 energy to throw.
---@return table Projectile spec with name, sprite, icon, damage, stamina_cost, energy_cost, create
function Projectile.get_axe()
    return {
        name = "Axe",
        sprite = sprites.projectiles.axe,
        icon = sprites.projectiles.axe_icon,
        damage = 1,
        stamina_cost = 1,
        energy_cost = 0,
        create = Projectile.create_axe,
    }
end

--- Returns the Shuriken projectile specification.
--- Shuriken travels in a straight line with no gravity, costs no stamina and 1 energy.
---@return table Projectile spec with name, sprite, icon, damage, stamina_cost, energy_cost, create
function Projectile.get_shuriken()
    return {
        name = "Shuriken",
        sprite = sprites.projectiles.shuriken,
        icon = sprites.projectiles.shuriken_icon,
        damage = 1,
        stamina_cost = 0,
        energy_cost = 1,
        create = Projectile.create_shuriken,
    }
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
        projectile.vy = math.min(20, projectile.vy + projectile.gravity_scale*dt)
        projectile.y = projectile.y + projectile.vy * dt

        projectile.animation:play(dt)

        if projectile.x < -2 or projectile.x > level_info.width + 2 or projectile.y > level_info.height + 2 then
            projectile.marked_for_destruction = true
        end

        local collision = world.move_trigger(projectile)
        if collision then
            projectile:on_collision(collision)
        end

        if projectile.marked_for_destruction then
            to_remove[#to_remove + 1] = projectile
        end
        projectile = next(Projectile.all, projectile)
    end

    for i = 1, #to_remove do
        local p = to_remove[i]
        world.remove_collider(p)
        Projectile.all[p] = nil
    end
end

--- Renders all active projectiles and their debug hitboxes if enabled.
function Projectile.draw()
    canvas.save()
    local projectile = next(Projectile.all)
    while projectile do
        projectile.animation:draw(
            projectile.x * sprites.tile_size,
            projectile.y * sprites.tile_size)

        if config.bounding_boxes == true then
            canvas.set_color("#FFFF00")
            canvas.draw_rect(
                (projectile.x + projectile.box.x) * sprites.tile_size,
                (projectile.y + projectile.box.y) * sprites.tile_size,
                projectile.box.w * sprites.tile_size,
                projectile.box.h * sprites.tile_size)
        end
        projectile = next(Projectile.all, projectile)
    end
    canvas.restore()
end

--- Handles projectile collision. Damages enemies, spawns hit effect, and marks for destruction.
---@param collision table Collision data {other: shape, x: number, y: number}
function Projectile:on_collision(collision)
    local direction = self.vx >= 0 and 1 or -1

    if collision.other and collision.other.owner and collision.other.owner.is_enemy then
        local enemy = collision.other.owner
        enemy:on_hit("projectile", self)
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
---@return table Projectile instance
function Projectile.new(name, animation_def, x, y, vx, vy, gravity_scale, direction, effect_callback, damage)
    if effect_callback == nil then effect_callback = Effects.create_hit end
	local self = setmetatable({}, Projectile)
    self.create_effect = effect_callback
	self.id = name .. "_" .. Projectile.next_id
	Projectile.next_id = Projectile.next_id + 1
	self.animation = Animation.new(animation_def, {
		flipped = direction > 0 and 1 or -1,
		reverse = true  -- Always play in reverse for correct spin direction
	})
	self.x = x
	self.y = y
	self.vx = vx
	self.vy = vy
	self.gravity_scale = gravity_scale
	self.damage = damage or 1
	self.box = { w = 0.5, h = 0.5, x = 0, y = 0 }
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
---@return table The created projectile instance
function Projectile.create_axe(x, y, direction)
    local axe_vx = direction*16
    local axe_vy = -3
    local axe_gravity = 20
    local damage = 1
    audio.play_axe_throw_sound()
    return Projectile.new("axe", Projectile.animations.AXE, x + 0.5, y + 0.25, axe_vx, axe_vy, axe_gravity, direction, nil, damage)
end

--- Creates and spawns a shuriken projectile with straight trajectory.
---@param x number Spawn X position in tile coordinates
---@param y number Spawn Y position in tile coordinates
---@param direction number Throw direction (-1 left, 1 right)
---@return table The created projectile instance
function Projectile.create_shuriken(x, y, direction)
    local velocity_x = direction*24
    local velocity_y = 0
    local gravity = 0
    local effect_callback = Effects.create_shuriken_hit
    local damage = 2
    audio.play_shuriken_throw_sound()
    return Projectile.new("shuriken", Projectile.animations.SHURIKEN, x + 0.5, y + 0.25, velocity_x, velocity_y, gravity, direction, effect_callback, damage)
end

return Projectile