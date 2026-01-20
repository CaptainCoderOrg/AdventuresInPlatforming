--- Projectile selector micro-widget for displaying current throwable
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")

local projectile_selector = {}
projectile_selector.__index = projectile_selector

-- Animation and layout constants
local LERP_SPEED = 8          -- HP units per second for health bar animation
local WIDGET_HEIGHT = 32      -- Must match ability_selector_left sprite for bottom-left anchoring
local METER_X = 36            -- Meter X offset from widget origin (right edge of selector + 4px)
local METER_Y = 1             -- Meter Y offset from widget origin
local PX_PER_HP = 5           -- Pixels per health point
local METER_HEIGHT = 10       -- Total meter sprite height in pixels
local BAR_HEIGHT = 6          -- Health bar height in pixels
local BAR_Y_OFFSET = 2        -- Vertical offset for health bar within meter
local SHINE_OPACITY = 0.7     -- Shine overlay relative opacity

---@param opts {x: number?, y: number?, alpha: number?}|nil Optional position and alpha settings
---@return projectile_selector widget instance
function projectile_selector.create(opts)
    opts = opts or {}
    local self = setmetatable({}, projectile_selector)
    self.x = opts.x or 8
    self.y = opts.y or 8
    self.alpha = opts.alpha or 0.7
    self.displayed_hp = nil -- Initialized on first update
    return self
end

---@param dt number Delta time in seconds
---@param player {max_health: number, damage: number} Player with health properties
function projectile_selector:update(dt, player)
    local target_hp = player.max_health - player.damage
    -- Initialize on first update
    if self.displayed_hp == nil then
        self.displayed_hp = target_hp
        return
    end
    -- Lerp toward target
    if self.displayed_hp < target_hp then
        self.displayed_hp = math.min(self.displayed_hp + LERP_SPEED * dt, target_hp)
    elseif self.displayed_hp > target_hp then
        self.displayed_hp = math.max(self.displayed_hp - LERP_SPEED * dt, target_hp)
    end
end

---@param player {projectile: {icon: userdata}, max_health: number} Player with projectile and health properties
function projectile_selector:draw(player)
    local scale = config.ui.SCALE
    canvas.save()
    canvas.set_global_alpha(self.alpha)
    canvas.translate(self.x, canvas.get_height() - WIDGET_HEIGHT * scale - self.y)
    canvas.scale(scale, scale)

    canvas.draw_image(sprites.ui.ability_selector_left, 0, 0)
    canvas.draw_image(player.projectile.icon, 8, 8, 16, 16)

    local meter_width = player.max_health * PX_PER_HP
    local bar_width = self.displayed_hp * PX_PER_HP

    canvas.draw_image(sprites.ui.meter_background, METER_X, METER_Y, meter_width, METER_HEIGHT)
    canvas.set_fill_style("#FF0000")
    canvas.fill_rect(METER_X, METER_Y + BAR_Y_OFFSET, bar_width, BAR_HEIGHT)
    canvas.set_global_alpha(self.alpha * SHINE_OPACITY)
    canvas.draw_image(sprites.ui.meter_shine, METER_X + 1, METER_Y, meter_width - 2, METER_HEIGHT)
    canvas.set_global_alpha(self.alpha)
    canvas.draw_image(sprites.ui.meter_cap_red, METER_X + meter_width, METER_Y)

    canvas.restore()
end

return projectile_selector
