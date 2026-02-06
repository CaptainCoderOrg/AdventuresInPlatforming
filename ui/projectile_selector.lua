--- Player resource display widget showing health, stamina, energy meters and equipped weapon
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local weapon_sync = require("player.weapon_sync")
local control_icon = require("ui.control_icon")

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
local TOP_MARGIN = 1          -- Margin from top of HUD bar (1x scale)
local METER_X = 36            -- Meter X offset from widget origin (right edge of selector + 4px)
local METER_Y = 1             -- Meter Y offset from widget origin
local PX_PER_UNIT = 5         -- Pixels per health/stamina point
local METER_HEIGHT = 10       -- Total meter sprite height in pixels
local BAR_HEIGHT = 6          -- Bar height in pixels
local BAR_Y_OFFSET = 2        -- Vertical offset for bar within meter
local SHINE_OPACITY = 0.7     -- Shine overlay relative opacity

-- Control icon layout (for attack indicator on weapon slot)
local CONTROL_ICON_SIZE = 8   -- Size of control icon in 1x scale
local WEAPON_ICON_X = 8       -- Weapon icon X position
local WEAPON_ICON_Y = 8       -- Weapon icon Y position
local WEAPON_ICON_SIZE = 16   -- Weapon icon size
local ATTACK_ICON_OFFSET_X = 18  -- X offset from weapon container left edge
local ATTACK_ICON_OFFSET_Y = 20  -- Y offset from weapon container top edge

-- Swap icon layout (shown when multiple weapons equipped)
local SWAP_ICON_SIZE = 10     -- Size of swap control icon
local SWAP_ICON_PADDING = 1   -- Padding from bottom-left corner

-- Pre-computed fatigue colors (green channel 0-136 for orange-to-red pulse)
local FATIGUE_COLORS = {}
for green = 0, 136 do
    FATIGUE_COLORS[green] = string.format("#FF%02X00", green)
end

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
--- Shows animating portion at reduced opacity so player can see final value immediately.
---@param alpha number Widget alpha for shine calculation
---@param y number Y position of the meter
---@param max_value number Maximum meter value (determines width)
---@param target_value number Actual current value (shown at full opacity)
---@param displayed_value number Animated displayed value (difference shown at reduced opacity)
---@param fill_color string Fill bar color (e.g., "#FF0000")
---@param cap_sprite string Sprite key for the end cap
local function draw_meter(alpha, y, max_value, target_value, displayed_value, fill_color, cap_sprite)
    local meter_width = max_value * PX_PER_UNIT
    local target_width = math.max(0, target_value) * PX_PER_UNIT
    local displayed_width = math.max(0, displayed_value) * PX_PER_UNIT
    local animating_alpha = 0.3

    canvas.draw_image(sprites.ui.meter_background, METER_X, y, meter_width, METER_HEIGHT)

    -- Draw the final/target bar at full opacity
    canvas.set_fill_style(fill_color)
    canvas.fill_rect(METER_X, y + BAR_Y_OFFSET, target_width, BAR_HEIGHT)

    -- Draw the animating portion at reduced opacity
    if displayed_width > target_width then
        -- Draining: show the portion that's still animating away
        canvas.set_global_alpha(alpha * animating_alpha)
        canvas.fill_rect(METER_X + target_width, y + BAR_Y_OFFSET, displayed_width - target_width, BAR_HEIGHT)
        canvas.set_global_alpha(alpha)
    elseif displayed_width < target_width then
        -- Regenerating: show the portion that's filling in
        canvas.set_global_alpha(alpha * animating_alpha)
        canvas.fill_rect(METER_X + displayed_width, y + BAR_Y_OFFSET, target_width - displayed_width, BAR_HEIGHT)
        canvas.set_global_alpha(alpha)
    end

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
    return FATIGUE_COLORS[green]
end

--- Returns a flickering opacity for energy flash overlay.
---@param timer number Flash timer in seconds
---@return number Opacity value (0-1)
local function get_energy_flash_opacity(timer)
    -- 8Hz flicker for rapid on/off effect
    local t = (math.sin(timer * math.pi * 16) + 1) / 2
    return t * 0.5  -- Max 50% opacity
end

--- Draws a portion of a stamina bar (either green stamina or fatigue).
---@param alpha number Widget alpha
---@param y number Y position of the meter
---@param x_offset number X offset from METER_X
---@param width number Width of the bar segment
---@param color string Fill color
---@param is_animating boolean Whether to draw at reduced opacity
local function draw_stamina_segment(alpha, y, x_offset, width, color, is_animating)
    if width <= 0 then return end
    if is_animating then
        canvas.set_global_alpha(alpha * 0.3)
    end
    canvas.set_fill_style(color)
    canvas.fill_rect(METER_X + x_offset, y + BAR_Y_OFFSET, width, BAR_HEIGHT)
    if is_animating then
        canvas.set_global_alpha(alpha)
    end
end

