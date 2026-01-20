--- Audio settings dialog with volume sliders
local canvas = require("canvas")
local controls = require("controls")
local slider = require("ui/slider")
local button = require("ui/button")
local simple_dialogue = require("ui/simple_dialogue")
local utils = require("ui/utils")
local audio = require("audio")
local config = require("config")
local settings_storage = require("settings_storage")

local audio_dialog = {}

-- Dialog dimensions at 1x scale
local base_width = 120
local base_height = 115
local slider_width = 100
local slider_height = 16
local button_height = 12

-- Slider layout
local SLIDER_X = (base_width - slider_width) / 2
local SLIDER_START_Y = 15
local SLIDER_SPACING = 26

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

-- Focus tracking (1-3 = sliders, 4 = close button)
local focus_index = 1
local VOLUME_STEP = 0.05

-- Hold-to-repeat timing for slider adjustment
local REPEAT_INITIAL_DELAY = 0.4
local REPEAT_INTERVAL = 0.08
local hold_direction = 0
local hold_time = 0

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Volume sliders
local volume_sliders = {}

-- Close button
local close_button = nil

--- Convert linear slider value (0-1) to perceptual volume (0-1)
---@param linear number Slider value (0-1)
---@return number Perceptual volume (0-1)
local function linear_to_perceptual(linear)
    return linear * linear
end

---@param slider_key string Key in volume_sliders table
---@param set_volume_fn function Volume setter (receives 0-1 value)
---@param on_change function|nil Optional callback after volume change
---@return function Input handler for slider
local function create_volume_callback(slider_key, set_volume_fn, on_change)
    return function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders[slider_key]:set_value(event.normalized_x)
            local perceptual = linear_to_perceptual(volume_sliders[slider_key]:get_value())
            set_volume_fn(perceptual)
            if on_change then on_change() end
        end
    end
end

volume_sliders.master = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#4488FF", value = 0.75, animate_speed = 0.1,
    on_input = create_volume_callback("master", canvas.set_master_volume)
})

volume_sliders.music = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#44FF88", value = 0.20, animate_speed = 0.1,
    on_input = create_volume_callback("music", audio.set_music_volume)
})

volume_sliders.sfx = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#FF8844", value = 0.6, animate_speed = 0.1,
    on_input = create_volume_callback("sfx", audio.set_sfx_volume, audio.play_sound_check)
})

--- Initialize audio dialog components (call after audio.init)
---@return nil
function audio_dialog.init()
    dialog_box = simple_dialogue.create({ x = 0, y = 0, width = base_width, height = base_height })

    local saved_volumes = settings_storage.load_volumes()
    volume_sliders.master:set_value(saved_volumes.master)
    volume_sliders.music:set_value(saved_volumes.music)
    volume_sliders.sfx:set_value(saved_volumes.sfx)

    -- Convert saved linear slider positions to perceptual volume (squared curve)
    canvas.set_master_volume(linear_to_perceptual(volume_sliders.master:get_value()))
    audio.set_music_volume(linear_to_perceptual(volume_sliders.music:get_value()))
    audio.set_sfx_volume(linear_to_perceptual(volume_sliders.sfx:get_value()))

    close_button = button.create({
        x = 0, y = 0, width = 40, height = button_height,
        label = "Close",
        text_only = true,
        on_click = function()
            audio_dialog.hide()
        end
    })
end

--- Get the slider at the given focus index, or nil if focus is on button
---@param index number Focus index (1-3 = sliders, 4 = button)
---@return table|nil slider
local function get_focused_slider(index)
    local slider_keys = { "master", "music", "sfx" }
    return volume_sliders[slider_keys[index]]
end

--- Get the volume setter function for a given focus index
---@param index number Focus index (1-3)
---@return function|nil setter
local function get_volume_setter(index)
    local setters = {
        canvas.set_master_volume,
        audio.set_music_volume,
        audio.set_sfx_volume,
    }
    return setters[index]
end

--- Save volume settings to storage
---@return nil
local function save_settings()
    local volumes = {
        master = volume_sliders.master:get_value(),
        music = volume_sliders.music:get_value(),
        sfx = volume_sliders.sfx:get_value(),
    }
    settings_storage.save_volumes(volumes)
end

--- Show the audio dialog with fade-in animation
---@return nil
function audio_dialog.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        focus_index = 1
        mouse_active = true
        hold_direction = 0
        hold_time = 0
    end
end

--- Hide the audio dialog with fade-out animation
---@return nil
function audio_dialog.hide()
    if state == STATE.OPEN or state == STATE.FADING_IN then
        state = STATE.FADING_OUT
        fade_progress = 0
    end
end

--- Check if audio dialog is visible
---@return boolean is_active True if dialog is visible or animating
function audio_dialog.is_active()
    return state ~= STATE.HIDDEN
end

