--- Save slot selection screen with fade transitions and delete functionality
local canvas = require("canvas")
local controls = require("controls")
local config = require("config")
local SaveSlots = require("SaveSlots")

local slot_screen = {}

local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
}

-- Interaction modes
local MODE = {
    SELECTING = "selecting",           -- Normal slot selection
    CONFIRMING_DELETE = "confirming_delete"  -- Confirmation prompt
}

-- Fade timing (seconds)
local FADE_DURATION = 0.25

-- Current state
local state = STATE.HIDDEN
local fade_progress = 0
local focus_row = 1    -- 1-3 for slots, 4 for Back button
local focus_col = 1    -- 1 = slot, 2 = delete button
local SLOT_COUNT = 3
local ROW_COUNT = 4    -- 3 slots + Back button

-- Delete confirmation state
local mode = MODE.SELECTING
local delete_target_slot = nil
local confirm_focus = 1  -- 1 = Cancel, 2 = Delete

-- Callbacks
local slot_callback = nil
local back_callback = nil

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Layout constants (at 1x scale)
local TITLE_Y = 30
local SLOT_START_Y = 55
local SLOT_SPACING = 38
local SLOT_WIDTH = 140
local SLOT_HEIGHT = 32
local BACK_BUTTON_Y = 175
local DELETE_BUTTON_SIZE = 9
local DELETE_BUTTON_MARGIN = 4

--- Initialize slot screen
function slot_screen.init()
    SaveSlots.init()
end

--- Show the slot screen with fade-in animation
function slot_screen.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        focus_row = 1
        focus_col = 1
        mode = MODE.SELECTING
        delete_target_slot = nil
        confirm_focus = 1
        mouse_active = true
    end
end

--- Hide the slot screen with fade-out animation
local function hide()
    if state == STATE.OPEN then
        state = STATE.FADING_OUT
        fade_progress = 0
    end
end

--- Check if slot screen is blocking game input
---@return boolean is_active True if screen is visible or animating
function slot_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Set callback for when a slot is selected
---@param fn function Function to call with slot_index when selected
function slot_screen.set_slot_callback(fn)
    slot_callback = fn
end

--- Set callback for when Back is selected
---@param fn function Function to call when going back to title
function slot_screen.set_back_callback(fn)
    back_callback = fn
end

--- Check if a slot has data (delete button should be shown)
---@param slot_index number Slot number (1-3)
---@return boolean has_data True if slot has save data
local function slot_has_data(slot_index)
    return SaveSlots.get(slot_index) ~= nil
end

--- Trigger the selected action based on current focus
local function trigger_selection()
    if focus_row >= 1 and focus_row <= SLOT_COUNT then
        if focus_col == 1 then
            -- Slot selected
            hide()
            if slot_callback then
                slot_callback(focus_row)
            end
        elseif focus_col == 2 and slot_has_data(focus_row) then
            -- Delete button selected - show confirmation
            delete_target_slot = focus_row
            confirm_focus = 1  -- Default to Cancel
            mode = MODE.CONFIRMING_DELETE
        end
    elseif focus_row == 4 then
        -- Back button selected
        hide()
        if back_callback then
            back_callback()
        end
    end
end

--- Execute delete confirmation action
local function execute_delete_confirmation()
    if confirm_focus == 1 then
        -- Cancel - return to selecting
        mode = MODE.SELECTING
        delete_target_slot = nil
    elseif confirm_focus == 2 then
        -- Delete - clear the slot
        SaveSlots.clear(delete_target_slot)
        mode = MODE.SELECTING
        focus_col = 1  -- Return to slot column
        delete_target_slot = nil
    end
end