--- Draws the stamina meter. Uses pulsing orange/red while fatigued, green otherwise.
--- Shows animating portion at reduced opacity so player can see final value immediately.
---@param alpha number Widget alpha for shine calculation
---@param y number Y position of the meter
---@param player table Player instance with stamina properties
---@param displayed_stamina number Current displayed stamina value
---@param fatigue_timer number Timer for fatigue color pulsing
local function draw_stamina_meter(alpha, y, player, displayed_stamina, fatigue_timer)
    local meter_width = player.max_stamina * PX_PER_UNIT
    local is_fatigued = player.fatigue_remaining > 0
    local bar_color = is_fatigued and get_fatigue_color(fatigue_timer) or "#00FF00"

    canvas.draw_image(sprites.ui.meter_background, METER_X, y, meter_width, METER_HEIGHT)

    local target_w = math.max(0, player.max_stamina - player.stamina_used) * PX_PER_UNIT
    local displayed_w = math.max(0, displayed_stamina) * PX_PER_UNIT
    draw_stamina_segment(alpha, y, 0, target_w, bar_color, false)
    if displayed_w > target_w then
        draw_stamina_segment(alpha, y, target_w, displayed_w - target_w, bar_color, true)
    elseif displayed_w < target_w then
        draw_stamina_segment(alpha, y, displayed_w, target_w - displayed_w, bar_color, true)
    end

    canvas.set_global_alpha(alpha * SHINE_OPACITY)
    canvas.draw_image(sprites.ui.meter_shine, METER_X + 1, y, meter_width - 2, METER_HEIGHT)
    canvas.set_global_alpha(alpha)

    local cap_sprite = is_fatigued and sprites.ui.meter_cap_red or sprites.ui.meter_cap_green
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
    self.displayed_hp = nil
    self.displayed_stamina = nil
    self.displayed_energy = nil
    self.fatigue_pulse_timer = 0
    self.energy_flash_timer = 0
    return self
end

--- Triggers energy bar flash effect for insufficient energy feedback.
---@return nil
function projectile_selector:flash_energy()
    self.energy_flash_timer = 0.5 -- Flash duration in seconds
end

---@param dt number Delta time in seconds
---@param player table Player instance with health, stamina, and energy properties
---@return nil
function projectile_selector:update(dt, player)
    self.target_hp = player.max_health - player.damage
    self.target_stamina = player.max_stamina - player.stamina_used
    self.target_energy = player.max_energy - player.energy_used

    self.displayed_hp = lerp_toward(self.displayed_hp, self.target_hp, LERP_SPEED, dt)
    self.displayed_stamina = lerp_toward(self.displayed_stamina, self.target_stamina, LERP_SPEED, dt)
    self.displayed_energy = lerp_toward(self.displayed_energy, self.target_energy, LERP_SPEED, dt)

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
---@return nil
function projectile_selector:draw(player)
    local scale = config.ui.SCALE
    local hud_height = config.ui.HUD_HEIGHT_PX * scale
    canvas.save()
    canvas.set_global_alpha(self.alpha)
    canvas.translate(self.x, canvas.get_height() - hud_height + (TOP_MARGIN * scale))
    canvas.scale(scale, scale)

    canvas.draw_image(sprites.ui.ability_selector_left, 0, 0)
    -- Draw equipped weapon icon
    local _, weapon_def = weapon_sync.get_equipped_weapon(player)
    if weapon_def then
        if weapon_def.animated_sprite then
            -- For animated sprites, draw only the first frame (16x16)
            canvas.draw_image(weapon_def.animated_sprite, WEAPON_ICON_X, WEAPON_ICON_Y, WEAPON_ICON_SIZE, WEAPON_ICON_SIZE, 0, 0, 16, 16)
        elseif weapon_def.static_sprite then
            canvas.draw_image(weapon_def.static_sprite, WEAPON_ICON_X, WEAPON_ICON_Y, WEAPON_ICON_SIZE, WEAPON_ICON_SIZE)
        end

        -- Draw attack control icon in bottom-right of weapon
        control_icon.draw("attack", ATTACK_ICON_OFFSET_X, ATTACK_ICON_OFFSET_Y, CONTROL_ICON_SIZE)
    end

    draw_meter(self.alpha, METER_Y, player.max_health, self.target_hp, self.displayed_hp, "#FF0000", sprites.ui.meter_cap_red)
    draw_stamina_meter(self.alpha, METER_Y + METER_HEIGHT, player, self.displayed_stamina, self.fatigue_pulse_timer)
    draw_meter(self.alpha, METER_Y + METER_HEIGHT * 2, player.max_energy, self.target_energy, self.displayed_energy, "#0088FF", sprites.ui.meter_cap_blue)

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

    -- Draw swap icon in bottom-left of screen if more than 1 weapon equipped
    local all_weapons = weapon_sync.get_all_equipped_weapons(player)
    if #all_weapons > 1 then
        -- Calculate position relative to current transform to place at screen bottom-left
        -- We're translated by self.x and scaled, so adjust accordingly
        local swap_x = (SWAP_ICON_PADDING * scale - self.x) / scale
        local swap_y = config.ui.HUD_HEIGHT_PX - TOP_MARGIN - SWAP_ICON_SIZE - SWAP_ICON_PADDING
        control_icon.draw("swap_weapon", swap_x, swap_y, SWAP_ICON_SIZE)
    end

    canvas.restore()
end

return projectile_selector
