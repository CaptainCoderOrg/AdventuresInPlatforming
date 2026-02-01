--- Player resource display widget showing health, stamina, energy meters and current throwable
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")

---@class projectile_selector
---@field x number X position offset from screen edge
---@field y number Y position offset from screen bottom
---@field alpha number Widget opacity (0-1)
---@field displayed_hp number|nil Lerped health value for smooth animation
---@field displayed_stamina number|nil Lerped stamina value for smooth animation
---@field displayed_energy number|nil Lerped energy value for smooth animation
---@field fatigue_pulse_timer number Timer for fatigue color pulsing (seconds)
---@field energy_flash_timer number Timer for energy bar flash effect (seconds)

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

--- Returns a pulsating orange-to-red color for fatigue visualization.
---@param timer number Pulse timer in seconds
---@return string Hex color string
local function get_fatigue_color(timer)
    -- 2Hz pulse (4 * pi/2 radians/sec) feels urgent without being seizure-inducing
    local t = (math.sin(timer * math.pi * 4) + 1) / 2
    -- Interpolate green channel between 136 (orange #FF8800) and 0 (red #FF0000)
    local green = math.floor(136 * (1 - t))
    return string.format("#FF%02X00", green)
end

--- Returns a flickering opacity for energy flash overlay.
---@param timer number Flash timer in seconds
---@return number Opacity value (0-1)
local function get_energy_flash_opacity(timer)
    -- 8Hz flicker for rapid on/off effect
    local t = (math.sin(timer * math.pi * 16) + 1) / 2
    return t * 0.5  -- Max 50% opacity
end

--- Draws the stamina meter with fatigue support (debt shown as pulsing orange/red bar).
---@param alpha number Widget alpha for shine calculation
---@param y number Y position of the meter
---@param player table Player instance with stamina properties
---@param displayed_stamina number Current displayed stamina value (can be negative)
---@param fatigue_timer number Timer for fatigue color pulsing
local function draw_stamina_meter(alpha, y, player, displayed_stamina, fatigue_timer)
    local meter_width = player.max_stamina * PX_PER_UNIT

    canvas.draw_image(sprites.ui.meter_background, METER_X, y, meter_width, METER_HEIGHT)

    if displayed_stamina >= 0 then
        -- Normal: green bar
        local bar_width = displayed_stamina * PX_PER_UNIT
        canvas.set_fill_style("#00FF00")
        canvas.fill_rect(METER_X, y + BAR_Y_OFFSET, bar_width, BAR_HEIGHT)
    else
        -- Fatigue: pulsating orange/red bar showing debt
        local debt = math.abs(displayed_stamina)
        local bar_width = debt * PX_PER_UNIT
        canvas.set_fill_style(get_fatigue_color(fatigue_timer))
        canvas.fill_rect(METER_X, y + BAR_Y_OFFSET, bar_width, BAR_HEIGHT)
    end

    canvas.set_global_alpha(alpha * SHINE_OPACITY)
    canvas.draw_image(sprites.ui.meter_shine, METER_X + 1, y, meter_width - 2, METER_HEIGHT)
    canvas.set_global_alpha(alpha)

    local cap_sprite = displayed_stamina >= 0 and sprites.ui.meter_cap_green or sprites.ui.meter_cap_red
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
    self.fatigue_pulse_timer = 0 -- For fatigue color pulsing
    self.energy_flash_timer = 0 -- For energy bar flash effect
    return self
end

--- Triggers energy bar flash effect for insufficient energy feedback.
function projectile_selector:flash_energy()
    self.energy_flash_timer = 0.5 -- Flash duration in seconds
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

    self.fatigue_pulse_timer = self.fatigue_pulse_timer + dt

    -- Check for energy flash request from player
    if player.energy_flash_requested then
        self:flash_energy()
        player.energy_flash_requested = false
    end

    -- Decrement energy flash timer
    if self.energy_flash_timer > 0 then
        self.energy_flash_timer = self.energy_flash_timer - dt
    end
end

---@param player table Player instance with projectile, health, stamina, and energy properties
function projectile_selector:draw(player)
    local scale = config.ui.SCALE
    canvas.save()
    canvas.set_global_alpha(self.alpha)
    canvas.translate(self.x, canvas.get_height() - WIDGET_HEIGHT * scale - self.y)
    canvas.scale(scale, scale)

    canvas.draw_image(sprites.ui.ability_selector_left, 0, 0)
    -- Only draw projectile icon if current projectile is unlocked
    if player:is_projectile_unlocked(player.projectile) then
        canvas.draw_image(player.projectile.icon, 8, 8, 16, 16)
    end

    draw_meter(self.alpha, METER_Y, player.max_health, self.displayed_hp, "#FF0000", sprites.ui.meter_cap_red)
    draw_stamina_meter(self.alpha, METER_Y + METER_HEIGHT, player, self.displayed_stamina, self.fatigue_pulse_timer)
    draw_meter(self.alpha, METER_Y + METER_HEIGHT * 2, player.max_energy, self.displayed_energy, "#0088FF", sprites.ui.meter_cap_blue)

    -- Energy flash overlay (flickering rectangle over the meter)
    if self.energy_flash_timer > 0 then
        local energy_y = METER_Y + METER_HEIGHT * 2
        local meter_width = player.max_energy * PX_PER_UNIT
        local flash_opacity = get_energy_flash_opacity(self.energy_flash_timer)
        canvas.set_global_alpha(self.alpha * flash_opacity)
        canvas.set_fill_style("#FFFFFF")
        canvas.fill_rect(METER_X, energy_y + BAR_Y_OFFSET, meter_width, BAR_HEIGHT)
        canvas.set_global_alpha(self.alpha)
    end

    canvas.restore()
end

return projectile_selector
