local sprites = require('sprites')
local canvas = require('canvas')
local world = require('world')
local Projectile = {}

Projectile.__index = Projectile
Projectile.all = {}
Projectile.next_id = 1

Projectile.animations = {
    AXE = sprites.create_animation("throwable_axe", 4, { width = 8, height = 8 }),
}

function Projectile.update(dt)
    local to_remove = {}

    for projectile, _ in pairs(Projectile.all) do
        projectile.x = projectile.x + projectile.vx * dt
        projectile.vy = math.min(20, projectile.vy + projectile.gravity_scale*dt)
        projectile.y = projectile.y + projectile.vy * dt

        -- Advance animation
        projectile.animation.timer = projectile.animation.timer + 1
        if projectile.animation.timer >= projectile.animation.definition.speed then
            projectile.animation.timer = 0
            projectile.animation.frame = (projectile.animation.frame + 1) % projectile.animation.definition.frame_count
        end

        if projectile.x < -2 or projectile.x > 34 or projectile.y > 34 then
            projectile.marked_for_destruction = true
        end

        world.sync_position(projectile)
        if projectile.shape then
            local collisions = world.hc:collisions(projectile.shape)
            for other, sep in pairs(collisions) do
                -- Only collide with solid world geometry, not other triggers or player
                if world.shape_map[other.owner] == other and not (other.owner and other.owner.is_player) then
                    projectile:on_collision(other)
                end
            end
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
        sprites.draw_animation(projectile.animation,
            projectile.x * sprites.tile_size,
            projectile.y * sprites.tile_size)
    end
    canvas.restore()
end

function Projectile:on_collision(other)
    if other.owner then
        self.marked_for_destruction = true
    end
end

function Projectile.new(name, animation_def, x, y, vx, vy, gravity_scale, direction)
    local self = setmetatable({}, Projectile)
    self.id = name .. "_" .. Projectile.next_id
    Projectile.next_id = Projectile.next_id + 1
    self.animation = sprites.create_animation_state(animation_def, {
        flipped = direction > 0 and 1 or -1
    })
    self.x = x
    self.y = y
    self.vx = vx
    self.vy = vy
    self.gravity_scale = gravity_scale
    self.box = { w = 0.25, h = 0.25, x = 0, y = 0 }
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

return Projectile