local sprites = require('sprites')
local canvas = require('canvas')
local Projectile = {}

Projectile.__index = Projectile
Projectile.all = {}
Projectile.next_id = 1

Projectile.animations = {
    AXE = sprites.create_animation("throwable_axe", 4, { width = 8, height = 8 }),
}

function Projectile.update(dt)
    -- print(dt)
    for _, projectile in ipairs(Projectile.all) do
        -- print("Updating " .. projectile.id)
        projectile.x = projectile.x + projectile.vx * dt

        projectile.vy = math.min(5, projectile.vy + projectile.gravity_scale*dt)

        projectile.y = projectile.y + projectile.vy * dt

    end
end

function Projectile.draw()
    canvas.save()
    for _, projectile in ipairs(Projectile.all) do
        sprites.draw_animation(projectile.animation, 
            projectile.x * sprites.tile_size, 
            projectile.y * sprites.tile_size)
    end
    canvas.restore()
end

function Projectile.new(name, animation, x, y, vx, vy, gravity_scale)
    local self = setmetatable({}, Projectile)
    self.id = name .. "_" .. Projectile.next_id
    Projectile.next_id = Projectile.next_id + 1
    self.animation = animation
    self.x = x
    self.y = y
    self.vx = vx
    self.vy = vy
    self.gravity_scale = gravity_scale
    table.insert(Projectile.all, self)
    print(#Projectile.all, "Projectiles")
    return self
end

function Projectile.create_axe(x, y, direction)
    print("Created axe")
    local axe_vx = direction*15
    local axe_vy = -2
    local axe_gravity = 8
    return Projectile.new("axe", Projectile.animations.AXE, x, y, axe_vx, axe_vy, axe_gravity)
end

return Projectile