local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local Animation = require('Animation')
local config = require('config')
local Effects = require("Effects")
local Projectile = {}

Projectile.__index = Projectile
Projectile.all = {}
Projectile.next_id = 1

Projectile.animations = {
	AXE = Animation.create_definition("throwable_axe", 4, {
		width = 8,
		height = 8,
	}),

    SHURIKEN = Animation.create_definition("shuriken", 5, {
        width = 8,
        height = 8,
    })
}

function Projectile.get_axe()
    return {
        name = "Axe",
        sprite = "axe",
        create = Projectile.create_axe,
    }
end

function Projectile.get_shuriken()
    return {
        name = "Shuriken",
        sprite = "shuriken",
        create = Projectile.create_shuriken,
    }
end

function Projectile.update(dt, level_info)
    local to_remove = {}

    for projectile, _ in pairs(Projectile.all) do
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
            table.insert(to_remove, projectile)
        end
    end

    for _, projectile in ipairs(to_remove) do
        world.remove_collider(projectile)
        Projectile.all[projectile] = nil
    end
end

function Projectile.draw()
    canvas.save()
    for projectile, _ in pairs(Projectile.all) do
        projectile.animation:draw(
            projectile.x * sprites.tile_size,
            projectile.y * sprites.tile_size)

        -- Draw debug hitbox in bright yellow
        if config.bounding_boxes == true then
            canvas.set_color("#FFFF00")  -- Bright yellow
            canvas.draw_rect(
                (projectile.x + projectile.box.x) * sprites.tile_size,
                (projectile.y + projectile.box.y) * sprites.tile_size,
                projectile.box.w * sprites.tile_size,
                projectile.box.h * sprites.tile_size)
        end
    end
    canvas.restore()
end

---@param collision table {other, x, y}
function Projectile:on_collision(collision)
    local direction = self.vx >= 0 and 1 or -1
    self.create_effect(collision.x - 0.25, collision.y - 0.25, direction)
    self.marked_for_destruction = true
end

function Projectile.new(name, animation_def, x, y, vx, vy, gravity_scale, direction, effect_callback)
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
	self.box = { w = 0.5, h = 0.5, x = 0, y = 0 }
	self.is_projectile = true
	self.marked_for_destruction = false
	self.shape = world.add_trigger_collider(self)
	Projectile.all[self] = true
	return self
end

function Projectile.create_axe(x, y, direction)
    local axe_vx = direction*16
    local axe_vy = -3
    local axe_gravity = 20
    return Projectile.new("axe", Projectile.animations.AXE, x + 0.5, y + 0.25, axe_vx, axe_vy, axe_gravity, direction)
end

function Projectile.create_shuriken(x, y, direction)
    local velocity_x = direction*24
    local velocity_y = 0
    local gravity = 0
    local effect_callback = Effects.create_shuriken_hit
    return Projectile.new("shuriken", Projectile.animations.SHURIKEN, x + 0.5, y + 0.25, velocity_x, velocity_y, gravity, direction, effect_callback)
end

return Projectile