--- Process audio dialog input
---@return nil
function audio_dialog.input()
    if state ~= STATE.OPEN then return end

    -- ESC or Back (EAST) closes dialog
    if controls.settings_pressed() or controls.menu_back_pressed() then
        audio_dialog.hide()
        return
    end

    -- Up/Down navigation
    if controls.menu_up_pressed() then
        mouse_active = false
        focus_index = focus_index - 1
        if focus_index < 1 then focus_index = 4 end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focus_index = focus_index + 1
        if focus_index > 4 then focus_index = 1 end
    end

    -- Left/Right to adjust focused slider value (with hold-to-repeat)
    local focused_slider = get_focused_slider(focus_index)
    if focused_slider then
        local dt = canvas.get_delta()
        local left_down = controls.menu_left_down()
        local right_down = controls.menu_right_down()
        local left_pressed = controls.menu_left_pressed()
        local right_pressed = controls.menu_right_pressed()

        -- Determine current direction
        local current_dir = 0
        if left_down then current_dir = -1
        elseif right_down then current_dir = 1 end

        -- Reset hold time if direction changed or released
        if current_dir ~= hold_direction then
            hold_direction = current_dir
            hold_time = 0
        end

        -- Check if we should adjust the slider
        local should_adjust = false
        if left_pressed or right_pressed then
            should_adjust = true
        elseif hold_direction ~= 0 then
            hold_time = hold_time + dt
            if hold_time >= REPEAT_INITIAL_DELAY then
                local repeat_time = hold_time - REPEAT_INITIAL_DELAY
                local repeat_count = math.floor(repeat_time / REPEAT_INTERVAL)
                local prev_repeat_count = math.floor((repeat_time - dt) / REPEAT_INTERVAL)
                if repeat_count > prev_repeat_count then
                    should_adjust = true
                end
            end
        end

        if should_adjust and hold_direction ~= 0 then
            local new_value = focused_slider:get_value() + (VOLUME_STEP * hold_direction)
            focused_slider:set_value(new_value)
            local setter = get_volume_setter(focus_index)
            if setter then setter(linear_to_perceptual(focused_slider:get_value())) end
            if focus_index == 3 then audio.play_sound_check() end
        end
    else
        hold_direction = 0
        hold_time = 0
    end

    -- Confirm button to activate close button
    if controls.menu_confirm_pressed() then
        if focus_index == 4 then
            audio_dialog.hide()
        end
    end
end

--- Update audio dialog animations and mouse input
---@param dt number Delta time in seconds
function audio_dialog.update(dt)
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

        -- Mouse hover handling
        if mouse_active then
            for i = 1, 3 do
                local slider_y = SLIDER_START_Y + SLIDER_SPACING * (i - 1)
                if local_mx >= SLIDER_X and local_mx <= SLIDER_X + slider_width
                    and local_my >= slider_y and local_my <= slider_y + slider_height then
                    focus_index = i
                end
            end

            -- Close button hover
            local close_y = SLIDER_START_Y + SLIDER_SPACING * 3 + 3
            local close_x = (base_width - close_button.width) / 2
            if local_mx >= close_x and local_mx <= close_x + close_button.width
                and local_my >= close_y and local_my <= close_y + button_height then
                focus_index = 4
                if canvas.is_mouse_pressed(0) then
                    audio_dialog.hide()
                end
            end
        end

        for _, s in pairs(volume_sliders) do
            s:update(local_mx, local_my)
        end

        close_button:update(local_mx, local_my)
    end
end

--- Draw centered text with outline at the given position
---@param text string Label text to draw
---@param center_x number Center X position
---@param y number Y position (baseline)
---@param color? string Text fill color (default white)
local function draw_centered_label(text, center_x, y, color)
    local metrics = canvas.get_text_metrics(text)
    local text_x = center_x - metrics.width / 2
    utils.draw_outlined_text(text, text_x, y, color)
end

--- Render the audio dialog
---@return nil
function audio_dialog.draw()
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

    local slider_center_x = SLIDER_X + slider_width / 2

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("bottom")

    local slider_labels = {
        { label = "Master Volume", slider = volume_sliders.master },
        { label = "Music",         slider = volume_sliders.music },
        { label = "SFX",           slider = volume_sliders.sfx },
    }
    for i, item in ipairs(slider_labels) do
        local offset_y = SLIDER_START_Y + SLIDER_SPACING * (i - 1)
        local is_focused = focus_index == i
        local label_color = is_focused and "#FFFF00" or nil
        draw_centered_label(item.label, slider_center_x, offset_y + 1, label_color)
        item.slider.x = SLIDER_X
        item.slider.y = offset_y
        item.slider:draw(is_focused)
    end

    -- Close button
    close_button.x = (base_width - close_button.width) / 2
    close_button.y = SLIDER_START_Y + SLIDER_SPACING * 3 + 3
    close_button:draw(focus_index == 4)

    canvas.restore()
    canvas.set_global_alpha(1)
end

return audio_dialog