--- Process slot screen input (navigation and selection)
function slot_screen.input()
    if state ~= STATE.OPEN then return end

    if mode == MODE.SELECTING then
        -- Navigation - Up/Down for rows
        if controls.menu_up_pressed() then
            mouse_active = false
            focus_row = focus_row - 1
            if focus_row < 1 then
                focus_row = ROW_COUNT
            end
            -- Reset to slot column if moving to Back button or slot without data
            if focus_row == 4 then
                focus_col = 1
            elseif focus_col == 2 and not slot_has_data(focus_row) then
                focus_col = 1
            end
        elseif controls.menu_down_pressed() then
            mouse_active = false
            focus_row = focus_row + 1
            if focus_row > ROW_COUNT then
                focus_row = 1
            end
            -- Reset to slot column if moving to Back button or slot without data
            if focus_row == 4 then
                focus_col = 1
            elseif focus_col == 2 and not slot_has_data(focus_row) then
                focus_col = 1
            end
        end

        -- Navigation - Left/Right for columns (only on slot rows with data)
        if focus_row >= 1 and focus_row <= SLOT_COUNT then
            if controls.menu_right_pressed() then
                mouse_active = false
                if focus_col == 1 and slot_has_data(focus_row) then
                    focus_col = 2
                end
            elseif controls.menu_left_pressed() then
                mouse_active = false
                if focus_col == 2 then
                    focus_col = 1
                end
            end
        end

        -- Confirm selection
        if controls.menu_confirm_pressed() then
            trigger_selection()
        end

        -- Back (menu_back or cancel)
        if controls.menu_back_pressed() then
            hide()
            if back_callback then
                back_callback()
            end
        end

    elseif mode == MODE.CONFIRMING_DELETE then
        -- Left/Right to toggle Cancel/Delete
        if controls.menu_left_pressed() or controls.menu_right_pressed() then
            mouse_active = false
            -- Toggle between 1 (Cancel) and 2 (Delete): 3-1=2, 3-2=1
            confirm_focus = 3 - confirm_focus
        end

        -- Confirm action
        if controls.menu_confirm_pressed() then
            execute_delete_confirmation()
        end

        -- Back/Escape cancels
        if controls.menu_back_pressed() then
            mode = MODE.SELECTING
            delete_target_slot = nil
        end
    end
end

--- Get delete button bounds for a slot
---@param slot_index number Slot number (1-3)
---@param center_x number Screen center X (1x scale)
---@return number x, number y, number w, number h Button bounds
local function get_delete_button_bounds(slot_index, center_x)
    local slot_x = center_x - SLOT_WIDTH / 2
    local slot_y = SLOT_START_Y + (slot_index - 1) * SLOT_SPACING
    local btn_x = slot_x + SLOT_WIDTH - DELETE_BUTTON_SIZE - DELETE_BUTTON_MARGIN
    local btn_y = slot_y + (SLOT_HEIGHT - DELETE_BUTTON_SIZE) / 2
    return btn_x, btn_y, DELETE_BUTTON_SIZE, DELETE_BUTTON_SIZE
end

