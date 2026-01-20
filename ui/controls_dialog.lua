--- Controls settings dialog with keybind panel
local canvas = require("canvas")
local controls = require("controls")
local button = require("ui/button")
local simple_dialogue = require("ui/simple_dialogue")
local config = require("config")
local keybind_panel = require("ui/keybind_panel")
local settings_storage = require("settings_storage")

local controls_dialog = {}

-- Dialog dimensions at 1x scale
local base_width = 180
local base_height = 140
local button_height = 12

-- Dialog box instance (created in init after base dimensions are set)
local dialog_box = nil

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

-- Controls panel
local controls_panel = nil

-- Close button
local close_button = nil

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

--- Initialize controls dialog components
---@return nil
function controls_dialog.init()
    dialog_box = simple_dialogue.create({ x = 0, y = 0, width = base_width, height = base_height })

    -- Two-column layout: 72px * 2 + 22px gap = 166px
    controls_panel = keybind_panel.create({
        x = 0,
        y = 0,
        width = 166,
        height = base_height - 40,
    })

    close_button = button.create({
        x = 0, y = 0, width = 40, height = button_height,
        label = "Close",
        text_only = true,
        on_click = function()
            controls_dialog.hide()
        end
    })
end

--- Save control bindings to storage
---@return nil
local function save_settings()
    settings_storage.save_bindings("keyboard", controls.get_all_bindings("keyboard"))
    settings_storage.save_bindings("gamepad", controls.get_all_bindings("gamepad"))
end

--- Show the controls dialog with fade-in animation
---@return nil
function controls_dialog.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        mouse_active = true
        if controls_panel then
            controls_panel:reset_focus()
        end
    end
end

--- Hide the controls dialog with fade-out animation
---@return nil
function controls_dialog.hide()
    if state == STATE.OPEN or state == STATE.FADING_IN then
        state = STATE.FADING_OUT
        fade_progress = 0
        if controls_panel then
            controls_panel:cancel_listening()
        end
    end
end

--- Check if controls dialog is visible
---@return boolean is_active True if dialog is visible or animating
function controls_dialog.is_active()
    return state ~= STATE.HIDDEN
end

--- Check if currently capturing a keybind
---@return boolean True if waiting for keybind input
function controls_dialog.is_capturing()
    return controls_panel and controls_panel:is_capturing_input()
end

--- Process controls dialog input
---@return nil
function controls_dialog.input()
    if state ~= STATE.OPEN then return end

    -- If panel is listening for input, let it handle everything
    if controls_panel:is_listening() then
        return
    end

    -- ESC or Back (EAST) closes dialog (unless capturing keybind)
    if controls.settings_pressed() or controls.menu_back_pressed() then
        controls_dialog.hide()
        return
    end

    local reset_focus = #controls_panel.rows + 1
    local close_focus = reset_focus + 1

    -- Handle focus on close button
    if controls_panel.focus_index == close_focus then
        if controls.menu_up_pressed() then
            mouse_active = false
            controls_panel.focus_index = reset_focus
            return
        elseif controls.menu_down_pressed() then
            mouse_active = false
            controls_panel.focus_index = -1  -- Scheme tab
            return
        end
        if controls.menu_confirm_pressed() then
            controls_dialog.hide()
            return
        end
        return
    end

    -- Handle scheme tab (-1) and reset button navigation to close button
    if controls_panel.focus_index == -1 then
        -- Scheme tab
        if controls.menu_left_pressed() then
            controls_panel:cycle_scheme(-1)
            return
        elseif controls.menu_right_pressed() then
            controls_panel:cycle_scheme(1)
            return
        elseif controls.menu_up_pressed() then
            mouse_active = false
            controls_panel.focus_index = close_focus  -- Wrap to close button
            return
        elseif controls.menu_down_pressed() then
            mouse_active = false
            controls_panel.focus_index = 1  -- Move to first row
            return
        end
        return
    end

    if controls_panel.focus_index == reset_focus then
        -- Reset button - down goes to close button
        if controls.menu_down_pressed() then
            mouse_active = false
            controls_panel.focus_index = close_focus
            return
        elseif controls.menu_up_pressed() then
            mouse_active = false
            -- Go to bottom of left column
            local max_left_row = controls_panel:get_max_row_in_column(1)
            controls_panel.focus_index = controls_panel:find_row_at(1, max_left_row) or controls_panel.focus_index
            return
        end
        if controls.menu_confirm_pressed() then
            controls_panel:reset_to_defaults()
            return
        end
        return
    end

    -- Let panel handle row navigation
    if controls.menu_up_pressed() or controls.menu_down_pressed() then
        mouse_active = false
    end
    controls_panel:input()
end

--- Update controls dialog animations and mouse input
---@param dt number Delta time in seconds
function controls_dialog.update(dt)
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
            save_settings()
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

        -- Update keybind panel
        local panel_x = (base_width - controls_panel.width) / 2
        local panel_y = 8
        controls_panel:update(dt, local_mx - panel_x, local_my - panel_y, mouse_active)

        -- Close button mouse handling
        local close_y = base_height - 18
        local close_x = (base_width - close_button.width) / 2
        close_button.x = close_x
        close_button.y = close_y
        close_button:update(local_mx, local_my)

        -- Don't update close button hover while listening
        if mouse_active and not controls_panel:is_listening() then
            if local_mx >= close_x and local_mx <= close_x + close_button.width
                and local_my >= close_y and local_my <= close_y + button_height then
                controls_panel.focus_index = #controls_panel.rows + 2  -- close_focus
                if canvas.is_mouse_pressed(0) then
                    controls_dialog.hide()
                end
            end
        end
    end
end

--- Render the controls dialog
---@return nil
function controls_dialog.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - base_width * scale) / 2
    local menu_y = (screen_h - base_height * scale) / 2

    -- Calculate alpha based on fade state (both fade-in and fade-out use progress directly)
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

    -- Draw controls panel
    local panel_x = (base_width - controls_panel.width) / 2
    local panel_y = 8

    canvas.save()
    canvas.translate(panel_x, panel_y)
    controls_panel:draw()
    canvas.restore()

    -- Draw close button
    local close_focus = #controls_panel.rows + 2
    close_button:draw(controls_panel.focus_index == close_focus)

    canvas.restore()
    canvas.set_global_alpha(1)
end

return controls_dialog
