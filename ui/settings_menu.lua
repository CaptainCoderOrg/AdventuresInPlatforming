--- Settings menu overlay with tabbed panels (Audio / Controls)
local canvas = require("canvas")
local controls = require("controls")
local slider = require("ui/slider")
local button = require("ui/button")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")
local audio = require("audio")
local config = require("config")
local keybind_panel = require("ui/keybind_panel")
local settings_storage = require("settings_storage")

local settings_menu = {}

-- Base dimensions at 1x scale (will be scaled by canvas transform)
-- At 5x scale: 384x216 effective pixels, so menu should fit comfortably
local base_width = 160
local base_height = 205
local slider_width = 100
local slider_height = 16
local button_width = 40
local button_height = 12

-- Audio tab slider layout
local SLIDER_X = (base_width - slider_width) / 2
local SLIDER_START_Y = 38
local SLIDER_SPACING = 26

-- Tab header layout
local TAB_HEADER_Y = 12
local TAB_AUDIO_X = 35
local TAB_CONTROLS_X = 90
local TAB_CLICK_WIDTH = 40
local TAB_CLICK_HEIGHT = 14

local dialogue_slice = nine_slice.create("dialogue_lg", 144, 144, 34, 18, 34, 20)

local fade_duration = 0.15
local fade_state = "closed"
local fade_progress = 0

-- Tab system
local TABS = { "audio", "controls" }
local TAB_LABELS = { audio = "Audio", controls = "Controls" }
local current_tab = 1

-- Audio tab focus tracking (1-3 = sliders, 4 = close button)
local audio_focus_index = 1
local AUDIO_ITEMS_COUNT = 4
local VOLUME_STEP = 0.05

-- Hold-to-repeat timing for slider adjustment
local REPEAT_INITIAL_DELAY = 0.4
local REPEAT_INTERVAL = 0.08
local hold_direction = 0
local hold_time = 0

-- Tab hover state for mouse feedback
local hovering_audio_tab = false
local hovering_controls_tab = false

-- Mouse input tracking (disabled when using keyboard/gamepad navigation)
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Controls tab panel
local controls_panel = nil

-- Shared close button
local close_button = nil

--- Convert linear slider value (0-1) to perceptual volume (0-1)
--- Human hearing is logarithmic, so we apply a power curve for even-sounding volume steps
---@param linear number Slider value (0-1)
---@return number Perceptual volume (0-1)
local function linear_to_perceptual(linear)
    return linear * linear
end

local volume_sliders = {}

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