--- Advance fade animations
---@param dt number Delta time in seconds
---@param block_mouse boolean|nil If true, skip mouse input processing (e.g., settings menu is open)
function slot_screen.update(dt, block_mouse)
    if state == STATE.HIDDEN then return end

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
        end
    end

    -- Handle mouse hover when menu is open and not blocked by overlay
    if state == STATE.OPEN and not block_mouse then
        local scale = config.ui.SCALE
        local mx = canvas.get_mouse_x()
        local my = canvas.get_mouse_y()

        -- Re-enable mouse input if mouse has moved
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x = mx
            last_mouse_y = my
        end

        -- Check mouse hover over items
        if mouse_active then
            local screen_w = canvas.get_width()
            local center_x = screen_w / (2 * scale)
            local local_mx = mx / scale
            local local_my = my / scale

            if mode == MODE.SELECTING then
                -- Check delete buttons first (they're on top)
                local delete_clicked = false
                for i = 1, SLOT_COUNT do
                    if slot_has_data(i) then
                        local btn_x, btn_y, btn_w, btn_h = get_delete_button_bounds(i, center_x)
                        if local_mx >= btn_x and local_mx <= btn_x + btn_w and
                           local_my >= btn_y and local_my <= btn_y + btn_h then
                            focus_row = i
                            focus_col = 2
                            if canvas.is_mouse_pressed(0) then
                                trigger_selection()
                                delete_clicked = true
                            end
                        end
                    end
                end

                -- Check slots (excluding delete button area)
                if not delete_clicked then
                    for i = 1, SLOT_COUNT do
                        local slot_x = center_x - SLOT_WIDTH / 2
                        local slot_y = SLOT_START_Y + (i - 1) * SLOT_SPACING
                        local btn_x = slot_x + SLOT_WIDTH - DELETE_BUTTON_SIZE - DELETE_BUTTON_MARGIN * 2
                        if local_mx >= slot_x and local_mx <= btn_x and
                           local_my >= slot_y and local_my <= slot_y + SLOT_HEIGHT then
                            focus_row = i
                            focus_col = 1
                            if canvas.is_mouse_pressed(0) then
                                trigger_selection()
                            end
                        end
                    end
                end

                -- Check Back button
                local back_width = 40
                local back_x = center_x - back_width / 2
                if local_mx >= back_x and local_mx <= back_x + back_width and
                   local_my >= BACK_BUTTON_Y - 6 and local_my <= BACK_BUTTON_Y + 6 then
                    focus_row = 4
                    focus_col = 1
                    if canvas.is_mouse_pressed(0) then
                        trigger_selection()
                    end
                end

            elseif mode == MODE.CONFIRMING_DELETE then
                -- Check Cancel and Delete buttons in dialog
                local dialog_w = 120
                local dialog_h = 60
                local dialog_x = center_x - dialog_w / 2
                local dialog_y = 85

                local btn_w = 45
                local btn_h = 14
                local btn_y = dialog_y + dialog_h - btn_h - 8

                -- Cancel button
                local cancel_x = dialog_x + 10
                if local_mx >= cancel_x and local_mx <= cancel_x + btn_w and
                   local_my >= btn_y and local_my <= btn_y + btn_h then
                    confirm_focus = 1
                    if canvas.is_mouse_pressed(0) then
                        execute_delete_confirmation()
                    end
                end

                -- Delete button
                local delete_x = dialog_x + dialog_w - btn_w - 10
                if local_mx >= delete_x and local_mx <= delete_x + btn_w and
                   local_my >= btn_y and local_my <= btn_y + btn_h then
                    confirm_focus = 2
                    if canvas.is_mouse_pressed(0) then
                        execute_delete_confirmation()
                    end
                end
            end
        end
    end
end

--- Draw a single save slot card
---@param slot_index number Slot number (1-3)
---@param x number X position (1x scale)
---@param y number Y position (1x scale)
---@param slot_focused boolean Whether the slot itself is focused
---@param delete_focused boolean Whether the delete button is focused
local function draw_slot_card(slot_index, x, y, slot_focused, delete_focused)
    local data = SaveSlots.get(slot_index)
    local has_data = data ~= nil

    -- Draw slot background
    local bg_color = slot_focused and "#333355" or "#222233"
    canvas.set_color(bg_color)
    canvas.fill_rect(x, y, SLOT_WIDTH, SLOT_HEIGHT)

    -- Draw border
    local border_color = slot_focused and "#FFFF00" or "#444466"
    canvas.set_color(border_color)
    canvas.draw_rect(x, y, SLOT_WIDTH, SLOT_HEIGHT)

    canvas.set_font_family("menu_font")
    canvas.set_text_baseline("middle")

    if has_data then
        -- Slot has save data
        local name = data.campfire_name or "Unknown"
        local playtime = SaveSlots.format_playtime(data.playtime or 0)
        local hp = data.max_health or 3
        local level = data.level or 1

        -- Slot number and campfire name
        canvas.set_font_size(7)
        local title = "[" .. slot_index .. "] " .. name

        -- Title shadow
        canvas.set_color("#000000")
        canvas.draw_text(x + 6, y + 10, title)

        -- Title text
        local title_color = slot_focused and "#FFFF00" or "#FFFFFF"
        canvas.set_color(title_color)
        canvas.draw_text(x + 5, y + 9, title)

        -- Stats line
        canvas.set_font_size(6)
        local stats = playtime .. "  |  HP: " .. hp .. "  |  Lv: " .. level

        -- Stats shadow
        canvas.set_color("#000000")
        canvas.draw_text(x + 11, y + 23, stats)

        -- Stats text
        canvas.set_color("#AAAAAA")
        canvas.draw_text(x + 10, y + 22, stats)

        -- Draw delete button
        local btn_x = x + SLOT_WIDTH - DELETE_BUTTON_SIZE - DELETE_BUTTON_MARGIN
        local btn_y = y + (SLOT_HEIGHT - DELETE_BUTTON_SIZE) / 2

        -- Delete button background
        local btn_bg = delete_focused and "#553333" or "#332222"
        canvas.set_color(btn_bg)
        canvas.fill_rect(btn_x, btn_y, DELETE_BUTTON_SIZE, DELETE_BUTTON_SIZE)

        -- Delete button border
        local btn_border = delete_focused and "#FFFF00" or "#664444"
        canvas.set_color(btn_border)
        canvas.draw_rect(btn_x, btn_y, DELETE_BUTTON_SIZE, DELETE_BUTTON_SIZE)

        -- Draw X character centered in button area
        canvas.set_font_size(5)
        local x_text = "X"
        local x_metrics = canvas.get_text_metrics(x_text)
        local x_color = delete_focused and "#FFFF00" or "#AA6666"
        canvas.set_color(x_color)
        canvas.draw_text(btn_x + (DELETE_BUTTON_SIZE - x_metrics.width) / 2, btn_y + DELETE_BUTTON_SIZE / 2 + 1, x_text)
    else
        -- Empty slot
        canvas.set_font_size(7)
        local title = "[" .. slot_index .. "] New Game"

        -- Title shadow
        canvas.set_color("#000000")
        canvas.draw_text(x + 6, y + 12, title)

        -- Title text
        local title_color = slot_focused and "#FFFF00" or "#FFFFFF"
        canvas.set_color(title_color)
        canvas.draw_text(x + 5, y + 11, title)

        -- Subtitle
        canvas.set_font_size(6)
        canvas.set_color("#666666")
        canvas.draw_text(x + 10, y + 23, "(empty slot)")
    end
end

--- Draw confirmation dialog overlay
---@param center_x number Screen center X (1x scale)
---@param screen_w_1x number Screen width at 1x scale
---@param screen_h_1x number Screen height at 1x scale
local function draw_confirmation_dialog(center_x, screen_w_1x, screen_h_1x)
    local dialog_w = 120
    local dialog_h = 60
    local dialog_x = center_x - dialog_w / 2
    local dialog_y = 85

    -- Black overlay covering full screen
    canvas.set_color("#000000")
    canvas.fill_rect(0, 0, screen_w_1x, screen_h_1x)

    -- Dialog background
    canvas.set_color("#222233")
    canvas.fill_rect(dialog_x, dialog_y, dialog_w, dialog_h)

    -- Dialog border
    canvas.set_color("#FFFF00")
    canvas.draw_rect(dialog_x, dialog_y, dialog_w, dialog_h)

    canvas.set_font_family("menu_font")
    canvas.set_text_baseline("middle")

    -- Title
    canvas.set_font_size(7)
    canvas.set_color("#FFFFFF")
    local title = "Clear this save?"
    local title_metrics = canvas.get_text_metrics(title)
    canvas.draw_text(center_x - title_metrics.width / 2, dialog_y + 14, title)

    -- Warning text
    canvas.set_font_size(6)
    canvas.set_color("#AA6666")
    local warning = "This cannot be undone."
    local warning_metrics = canvas.get_text_metrics(warning)
    canvas.draw_text(center_x - warning_metrics.width / 2, dialog_y + 28, warning)

    -- Buttons
    local btn_w = 45
    local btn_h = 14
    local btn_y = dialog_y + dialog_h - btn_h - 8

    -- Cancel button
    local cancel_x = dialog_x + 10
    local cancel_bg = confirm_focus == 1 and "#333355" or "#222233"
    canvas.set_color(cancel_bg)
    canvas.fill_rect(cancel_x, btn_y, btn_w, btn_h)

    local cancel_border = confirm_focus == 1 and "#FFFF00" or "#444466"
    canvas.set_color(cancel_border)
    canvas.draw_rect(cancel_x, btn_y, btn_w, btn_h)

    canvas.set_font_size(6)
    local cancel_color = confirm_focus == 1 and "#FFFF00" or "#AAAAAA"
    canvas.set_color(cancel_color)
    local cancel_text = "Cancel"
    local cancel_metrics = canvas.get_text_metrics(cancel_text)
    canvas.draw_text(cancel_x + (btn_w - cancel_metrics.width) / 2, btn_y + btn_h / 2, cancel_text)

    -- Delete button
    local delete_x = dialog_x + dialog_w - btn_w - 10
    local delete_bg = confirm_focus == 2 and "#553333" or "#332222"
    canvas.set_color(delete_bg)
    canvas.fill_rect(delete_x, btn_y, btn_w, btn_h)

    local delete_border = confirm_focus == 2 and "#FFFF00" or "#664444"
    canvas.set_color(delete_border)
    canvas.draw_rect(delete_x, btn_y, btn_w, btn_h)

    local delete_color = confirm_focus == 2 and "#FFFF00" or "#AA6666"
    canvas.set_color(delete_color)
    local delete_text = "Delete"
    local delete_metrics = canvas.get_text_metrics(delete_text)
    canvas.draw_text(delete_x + (btn_w - delete_metrics.width) / 2, btn_y + btn_h / 2, delete_text)
end

--- Draw slot screen overlay
function slot_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Calculate alpha based on state
    local alpha = 1
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    canvas.set_global_alpha(alpha)

    -- Draw black background
    canvas.set_color("#000000")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Draw content at 1x scale
    canvas.save()
    canvas.scale(scale, scale)

    local center_x = screen_w / (2 * scale)

    -- Draw title "SELECT SLOT"
    canvas.set_font_family("menu_font")
    canvas.set_font_size(10)
    canvas.set_text_baseline("middle")

    local title = "SELECT SLOT"
    local title_metrics = canvas.get_text_metrics(title)
    local title_x = center_x - title_metrics.width / 2

    -- Title shadow
    canvas.set_color("#000000")
    canvas.draw_text(title_x + 1, TITLE_Y + 1, title)

    -- Title text (yellow)
    canvas.set_color("#FFFF00")
    canvas.draw_text(title_x, TITLE_Y, title)

    -- Draw slot cards
    for i = 1, SLOT_COUNT do
        local slot_x = center_x - SLOT_WIDTH / 2
        local slot_y = SLOT_START_Y + (i - 1) * SLOT_SPACING
        local slot_focused = focus_row == i and focus_col == 1
        local delete_focused = focus_row == i and focus_col == 2
        draw_slot_card(i, slot_x, slot_y, slot_focused, delete_focused)
    end

    -- Draw Back button
    canvas.set_font_size(7)
    local back_text = "Back"
    local back_metrics = canvas.get_text_metrics(back_text)
    local back_x = center_x - back_metrics.width / 2

    -- Back shadow
    canvas.set_color("#000000")
    canvas.draw_text(back_x + 1, BACK_BUTTON_Y + 1, back_text)

    -- Back text
    local back_color = focus_row == 4 and "#FFFF00" or "#AAAAAA"
    canvas.set_color(back_color)
    canvas.draw_text(back_x, BACK_BUTTON_Y, back_text)

    -- Draw confirmation dialog if in delete confirmation mode
    if mode == MODE.CONFIRMING_DELETE then
        draw_confirmation_dialog(center_x, screen_w / scale, screen_h / scale)
    end

    canvas.restore()
    canvas.set_global_alpha(1)
end

return slot_screen
