--- Projectile selector micro-widget for displaying current throwable
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")

local projectile_selector = {}
projectile_selector.__index = projectile_selector

-- Animation and layout constants
local LERP_SPEED = 8          -- Units per second for meter animation
local WIDGET_HEIGHT = 32      -- Must match ability_selector_left sprite for bottom-left anchoring
local METER_X = 36            -- Meter X offset from widget origin (right edge of selector + 4px)
local METER_Y = 1             -- Meter Y offset from widget origin
local PX_PER_UNIT = 5         -- Pixels per health/stamina point
local METER_HEIGHT = 10       -- Total meter sprite height in pixels
local BAR_HEIGHT = 6          -- Bar height in pixels
local BAR_Y_OFFSET = 2        -- Vertical offset for bar within meter
local SHINE_OPACITY = 0.7     -- Shine overlay relative opacity

--- Lerps a displayed value toward a target at a given speed.
---@param current number|nil Current displayed value (nil for first initialization)
---@param target number Target value to lerp toward
---@param speed number Lerp speed (units per second)
---@param dt number Delta time in seconds
---@return number Updated displayed value
local function lerp_toward(current, target, speed, dt)
    if current == nil then
        return target
    end
    if current < target then
        return math.min(current + speed * dt, target)
    elseif current > target then
        return math.max(current - speed * dt, target)
    end
    return current
end

--- Draws a horizontal meter with background, fill bar, shine overlay, and end cap.
---@param alpha number Widget alpha for shine calculation
---@param y number Y position of the meter
---@param max_value number Maximum meter value (determines width)
---@param displayed_value number Current displayed value (for fill width)
---@param fill_color string Fill bar color (e.g., "#FF0000")
---@param cap_sprite string Sprite key for the end cap
local function draw_meter(alpha, y, max_value, displayed_value, fill_color, cap_sprite)
    local meter_width = max_value * PX_PER_UNIT
    local bar_width = displayed_value * PX_PER_UNIT

    canvas.draw_image(sprites.ui.meter_background, METER_X, y, meter_width, METER_HEIGHT)
    canvas.set_fill_style(fill_color)
    canvas.fill_rect(METER_X, y + BAR_Y_OFFSET, bar_width, BAR_HEIGHT)
    canvas.set_global_alpha(alpha * SHINE_OPACITY)
    canvas.draw_image(sprites.ui.meter_shine, METER_X + 1, y, meter_width - 2, METER_HEIGHT)
    canvas.set_global_alpha(alpha)
    canvas.draw_image(cap_sprite, METER_X + meter_width, y)
end

---@param opts {x: number?, y: number?, alpha: number?}|nil Optional position and alpha settings
---@return projectile_selector widget instance
function projectile_selector.create(opts)
    opts = opts or {}
    local self = setmetatable({}, projectile_selector)
    self.x = opts.x or 8
    self.y = opts.y or 8
    self.alpha = opts.alpha or 0.7
    self.displayed_hp = nil -- Initialized on first update
    self.displayed_stamina = nil -- Initialized on first update
    self.displayed_energy = nil -- Initialized on first update
    return self
end

---@param dt number Delta time in seconds
---@param player table Player instance with health, stamina, and energy properties
function projectile_selector:update(dt, player)
    local target_hp = player.max_health - player.damage
    local target_stamina = player.max_stamina - player.stamina_used
    local target_energy = player.max_energy - player.energy_used

    self.displayed_hp = lerp_toward(self.displayed_hp, target_hp, LERP_SPEED, dt)
    self.displayed_stamina = lerp_toward(self.displayed_stamina, target_stamina, LERP_SPEED, dt)
    self.displayed_energy = lerp_toward(self.displayed_energy, target_energy, LERP_SPEED, dt)
end

---@param player table Player instance with projectile, health, stamina, and energy properties
function projectile_selector:draw(player)
    local scale = config.ui.SCALE
    canvas.save()
    canvas.set_global_alpha(self.alpha)
    canvas.translate(self.x, canvas.get_height() - WIDGET_HEIGHT * scale - self.y)
    canvas.scale(scale, scale)

    canvas.draw_image(sprites.ui.ability_selector_left, 0, 0)
    canvas.draw_image(player.projectile.icon, 8, 8, 16, 16)

    draw_meter(self.alpha, METER_Y, player.max_health, self.displayed_hp, "#FF0000", sprites.ui.meter_cap_red)
    draw_meter(self.alpha, METER_Y + METER_HEIGHT, player.max_stamina, self.displayed_stamina, "#00FF00", sprites.ui.meter_cap_green)
    draw_meter(self.alpha, METER_Y + METER_HEIGHT * 2, player.max_energy, self.displayed_energy, "#0088FF", sprites.ui.meter_cap_blue)

    canvas.restore()
end

return projectile_selector
