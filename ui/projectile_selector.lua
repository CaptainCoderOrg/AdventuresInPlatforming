--- Projectile selector micro-widget for displaying current throwable
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")

local projectile_selector = {}
projectile_selector.__index = projectile_selector

---@param opts {x: number?, y: number?, alpha: number?}|nil Optional position and alpha settings
---@return projectile_selector widget instance
function projectile_selector.create(opts)
    opts = opts or {}
    local self = setmetatable({}, projectile_selector)
    self.x = opts.x or 8
    self.y = opts.y or 8
    self.alpha = opts.alpha or 0.9
    return self
end

---@param player {projectile: {icon: userdata}} Player with projectile.icon image property
---@return nil
function projectile_selector:draw(player)
    local scale = config.ui.SCALE
    canvas.save()
    canvas.set_global_alpha(self.alpha)
    -- 32 = widget height in base pixels (matches ability_selector_left sprite)
    canvas.translate(self.x, canvas.get_height() - 32 * scale - self.y)
    canvas.scale(scale, scale)
    canvas.draw_image(sprites.ui.ability_selector_left, 0, 0)
    canvas.draw_image(player.projectile.icon, 8, 8, 16, 16)
    canvas.restore()
end

return projectile_selector
