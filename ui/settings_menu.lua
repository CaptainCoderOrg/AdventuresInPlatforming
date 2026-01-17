--- Settings menu overlay with volume controls
local canvas = require("canvas")
local controls = require("controls")
local slider = require("ui/slider")
local button = require("ui/button")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")
local audio = require("audio")
local config = require("config")

local settings_menu = {}

-- Base dimensions at 1x scale (will be scaled by canvas transform)
local base_width = 135
local base_height = 170
local slider_width = 100
local slider_height = 16
local button_width = 100
local button_height = 30

local dialogue_slice = nine_slice.create("dialogue_lg", 144, 144, 34, 18, 34, 20)

local fade_duration = 0.15
local fade_state = "closed"
local fade_progress = 0

-- Focus tracking for keyboard/gamepad navigation
-- 1-3 = sliders (master, music, sfx), 4 = close button
local focus_index = 1
local MENU_ITEMS_COUNT = 4
local VOLUME_STEP = 0.05

-- Hold-to-repeat timing for slider adjustment
local REPEAT_INITIAL_DELAY = 0.4  -- Delay before repeat starts (seconds)
local REPEAT_INTERVAL = 0.08      -- Interval between repeats (seconds)
local hold_direction = 0          -- -1 = left, 0 = none, 1 = right
local hold_time = 0               -- Time held in current direction

local volume_sliders = {}

---@param slider_key string Key in volume_sliders table
---@param set_volume_fn function Volume setter (receives 0-1 value)
---@param on_change function|nil Optional callback after volume change
---@return function Input handler for slider
local function create_volume_callback(slider_key, set_volume_fn, on_change)
    return function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders[slider_key]:set_value(event.normalized_x)
            set_volume_fn(volume_sliders[slider_key]:get_value())
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
    color = "#44FF88", value = 0.00, animate_speed = 0.1,
    on_input = create_volume_callback("music", audio.set_music_volume)
})

volume_sliders.sfx = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#FF8844", value = 0.6, animate_speed = 0.1,
    on_input = create_volume_callback("sfx", audio.set_sfx_volume, audio.play_sound_check)
})

local close_button = button.create({
    x = 0, y = 0, width = button_width, height = button_height,
    label = "Close",
    on_click = function()
        fade_state = "fading_out"
    end
})

--- Apply initial volume settings (call after audio.init)
---@return nil
function settings_menu.init()
    canvas.set_master_volume(volume_sliders.master:get_value())
    audio.set_music_volume(volume_sliders.music:get_value())
    audio.set_sfx_volume(volume_sliders.sfx:get_value())
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

--- Process settings menu input (handles ESC key for toggle and navigation)
---@return nil
function settings_menu.input()
    if controls.settings_pressed() then
        if fade_state == "closed" or fade_state == "fading_out" then
            fade_state = "fading_in"
            focus_index = 1  -- Reset focus when opening
            hold_direction = 0
            hold_time = 0
        elseif fade_state == "open" or fade_state == "fading_in" then
            fade_state = "fading_out"
        end
    end

    -- Handle keyboard/gamepad navigation when menu is open
    if fade_state == "open" then
        -- Up/Down navigation
        if controls.menu_up_pressed() then
            focus_index = focus_index - 1
            if focus_index < 1 then
                focus_index = MENU_ITEMS_COUNT
            end
        elseif controls.menu_down_pressed() then
            focus_index = focus_index + 1
            if focus_index > MENU_ITEMS_COUNT then
                focus_index = 1
            end
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
                -- Initial press always triggers
                should_adjust = true
            elseif hold_direction ~= 0 then
                -- Holding - check repeat timing
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
                if setter then setter(focused_slider:get_value()) end
                -- Play sound check for SFX slider
                if focus_index == 3 then audio.play_sound_check() end
            end
        else
            -- Not on a slider, reset hold state
            hold_direction = 0
            hold_time = 0
        end

        -- Confirm button to activate close button
        if focus_index == MENU_ITEMS_COUNT and controls.menu_confirm_pressed() then
            fade_state = "fading_out"
        end
    end
end

--- Advance fade animation and update controls
---@return nil
function settings_menu.update()
    local dt = canvas.get_delta()
    local speed = dt / fade_duration

    if fade_state == "fading_in" then
        fade_progress = math.min(1, fade_progress + speed)
        if fade_progress >= 1 then
            fade_state = "open"
        end
    elseif fade_state == "fading_out" then
        fade_progress = math.max(0, fade_progress - speed)
        if fade_progress <= 0 then
            fade_state = "closed"
        end
    end

    if fade_state == "open" then
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local screen_h = canvas.get_height()

        -- Must match draw() positioning for correct mouse coordinate conversion
        local menu_x = (screen_w - base_width * scale) / 2
        local menu_y = (screen_h - base_height * scale) / 2

        -- Convert screen mouse to local 1x coordinates
        local local_mx = (canvas.get_mouse_x() - menu_x) / scale
        local local_my = (canvas.get_mouse_y() - menu_y) / scale

        for _, s in pairs(volume_sliders) do
            s:update(local_mx, local_my)
        end
        close_button:update(local_mx, local_my)
    end
end

--- Check if settings menu is blocking game input
---@return boolean
function settings_menu.is_open()
    return fade_state ~= "closed"
end

---@param text string Label text to draw
---@param center_x number Center X position
---@param y number Y position (baseline)
---@param color? string Text fill color (default white)
local function draw_centered_label(text, center_x, y, color)
    local metrics = canvas.get_text_metrics(text)
    local text_x = center_x - metrics.width / 2
    utils.draw_outlined_text(text, text_x, y, color)
end

--- Draw the settings menu overlay
---@return nil
function settings_menu.draw()
    if fade_state == "closed" then
        return
    end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - base_width * scale) / 2
    local menu_y = (screen_h - base_height * scale) / 2

    -- Draw background overlay (before transform, covers full screen)
    canvas.set_global_alpha(fade_progress)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Apply canvas transform for pixel-perfect scaling
    canvas.save()
    canvas.translate(menu_x, menu_y)
    canvas.scale(scale, scale)

    nine_slice.draw(dialogue_slice, 0, 0, base_width, base_height)

    -- Slider layout at 1x scale
    local slider_x = (base_width - slider_width) / 2
    local slider_center_x = slider_x + slider_width / 2
    local slider_start_y = 30
    local slider_spacing = 30
    local label_offset = 4

    canvas.set_font_family("menu_font")
    canvas.set_font_size(12)
    canvas.set_text_baseline("bottom")

    local slider_labels = {
        { label = "Master Volume", slider = volume_sliders.master },
        { label = "Music",         slider = volume_sliders.music },
        { label = "SFX",           slider = volume_sliders.sfx },
    }
    for i, item in ipairs(slider_labels) do
        local offset_y = slider_start_y + slider_spacing * (i - 1)
        local is_focused = focus_index == i
        local label_color = is_focused and "#FFFF00" or nil
        draw_centered_label(item.label, slider_center_x, offset_y - label_offset + 5, label_color)
        item.slider.x = slider_x
        item.slider.y = offset_y
        item.slider:draw(is_focused)
    end

    close_button.x = (base_width - close_button.width) / 2
    close_button.y = slider_start_y + slider_spacing * 3
    close_button:draw(focus_index == MENU_ITEMS_COUNT)

    canvas.restore()
    canvas.set_global_alpha(1)
end

return settings_menu
