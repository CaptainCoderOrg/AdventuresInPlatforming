--- Placeholder credits screen overlay
--- Shows "Credits" and "To Be Continued..." text, then returns to title screen
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")

local credits_screen = {}

-- State machine
local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
}

-- Timing configuration (seconds)
local FADE_IN_DURATION = 2
local FADE_OUT_DURATION = 1

local state = STATE.HIDDEN
local fade_progress = 0

-- Callback to invoke when credits finish (return to title)
local on_close_callback = nil

--- Show the credits screen with fade-in
function credits_screen.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
    end
end

--- Hide the credits screen with fade-out
function credits_screen.hide()
    if state == STATE.OPEN or state == STATE.FADING_IN then
        state = STATE.FADING_OUT
        fade_progress = 0
    end
end

--- Check if credits screen is blocking game input
---@return boolean True if credits screen is visible or animating
function credits_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Set callback for when credits screen closes
---@param fn function Callback function
function credits_screen.set_on_close(fn)
    on_close_callback = fn
end

--- Process credits screen input
function credits_screen.input()
    if state ~= STATE.OPEN then return end

    -- Any key/button press closes credits
    if controls.menu_confirm_pressed() or controls.settings_pressed()
        or controls.menu_back_pressed() then
        credits_screen.hide()
    end
end

--- Update fade animations
---@param dt number Delta time in seconds
function credits_screen.update(dt)
    if state == STATE.HIDDEN then return end

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
            if on_close_callback then
                on_close_callback()
            end
        end
    end
end

--- Draw the credits screen
function credits_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local alpha = 1
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    canvas.set_global_alpha(alpha)

    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    canvas.save()
    canvas.scale(scale, scale)

    local center_x = screen_w / (2 * scale)

    canvas.set_font_family("menu_font")
    canvas.set_text_baseline("middle")

    -- "Credits" title
    canvas.set_font_size(16)
    local title = "Credits"
    local title_metrics = canvas.get_text_metrics(title)
    local title_x = center_x - title_metrics.width / 2

    canvas.set_color("#FFFF00")
    canvas.draw_text(title_x, 80, title)

    -- "To Be Continued..." subtitle
    canvas.set_font_size(7)
    local subtitle = "To Be Continued..."
    local sub_metrics = canvas.get_text_metrics(subtitle)
    local sub_x = center_x - sub_metrics.width / 2

    canvas.set_color("#FFFFFF")
    canvas.draw_text(sub_x, 120, subtitle)

    canvas.restore()
    canvas.set_global_alpha(1)
end

return credits_screen
