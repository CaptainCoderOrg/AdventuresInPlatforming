--- Game over screen with fade transitions and restart/continue menu
local canvas = require("canvas")
local controls = require("controls")
local button = require("ui/button")
local utils = require("ui/utils")
local config = require("config")

local game_over = {}

local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_TO_BLACK = "fading_to_black",
    RELOADING = "reloading",
    FADING_BACK_IN = "fading_back_in",
}

-- Fade timing (seconds)
local FADE_IN_DURATION = 0.5
local FADE_TO_BLACK_DURATION = 0.3
local RELOAD_PAUSE = 0.1
local FADE_BACK_IN_DURATION = 0.4

-- Current transition state for the game over overlay
local state = STATE.HIDDEN
local fade_progress = 0
local focus_index = 1  -- 1 = Continue, 2 = Restart
local BUTTON_COUNT = 2

-- Buttons (stored in array for iteration)
local buttons = {}

-- Callback for restarting the level
local restart_callback = nil

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Layout constants (at 1x scale)
local TITLE_Y = 80
local BUTTON_START_Y = 110
local BUTTON_SPACING = 18
local BUTTON_WIDTH = 60
local BUTTON_HEIGHT = 12

--- Create a menu button with standard settings
---@param label string Button label text
---@return table button
local function create_menu_button(label)
    return button.create({
        x = 0, y = 0,
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        label = label,
        text_only = true,
        on_click = function()
            if state == STATE.OPEN then
                game_over.trigger_restart()
            end
        end
    })
end

--- Initialize game over screen components
--- Must be called once before using the game over system
function game_over.init()
    buttons = {
        create_menu_button("Continue"),
        create_menu_button("Restart"),
    }
end

--- Trigger the fade to black and restart sequence
function game_over.trigger_restart()
    state = STATE.FADING_TO_BLACK
    fade_progress = 0
end

--- Show the game over screen (called when player dies)
function game_over.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        focus_index = 1
        mouse_active = true
    end
end

--- Set the restart callback function
---@param fn function Function to call when restarting the level
function game_over.set_restart_callback(fn)
    restart_callback = fn
end

--- Check if game over screen is blocking game input
---@return boolean is_active True if game over is visible or animating
function game_over.is_active()
    return state ~= STATE.HIDDEN
end

--- Process game over menu input
function game_over.input()
    if state ~= STATE.OPEN then return end

    if controls.menu_up_pressed() then
        mouse_active = false
        focus_index = focus_index - 1
        if focus_index < 1 then
            focus_index = BUTTON_COUNT
        end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focus_index = focus_index + 1
        if focus_index > BUTTON_COUNT then
            focus_index = 1
        end
    end

    if controls.menu_confirm_pressed() then
        game_over.trigger_restart()
    end
end

--- Advance fade animations and handle state transitions
---@param dt number Delta time in seconds
function game_over.update(dt)
    if state == STATE.HIDDEN then return end

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
    elseif state == STATE.FADING_TO_BLACK then
        fade_progress = fade_progress + dt / FADE_TO_BLACK_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.RELOADING
        end
    elseif state == STATE.RELOADING then
        fade_progress = fade_progress + dt / RELOAD_PAUSE
        if fade_progress >= 1 then
            if restart_callback then
                restart_callback()
            end
            state = STATE.FADING_BACK_IN
            fade_progress = 0
        end
    elseif state == STATE.FADING_BACK_IN then
        fade_progress = fade_progress + dt / FADE_BACK_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
        end
    end

    -- Update button hover states when menu is open
    if state == STATE.OPEN then
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local center_x = screen_w / (2 * scale)

        -- Re-enable mouse input if mouse has moved
        local mx = canvas.get_mouse_x()
        local my = canvas.get_mouse_y()
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x = mx
            last_mouse_y = my
        end

        -- Update button positions and handle mouse hover
        local local_mx = mx / scale
        local local_my = my / scale
        for i, btn in ipairs(buttons) do
            btn.x = center_x - BUTTON_WIDTH / 2
            btn.y = BUTTON_START_Y + (i - 1) * BUTTON_SPACING

            if mouse_active then
                if utils.point_in_rect(local_mx, local_my, btn.x, btn.y, btn.width, btn.height) then
                    focus_index = i
                end
                btn:update(local_mx, local_my)
            end
        end
    end
end

--- Draw game over screen overlay
function game_over.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Calculate overlay alpha based on state
    local overlay_alpha = 0
    local content_alpha = 0

    if state == STATE.FADING_IN then
        overlay_alpha = fade_progress * 0.6
        content_alpha = fade_progress
    elseif state == STATE.OPEN then
        overlay_alpha = 0.6
        content_alpha = 1
    elseif state == STATE.FADING_TO_BLACK then
        -- Fade from semi-transparent to full black
        overlay_alpha = 0.6 + fade_progress * 0.4
        content_alpha = 1 - fade_progress
    elseif state == STATE.RELOADING then
        overlay_alpha = 1
        content_alpha = 0
    elseif state == STATE.FADING_BACK_IN then
        overlay_alpha = 1 - fade_progress
        content_alpha = 0
    end

    canvas.set_global_alpha(overlay_alpha)
    canvas.set_color("#000000")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Draw content only during fading_in and open states
    if content_alpha > 0 then
        canvas.set_global_alpha(content_alpha)

        canvas.save()
        canvas.scale(scale, scale)

        local center_x = screen_w / (2 * scale)

        -- Draw "GAME OVER" title
        canvas.set_font_family("menu_font")
        canvas.set_font_size(52 / scale)  -- Scale down font since we're scaling canvas
        canvas.set_text_baseline("middle")
        canvas.set_text_align("center")

        -- Shadow
        canvas.set_color("#472727ff")
        canvas.draw_text(center_x + 2/scale, TITLE_Y + 2/scale, "GAME OVER", {})

        -- Main text
        canvas.set_color("#ebe389ff")
        canvas.draw_text(center_x, TITLE_Y, "GAME OVER", {})

        canvas.set_text_align("left")

        for i, btn in ipairs(buttons) do
            btn.x = center_x - BUTTON_WIDTH / 2
            btn.y = BUTTON_START_Y + (i - 1) * BUTTON_SPACING
            btn:draw(focus_index == i)
        end

        canvas.restore()
    end

    canvas.set_global_alpha(1)
end

return game_over
