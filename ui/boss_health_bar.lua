--- Boss Health Bar: Sprite-based health display for boss encounters.
--- Shows at top-center of screen with intro animation when a boss fight starts.
--- Configure with set_coordinator() to support different boss types.
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")

local boss_health_bar = {}

-- Active coordinator (set via set_coordinator)
local coordinator = nil

-- Sprite dimensions (unscaled pixels)
local SPRITE_WIDTH = 160
local SPRITE_HEIGHT = 16
local TOP_MARGIN = 1

-- Health bar rectangle (relative to sprite top-left)
local BAR_X_OFFSET = 6
local BAR_Y_OFFSET = 7
local BAR_WIDTH = 148
local BAR_HEIGHT = 3

-- Animation constants
local FADE_SPEED = 3           -- Bar fade in/out speed (alpha per second)
local HEALTH_MOVE_SPEED = 8    -- Match player bar speed (units per second)
local FILL_UP_SPEED = 1.5      -- Health fills up over ~0.7s (percentage per second)
local TEXT_DISPLAY_TIME = 2.5  -- How long title shows (seconds)
local TEXT_FADE_SPEED = 2      -- Title fade out speed (alpha per second)

-- Widget state
local alpha = 0                -- Bar fade (0-1)
local text_alpha = 0           -- Title/subtitle fade (0-1)
local displayed_health = 0     -- Smoothed health percentage (starts at 0 for fill-up)
local target_health = 0        -- Actual health percentage
local text_timer = 0           -- Countdown for text display
local intro_complete = false   -- Whether fill-up animation finished
local was_active = false       -- Track active state for intro triggers

-- Colors
local BAR_COLOR = "#FF0000"

--- Moves a value toward a target at a given speed, clamping to not overshoot.
---@param current number Current value
---@param target number Target value
---@param speed number Movement speed per second
---@param dt number Delta time in seconds
---@return number Updated value
local function move_toward(current, target, speed, dt)
    local delta = speed * dt
    if current < target then
        return math.min(current + delta, target)
    end
    if current > target then
        return math.max(current - delta, target)
    end
    return current
end

--- Set the active boss coordinator.
--- Call this when entering a level with a boss, or when a boss encounter starts.
---@param new_coordinator table Coordinator with is_active, get_health_percent, get_boss_name, get_boss_subtitle
function boss_health_bar.set_coordinator(new_coordinator)
    coordinator = new_coordinator
end

--- Get the current coordinator (for cleanup checks).
---@return table|nil Current coordinator or nil
function boss_health_bar.get_coordinator()
    return coordinator
end

--- Update the boss health bar state.
---@param dt number Delta time in seconds
function boss_health_bar.update(dt)
    if not coordinator then
        -- No coordinator set, fade out if visible
        if alpha > 0 then
            alpha = math.max(0, alpha - FADE_SPEED * dt)
        end
        return
    end

    local is_active = coordinator.is_active()

    -- Fade bar in/out
    if is_active then
        alpha = math.min(1, alpha + FADE_SPEED * dt)
    else
        alpha = math.max(0, alpha - FADE_SPEED * dt)
    end

    -- Reset to intro state when encounter starts
    if is_active and not was_active then
        displayed_health = 0
        intro_complete = false
        text_timer = TEXT_DISPLAY_TIME
        text_alpha = 1
    end
    was_active = is_active

    if not is_active then return end

    -- Get actual health percentage
    target_health = coordinator.get_health_percent()

    -- Intro phase: fill health bar from 0 to full
    if not intro_complete then
        displayed_health = displayed_health + FILL_UP_SPEED * dt
        if displayed_health >= 1 then
            displayed_health = 1
            intro_complete = true
        end
    else
        -- Normal phase: smoothly move displayed health toward actual
        displayed_health = move_toward(displayed_health, target_health, HEALTH_MOVE_SPEED, dt)
    end

    -- Text fade timer
    if text_timer > 0 then
        text_timer = text_timer - dt
    elseif text_alpha > 0 then
        text_alpha = math.max(0, text_alpha - TEXT_FADE_SPEED * dt)
    end
end

--- Draw the boss health bar.
function boss_health_bar.draw()
    if alpha <= 0 or not coordinator then return end

    local scale = config.ui.SCALE
    local screen_width = config.ui.canvas_width

    -- Calculate scaled dimensions
    local sprite_w = SPRITE_WIDTH * scale
    local sprite_h = SPRITE_HEIGHT * scale
    local top_margin = TOP_MARGIN * scale

    -- Center horizontally
    local sprite_x = math.floor((screen_width - sprite_w) / 2)
    local sprite_y = top_margin

    canvas.save()
    canvas.set_global_alpha(alpha)

    -- Calculate health bar position (relative to sprite)
    local bar_x = sprite_x + BAR_X_OFFSET * scale
    local bar_y = sprite_y + BAR_Y_OFFSET * scale
    local bar_w = BAR_WIDTH * scale
    local bar_h = BAR_HEIGHT * scale

    -- Calculate fill widths
    local target_fill = target_health
    if not intro_complete then
        target_fill = displayed_health  -- During intro, target = displayed
    end
    local target_width = bar_w * target_fill
    local displayed_width = bar_w * displayed_health

    -- Draw target health at full opacity (under sprite)
    if target_width > 0 then
        canvas.set_color(BAR_COLOR)
        canvas.fill_rect(bar_x, bar_y, target_width, bar_h)
    end

    -- Draw drain portion at reduced opacity (when displayed > target)
    if displayed_width > target_width then
        canvas.set_global_alpha(alpha * 0.3)
        canvas.set_color(BAR_COLOR)
        canvas.fill_rect(bar_x + target_width, bar_y, displayed_width - target_width, bar_h)
        canvas.set_global_alpha(alpha)
    end

    -- Draw sprite frame on top of health bar
    canvas.draw_image(sprites.ui.boss_health_bar, sprite_x, sprite_y, sprite_w, sprite_h)

    -- Draw title/subtitle text centered on screen
    if text_alpha > 0 then
        canvas.set_global_alpha(alpha * text_alpha)

        local boss_name = coordinator.get_boss_name()
        local boss_subtitle = coordinator.get_boss_subtitle()
        local screen_height = config.ui.canvas_height
        local center_x = screen_width / 2
        local center_y = screen_height / 2

        canvas.set_font_family("menu_font")
        canvas.set_text_align("center")

        -- Title: orange/gold with black outline
        local title_y = center_y - 10 * scale
        canvas.set_font_size(16 * scale)
        canvas.set_line_width(4 * scale)
        canvas.set_color("#000000")
        canvas.stroke_text(center_x, title_y, boss_name)
        canvas.set_color("#FFB833")
        canvas.draw_text(center_x, title_y, boss_name)

        -- Subtitle: white with black outline
        local subtitle_y = center_y + 14 * scale
        canvas.set_font_size(10 * scale)
        canvas.set_line_width(3 * scale)
        canvas.set_color("#000000")
        canvas.stroke_text(center_x, subtitle_y, boss_subtitle)
        canvas.set_color("#FFFFFF")
        canvas.draw_text(center_x, subtitle_y, boss_subtitle)

        canvas.set_global_alpha(alpha)
    end

    canvas.restore()
end

--- Reset the boss health bar state (call on level cleanup).
function boss_health_bar.reset()
    alpha = 0
    text_alpha = 0
    displayed_health = 0
    target_health = 0
    text_timer = 0
    intro_complete = false
    was_active = false
end

return boss_health_bar