--- Initialize volume settings and create UI components (call after audio.init)
---@return nil
function settings_menu.init()
    -- Load saved volumes from storage
    local saved_volumes = settings_storage.load_volumes()
    volume_sliders.master:set_value(saved_volumes.master)
    volume_sliders.music:set_value(saved_volumes.music)
    volume_sliders.sfx:set_value(saved_volumes.sfx)

    -- Apply loaded volumes to audio systems
    canvas.set_master_volume(linear_to_perceptual(volume_sliders.master:get_value()))
    audio.set_music_volume(linear_to_perceptual(volume_sliders.music:get_value()))
    audio.set_sfx_volume(linear_to_perceptual(volume_sliders.sfx:get_value()))

    -- Create controls panel
    controls_panel = keybind_panel.create({
        x = 0,
        y = 0,
        width = base_width - 15,
        height = base_height - 40,
    })

    -- Create close button
    close_button = button.create({
        x = 0, y = 0, width = button_width, height = button_height,
        label = "Close",
        text_only = true,
        on_click = function()
            fade_state = "fading_out"
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

--- Set focus to the current tab's header
local function focus_current_tab_header()
    if TABS[current_tab] == "audio" then
        audio_focus_index = 0
    else
        controls_panel.focus_index = -2
    end
end

--- Calculate tab header layout (must be called after setting font)
---@return table layout {audio_x, controls_x, audio_w, controls_w, tab_top, tab_bottom}
local function get_tab_header_layout()
    local center_x = base_width / 2
    local audio_metrics = canvas.get_text_metrics("Audio")
    local sep_metrics = canvas.get_text_metrics("|")
    local controls_metrics = canvas.get_text_metrics("Controls")
    local total_width = audio_metrics.width + sep_metrics.width + controls_metrics.width + 10
    local start_x = center_x - total_width / 2
    return {
        audio_x = start_x,
        controls_x = start_x + audio_metrics.width + sep_metrics.width + 10,
        audio_w = audio_metrics.width,
        controls_w = controls_metrics.width,
        sep_x = start_x + audio_metrics.width + 5,
        tab_top = TAB_HEADER_Y - TAB_CLICK_HEIGHT / 2,
        tab_bottom = TAB_HEADER_Y + TAB_CLICK_HEIGHT / 2,
    }
end

--- Switch to next settings tab (keeps focus on tab header)
local function next_tab()
    current_tab = (current_tab % #TABS) + 1
    focus_current_tab_header()
end

--- Switch to previous settings tab (keeps focus on tab header)
local function prev_tab()
    current_tab = ((current_tab - 2) % #TABS) + 1
    focus_current_tab_header()
end

--- Handle tab header navigation (left/right to switch tabs)
--- Returns true if input was handled
local function handle_tab_header_navigation()
    local is_on_header = (TABS[current_tab] == "audio" and audio_focus_index == 0)
        or (TABS[current_tab] == "controls" and controls_panel.focus_index == -2)
    if not is_on_header then return false end

    if controls.menu_left_pressed() then
        prev_tab()
        return true
    elseif controls.menu_right_pressed() then
        next_tab()
        return true
    end
    return false
end

--- Handle audio tab input
local function handle_audio_input()
    -- Tab header navigation (left/right to switch tabs)
    if handle_tab_header_navigation() then return end

    -- Up/Down navigation (disables mouse hover)
    if controls.menu_up_pressed() then
        mouse_active = false
        audio_focus_index = audio_focus_index - 1
        if audio_focus_index < 0 then
            audio_focus_index = AUDIO_ITEMS_COUNT
        end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        audio_focus_index = audio_focus_index + 1
        if audio_focus_index > AUDIO_ITEMS_COUNT then
            audio_focus_index = 0
        end
    end

    -- No further input when on tab header
    if audio_focus_index == 0 then return end

    -- Left/Right to adjust focused slider value (with hold-to-repeat)
    local focused_slider = get_focused_slider(audio_focus_index)
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
            local setter = get_volume_setter(audio_focus_index)
            if setter then setter(linear_to_perceptual(focused_slider:get_value())) end
            if audio_focus_index == 3 then audio.play_sound_check() end
        end
    else
        hold_direction = 0
        hold_time = 0
    end

    -- Confirm button to activate close button
    if audio_focus_index == AUDIO_ITEMS_COUNT and controls.menu_confirm_pressed() then
        fade_state = "fading_out"
    end
end

--- Handle controls tab input
local function handle_controls_input()
    -- If panel is listening for input, let it handle everything
    if controls_panel:is_listening() then
        return
    end

    -- Tab header navigation (left/right to switch tabs)
    if handle_tab_header_navigation() then return end

    local reset_focus = #controls_panel.rows + 1

    -- Handle special focus positions first
    if controls_panel.focus_index == -2 then
        -- Settings tab header (Audio/Controls) - up/down navigation
        if controls.menu_down_pressed() then
            mouse_active = false
            controls_panel.focus_index = -1  -- Move to scheme tab
            return
        elseif controls.menu_up_pressed() then
            mouse_active = false
            controls_panel.focus_index = reset_focus  -- Wrap to reset button
            return
        end
        return
    elseif controls_panel.focus_index == -1 then
        -- Scheme tab header (Keyboard/Gamepad)
        if controls.menu_left_pressed() then
            controls_panel:cycle_scheme(-1)
            return
        elseif controls.menu_right_pressed() then
            controls_panel:cycle_scheme(1)
            return
        elseif controls.menu_up_pressed() then
            mouse_active = false
            controls_panel.focus_index = -2  -- Move to settings tab header
            return
        elseif controls.menu_down_pressed() then
            mouse_active = false
            controls_panel.focus_index = 1  -- Move to first row
            return
        end
        return
    end

    -- Let panel handle row and reset button navigation (also disables mouse)
    if controls.menu_up_pressed() or controls.menu_down_pressed() then
        mouse_active = false
    end
    controls_panel:input()
end

--- Process settings menu input (handles ESC for toggle and tab navigation)
function settings_menu.input()
    if controls.settings_pressed() then
        if fade_state == "closed" or fade_state == "fading_out" then
            fade_state = "fading_in"
            -- Reset focus when opening
            audio_focus_index = 1
            if controls_panel then
                controls_panel:reset_focus()
            end
            hold_direction = 0
            hold_time = 0
        elseif fade_state == "open" or fade_state == "fading_in" then
            fade_state = "fading_out"
        end
    end

    -- Handle input when menu is open
    if fade_state == "open" then
        if TABS[current_tab] == "audio" then
            handle_audio_input()
        else
            handle_controls_input()
        end
    end
end

--- Advance fade animation and update active tab components
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
            -- Reset hover states when menu closes
            hovering_audio_tab = false
            hovering_controls_tab = false

            -- Save all settings to storage (failures logged internally by settings_storage)
            local volumes = {
                master = volume_sliders.master:get_value(),
                music = volume_sliders.music:get_value(),
                sfx = volume_sliders.sfx:get_value(),
            }
            settings_storage.save_all(
                volumes,
                controls.get_all_bindings("keyboard"),
                controls.get_all_bindings("gamepad")
            )
        end
    end

    if fade_state == "open" then
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

        -- Calculate tab header positions
        canvas.set_font_family("menu_font")
        canvas.set_font_size(8)
        local layout = get_tab_header_layout()

        -- Check for tab header hover and click (disabled when listening for keybind or mouse inactive)
        local panel_listening = controls_panel and controls_panel:is_listening()

        if mouse_active then
            hovering_audio_tab = local_my >= layout.tab_top and local_my <= layout.tab_bottom
                and local_mx >= layout.audio_x and local_mx <= layout.audio_x + layout.audio_w
            hovering_controls_tab = local_my >= layout.tab_top and local_my <= layout.tab_bottom
                and local_mx >= layout.controls_x and local_mx <= layout.controls_x + layout.controls_w
        else
            hovering_audio_tab = false
            hovering_controls_tab = false
        end

        -- Don't process hover/click when panel is listening for keybind input or mouse inactive
        if mouse_active and not panel_listening then
            if hovering_audio_tab then
                if TABS[current_tab] == "audio" then
                    audio_focus_index = 0
                end
                if canvas.is_mouse_pressed(0) then
                    current_tab = 1
                    audio_focus_index = 0
                end
            elseif hovering_controls_tab then
                if TABS[current_tab] == "controls" then
                    controls_panel.focus_index = -2
                end
                if canvas.is_mouse_pressed(0) then
                    current_tab = 2
                    controls_panel.focus_index = -2
                end
            end
        end

        if TABS[current_tab] == "audio" then
            -- Audio tab mouse hover (only when mouse is active)
            if mouse_active then
                for i = 1, 3 do
                    local slider_y = SLIDER_START_Y + SLIDER_SPACING * (i - 1)
                    if local_mx >= SLIDER_X and local_mx <= SLIDER_X + slider_width
                        and local_my >= slider_y and local_my <= slider_y + slider_height then
                        audio_focus_index = i
                    end
                end

                -- Close button hover
                local close_y = SLIDER_START_Y + SLIDER_SPACING * 3 + 3
                local close_x = (base_width - button_width) / 2
                if local_mx >= close_x and local_mx <= close_x + button_width
                    and local_my >= close_y and local_my <= close_y + button_height then
                    audio_focus_index = AUDIO_ITEMS_COUNT
                    if canvas.is_mouse_pressed(0) then
                        fade_state = "fading_out"
                    end
                end
            end

            for _, s in pairs(volume_sliders) do
                s:update(local_mx, local_my)
            end

            close_button:update(local_mx, local_my)
        else
            -- Offset mouse coordinates by panel position
            local panel_x = (base_width - controls_panel.width) / 2
            local panel_y = 24
            controls_panel:update(dt, local_mx - panel_x, local_my - panel_y, mouse_active)
        end
    end
end

--- Check if settings menu is visible and blocking game input
---@return boolean is_open True if menu is open or animating
function settings_menu.is_open()
    return fade_state ~= "closed"
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

--- Draw the settings tab header showing "Audio | Controls"
---@param is_focused boolean Whether the tab header is focused
local function draw_tab_header(is_focused)
    canvas.set_font_family("menu_font")
    canvas.set_font_size(8)
    canvas.set_text_baseline("middle")

    -- Determine colors based on selection, focus, and hover
    local audio_color, controls_color
    if current_tab == 1 then
        audio_color = is_focused and "#FFFF00" or "#FFFFFF"
        controls_color = hovering_controls_tab and "#FFFFFF" or "#888888"
    else
        audio_color = hovering_audio_tab and "#FFFFFF" or "#888888"
        controls_color = is_focused and "#FFFF00" or "#FFFFFF"
    end

    -- Draw "Audio | Controls"
    local layout = get_tab_header_layout()
    utils.draw_outlined_text("Audio", layout.audio_x, TAB_HEADER_Y, audio_color)
    utils.draw_outlined_text("|", layout.sep_x, TAB_HEADER_Y, "#666666")
    utils.draw_outlined_text("Controls", layout.controls_x, TAB_HEADER_Y, controls_color)
end

--- Draw the audio tab content
local function draw_audio_tab()
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
        local is_focused = audio_focus_index == i
        local label_color = is_focused and "#FFFF00" or nil
        draw_centered_label(item.label, slider_center_x, offset_y + 1, label_color)
        item.slider.x = SLIDER_X
        item.slider.y = offset_y
        item.slider:draw(is_focused)
    end

    close_button.x = (base_width - close_button.width) / 2
    close_button.y = SLIDER_START_Y + SLIDER_SPACING * 3 + 3
    close_button:draw(audio_focus_index == AUDIO_ITEMS_COUNT)
end

--- Draw the controls tab content
local function draw_controls_tab()
    local panel_x = (base_width - controls_panel.width) / 2
    local panel_y = 24

    canvas.save()
    canvas.translate(panel_x, panel_y)
    controls_panel:draw()
    canvas.restore()
end

--- Render the settings menu overlay with background dim and current tab
function settings_menu.draw()
    if fade_state == "closed" then
        return
    end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - base_width * scale) / 2
    local menu_y = (screen_h - base_height * scale) / 2

    -- Draw background overlay
    canvas.set_global_alpha(fade_progress)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Apply canvas transform for pixel-perfect scaling
    canvas.save()
    canvas.translate(menu_x, menu_y)
    canvas.scale(scale, scale)

    nine_slice.draw(dialogue_slice, 0, 0, base_width, base_height)

    -- Draw tab header
    local tab_focused = (TABS[current_tab] == "audio" and audio_focus_index == 0)
                     or (TABS[current_tab] == "controls" and controls_panel.focus_index == -2)
    draw_tab_header(tab_focused)

    -- Draw current tab content
    if TABS[current_tab] == "audio" then
        draw_audio_tab()
    else
        draw_controls_tab()
    end

    canvas.restore()
    canvas.set_global_alpha(1)
end

return settings_menu
