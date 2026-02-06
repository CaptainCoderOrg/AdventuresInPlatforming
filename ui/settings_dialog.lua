--- Settings dialog for difficulty selection (title screen overlay)
local canvas = require("canvas")
local controls = require("controls")
local button = require("ui/button")
local simple_dialogue = require("ui/simple_dialogue")
local utils = require("ui/utils")
local config = require("config")
local settings_storage = require("settings_storage")

local settings_dialog = {}

-- Dialog dimensions at 1x scale
local base_width = 120
local base_height = 60
local button_height = 12

-- State machine
local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
}

local FADE_DURATION = 0.15

local state = STATE.HIDDEN
local fade_progress = 0

-- Current difficulty selection
local difficulty = "normal"

-- Focus tracking (1 = difficulty toggle, 2 = close button)
local focus_index = 1

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- UI components
local dialog_box = nil
local close_button = nil

-- Layout constants
local TOGGLE_Y = 22
local TOGGLE_HEIGHT = 14

--- Initialize settings dialog components
---@return nil
function settings_dialog.init()
    dialog_box = simple_dialogue.create({ x = 0, y = 0, width = base_width, height = base_height })

    close_button = button.create({
        x = 0, y = 0, width = 40, height = button_height,
        label = "Close",
        text_only = true,
        on_click = function()
            settings_dialog.hide()
        end
    })

    difficulty = settings_storage.load_difficulty()
end

--- Toggle difficulty between "easy" and "normal"
---@return nil
local function toggle_difficulty()
    if difficulty == "normal" then
        difficulty = "easy"
    else
        difficulty = "normal"
    end
    settings_storage.save_difficulty(difficulty)
end

--- Show the settings dialog with fade-in animation
---@return nil
function settings_dialog.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        focus_index = 1
        mouse_active = true
    end
end

--- Hide the settings dialog with fade-out animation
---@return nil
function settings_dialog.hide()
    if state == STATE.OPEN or state == STATE.FADING_IN then
        state = STATE.FADING_OUT
        fade_progress = 0
    end
end

--- Check if settings dialog is visible
---@return boolean is_active True if dialog is visible or animating
function settings_dialog.is_active()
    return state ~= STATE.HIDDEN
end

--- Get the current difficulty setting
---@return string difficulty "easy" or "normal"
function settings_dialog.get_difficulty()
    return difficulty
end

--- Set the difficulty (used when loading a save)
---@param d string "easy" or "normal"
function settings_dialog.set_difficulty(d)
    if d == "easy" or d == "normal" then
        difficulty = d
    end
end

--- Process settings dialog input
---@return nil
function settings_dialog.input()
    if state ~= STATE.OPEN then return end

    -- ESC or Back closes dialog
    if controls.settings_pressed() or controls.menu_back_pressed() then
        settings_dialog.hide()
        return
    end

    -- Up/Down navigation
    if controls.menu_up_pressed() then
        mouse_active = false
        focus_index = focus_index - 1
        if focus_index < 1 then focus_index = 2 end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focus_index = focus_index + 1
        if focus_index > 2 then focus_index = 1 end
    end

    -- Left/Right or Confirm to toggle difficulty
    if focus_index == 1 then
        if controls.menu_left_pressed() or controls.menu_right_pressed() then
            toggle_difficulty()
        end
    end

    -- Confirm
    if controls.menu_confirm_pressed() then
        if focus_index == 1 then
            toggle_difficulty()
        elseif focus_index == 2 then
            settings_dialog.hide()
        end
    end
end

--- Update settings dialog animations and mouse input
---@param dt number Delta time in seconds
function settings_dialog.update(dt)
    if state == STATE.HIDDEN then return end

    local speed = dt / FADE_DURATION

    if state == STATE.FADING_IN then
        fade_progress = math.min(1, fade_progress + speed)
        if fade_progress >= 1 then
            state = STATE.OPEN
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = math.max(0, fade_progress - speed)
        if fade_progress <= 0 then
            state = STATE.HIDDEN
        end
    end

    if state == STATE.OPEN then
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local screen_h = canvas.get_height()

        local menu_x = (screen_w - base_width * scale) / 2
        local menu_y = (screen_h - base_height * scale) / 2

        local local_mx = (canvas.get_mouse_x() - menu_x) / scale
        local local_my = (canvas.get_mouse_y() - menu_y) / scale

        -- Re-enable mouse input if mouse has moved
        local raw_mx = canvas.get_mouse_x()
        local raw_my = canvas.get_mouse_y()
        if raw_mx ~= last_mouse_x or raw_my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x = raw_mx
            last_mouse_y = raw_my
        end

        -- Mouse hover handling
        if mouse_active then
            -- Difficulty toggle area
            if local_my >= TOGGLE_Y and local_my <= TOGGLE_Y + TOGGLE_HEIGHT then
                focus_index = 1
                if canvas.is_mouse_pressed(0) then
                    toggle_difficulty()
                end
            end

            -- Close button hover
            local close_y = TOGGLE_Y + TOGGLE_HEIGHT + 8
            local close_x = (base_width - close_button.width) / 2
            if local_mx >= close_x and local_mx <= close_x + close_button.width
                and local_my >= close_y and local_my <= close_y + button_height then
                focus_index = 2
                if canvas.is_mouse_pressed(0) then
                    settings_dialog.hide()
                end
            end
        end

        close_button:update(local_mx, local_my)
    end
end

--- Render the settings dialog
---@return nil
function settings_dialog.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - base_width * scale) / 2
    local menu_y = (screen_h - base_height * scale) / 2

    -- Calculate alpha based on fade state
    local alpha = (state == STATE.FADING_IN or state == STATE.FADING_OUT) and fade_progress or 1

    -- Draw background overlay
    canvas.set_global_alpha(alpha)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Apply canvas transform for pixel-perfect scaling
    canvas.save()
    canvas.translate(menu_x, menu_y)
    canvas.scale(scale, scale)

    simple_dialogue.draw(dialog_box)

    local center_x = base_width / 2

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")

    -- Draw "Difficulty" label
    local label = "Difficulty"
    local label_metrics = canvas.get_text_metrics(label)
    utils.draw_outlined_text(label, center_x - label_metrics.width / 2, TOGGLE_Y)

    -- Draw toggle value with arrows
    local toggle_y = TOGGLE_Y + 12
    local value_text = difficulty == "easy" and "Easy" or "Normal"
    local is_focused = focus_index == 1
    local value_color = is_focused and "#FFFF00" or "#FFFFFF"
    local arrow_color = is_focused and "#FFFF00" or "#888888"

    local value_metrics = canvas.get_text_metrics(value_text)
    local arrow_left = "< "
    local arrow_right = " >"
    local left_metrics = canvas.get_text_metrics(arrow_left)
    local right_metrics = canvas.get_text_metrics(arrow_right)
    local total_width = left_metrics.width + value_metrics.width + right_metrics.width
    local start_x = center_x - total_width / 2

    -- Left arrow
    canvas.set_color(arrow_color)
    canvas.draw_text(start_x, toggle_y, arrow_left)

    -- Value text
    utils.draw_outlined_text(value_text, start_x + left_metrics.width, toggle_y, value_color)

    -- Right arrow
    canvas.set_color(arrow_color)
    canvas.draw_text(start_x + left_metrics.width + value_metrics.width, toggle_y, arrow_right)

    -- Close button
    close_button.x = (base_width - close_button.width) / 2
    close_button.y = TOGGLE_Y + TOGGLE_HEIGHT + 8
    close_button:draw(focus_index == 2)

    canvas.restore()
    canvas.set_global_alpha(1)
end

return settings_dialog
