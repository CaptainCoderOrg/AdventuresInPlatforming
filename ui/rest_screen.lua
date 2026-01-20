--- Rest screen overlay with circular viewport effect around campfire
--- Shows player stats, audio settings, and controls while resting at a campfire.
--- Supports menu navigation, settings editing, and confirmation dialogs.
local canvas = require("canvas")
local controls = require("controls")
local button = require("ui/button")
local config = require("config")
local simple_dialogue = require("ui/simple_dialogue")
local Playtime = require("Playtime")
local SaveSlots = require("SaveSlots")
local slider = require("ui/slider")
local keybind_panel = require("ui/keybind_panel")
local audio = require("audio")
local settings_storage = require("settings_storage")
local utils = require("ui/utils")

local rest_screen = {}

-- State machine constants
local NAV_MODE = { MENU = "menu", SETTINGS = "settings", CONFIRM = "confirm" }
local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
    RELOADING = "reloading",
    FADING_BACK_IN = "fading_back_in",
}

-- Timing configuration (seconds)
local FADE_IN_DURATION = 0.5
local FADE_OUT_DURATION = 0.3
local RELOAD_PAUSE = 0.1
local FADE_BACK_IN_DURATION = 0.4

-- Circle viewport configuration
local CIRCLE_RADIUS = 40
local PULSE_SPEED = 2
local PULSE_AMOUNT = 0.08
local CIRCLE_EDGE_PADDING = 8
local CIRCLE_LERP_DURATION = 0.3

--- Apply ease-out curve to interpolation value
--- Uses quadratic ease-out: 1 - (1 - t)^2
---@param t number Linear interpolation value (0-1)
---@return number Eased interpolation value
local function ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

-- Layout constants (at 1x scale)
local BUTTON_WIDTH = 70
local BUTTON_HEIGHT = 12
local BUTTON_SPACING = 4
local BUTTON_TOP_OFFSET = 10
local DIALOGUE_HEIGHT = 42
local DIALOGUE_PADDING = 8
local DIALOGUE_GAP = 8

-- Hold-to-repeat timing for slider adjustment
local REPEAT_INITIAL_DELAY = 0.4
local REPEAT_INTERVAL = 0.08
local VOLUME_STEP = 0.05

-- Menu configuration
local MENU_ITEM_COUNT = 5

-- Screen state
local state = STATE.HIDDEN
local fade_progress = 0
local elapsed_time = 0
local nav_mode = NAV_MODE.MENU
local confirm_selection = 2

-- Navigation state
local focused_index = 1
local hovered_index = nil
local active_panel_index = 1
local audio_focus_index = 1

-- Hold-to-repeat state
local hold_direction = 0
local hold_time = 0

-- Mouse tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Campfire and camera state
local campfire_x = 0
local campfire_y = 0
local camera_ref = nil
local original_camera_x = 0
local original_camera_y = 0
local last_camera_x = 0
local last_camera_y = 0

-- Circle lerp state (screen pixels)
local circle_start_x = 0
local circle_start_y = 0
local circle_target_x = 0
local circle_target_y = 0
local circle_lerp_t = 0

-- Callbacks
local continue_callback = nil
local return_to_title_callback = nil

-- UI components (populated in init)
local status_button = nil
local audio_button = nil
local controls_button = nil
local continue_button = nil
local return_to_title_button = nil
local rest_dialogue = nil
local player_info_dialogue = nil
local menu_dialogue = nil
local buttons = nil
local volume_sliders = {}
local controls_panel = nil

---@type table|nil Player reference for stats display
local player_ref = nil

--- Return to menu mode showing the status panel
--- Common exit point for all settings/confirm states
local function return_to_status()
    nav_mode = NAV_MODE.MENU
    active_panel_index = 1
end

--- Create a text-only menu button with standard dimensions
---@param label string Button label text
---@return table button
local function create_menu_button(label)
    return button.create({
        x = 0, y = 0,
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        label = label,
        text_only = true,
    })
end

--- Wrap an index within a range (1 to max, cycling)
---@param index number Current index
---@param delta number Change amount (-1 or 1)
---@param max number Maximum value
---@return number Wrapped index
local function wrap_index(index, delta, max)
    index = index + delta
    if index < 1 then return max end
    if index > max then return 1 end
    return index
end

--- Calculate layout dimensions for all UI panels
---@param scale number UI scale factor
---@return table Layout dimensions for menu, info panel, and rest dialogue
local function calculate_layout(scale)
    local screen_w = canvas.get_width() / scale
    local screen_h = canvas.get_height() / scale
    local circle_right = CIRCLE_EDGE_PADDING + CIRCLE_RADIUS * 2
    local circle_top = screen_h - CIRCLE_EDGE_PADDING - CIRCLE_RADIUS * 2

    local menu_x = DIALOGUE_PADDING
    local menu_y = DIALOGUE_PADDING
    local menu_width = circle_right - DIALOGUE_PADDING
    local menu_height = circle_top - DIALOGUE_GAP - DIALOGUE_PADDING

    local info_x = circle_right + DIALOGUE_PADDING
    local info_y = DIALOGUE_PADDING
    local info_width = screen_w - info_x - DIALOGUE_PADDING
    local rest_y = screen_h - DIALOGUE_PADDING - DIALOGUE_HEIGHT
    local info_height = rest_y - DIALOGUE_GAP - DIALOGUE_PADDING

    return {
        menu = { x = menu_x, y = menu_y, width = menu_width, height = menu_height },
        info = { x = info_x, y = info_y, width = info_width, height = info_height },
        rest = { x = info_x, y = rest_y, width = info_width, height = DIALOGUE_HEIGHT },
    }
end

--- Position all menu buttons within the menu dialogue
---@param menu_x number Menu dialogue X position
---@param menu_y number Menu dialogue Y position
---@param menu_width number Menu dialogue width
---@param menu_height number Menu dialogue height
local function position_buttons(menu_x, menu_y, menu_width, menu_height)
    local button_x = menu_x + (menu_width - BUTTON_WIDTH) / 2
    local button_start_y = menu_y + BUTTON_TOP_OFFSET

    status_button.x = button_x
    status_button.y = button_start_y

    audio_button.x = button_x
    audio_button.y = button_start_y + BUTTON_HEIGHT + BUTTON_SPACING

    controls_button.x = button_x
    controls_button.y = button_start_y + (BUTTON_HEIGHT + BUTTON_SPACING) * 2

    -- Bottom-aligned action buttons
    continue_button.x = button_x
    continue_button.y = menu_y + menu_height - BUTTON_TOP_OFFSET - (BUTTON_HEIGHT + BUTTON_SPACING) - BUTTON_HEIGHT

    return_to_title_button.x = button_x
    return_to_title_button.y = menu_y + menu_height - BUTTON_TOP_OFFSET - BUTTON_HEIGHT
end

--- Initialize rest screen components (creates menu buttons)
---@return nil
function rest_screen.init()
    status_button = create_menu_button("Status")
    audio_button = create_menu_button("Audio")
    controls_button = create_menu_button("Controls")
    continue_button = create_menu_button("Continue")
    return_to_title_button = create_menu_button("Return to Title")

    -- Create volume sliders (copy pattern from settings_menu.lua)
    local slider_width = 80
    local slider_height = 14

    volume_sliders.master = slider.create({
        x = 0, y = 0, width = slider_width, height = slider_height,
        color = "#4488FF", value = 0.75, animate_speed = 0.1,
        on_input = function(event)
            if event.type == "press" or event.type == "drag" then
                volume_sliders.master:set_value(event.normalized_x)
                local perceptual = volume_sliders.master:get_value() * volume_sliders.master:get_value()
                canvas.set_master_volume(perceptual)
            end
        end
    })

    volume_sliders.music = slider.create({
        x = 0, y = 0, width = slider_width, height = slider_height,
        color = "#44FF88", value = 0.20, animate_speed = 0.1,
        on_input = function(event)
            if event.type == "press" or event.type == "drag" then
                volume_sliders.music:set_value(event.normalized_x)
                local perceptual = volume_sliders.music:get_value() * volume_sliders.music:get_value()
                audio.set_music_volume(perceptual)
            end
        end
    })

    volume_sliders.sfx = slider.create({
        x = 0, y = 0, width = slider_width, height = slider_height,
        color = "#FF8844", value = 0.6, animate_speed = 0.1,
        on_input = function(event)
            if event.type == "press" or event.type == "drag" then
                volume_sliders.sfx:set_value(event.normalized_x)
                local perceptual = volume_sliders.sfx:get_value() * volume_sliders.sfx:get_value()
                audio.set_sfx_volume(perceptual)
                audio.play_sound_check()
            end
        end
    })

    -- Load saved volumes from storage
    local saved_volumes = settings_storage.load_volumes()
    volume_sliders.master:set_value(saved_volumes.master)
    volume_sliders.music:set_value(saved_volumes.music)
    volume_sliders.sfx:set_value(saved_volumes.sfx)

    -- Create keybind panel
    controls_panel = keybind_panel.create({
        x = 0,
        y = 0,
        width = 120,
        height = 140,
    })

    rest_dialogue = simple_dialogue.create({
        x = 0,
        y = 0,
        width = 100,
        height = DIALOGUE_HEIGHT,
        text = "Resting restores your hit points and saves your progress. Enemies also respawn when you rest."
    })

    player_info_dialogue = simple_dialogue.create({
        x = 0,
        y = 0,
        width = 100,
        height = 100,
        text = ""
    })

    menu_dialogue = simple_dialogue.create({
        x = 0,
        y = 0,
        width = 80,
        height = 100,
        text = ""
    })

    buttons = { status_button, audio_button, controls_button, continue_button, return_to_title_button }
end

--- Hide and reset the rest screen (used when returning to title)
---@return nil
function rest_screen.hide()
    state = STATE.HIDDEN
    fade_progress = 0
    return_to_status()
end

--- Trigger the fade out and continue sequence
---@return nil
function rest_screen.trigger_continue()
    state = STATE.FADING_OUT
    fade_progress = 0
end

--- Save camera position every frame (called from main.lua before player:update)
--- This ensures we capture the camera position before anything can modify it
---@param x number Camera X position in tiles
---@param y number Camera Y position in tiles
function rest_screen.save_camera_position(x, y)
    last_camera_x = x
    last_camera_y = y
end

--- Build the stats text for the player info dialogue
---@param player table Player instance
---@return string Stats text with newlines
local function build_stats_text(player)
    if not player then return "" end

    local lines = {
        "Level: " .. player.level,
        "Exp: " .. player.experience,
        "Gold: " .. player.gold,
        "",
        "HP: " .. player:health() .. "/" .. player.max_health,
        "DEF: " .. player.defense,
        "STR: " .. player.strength,
        "CRIT: " .. player.critical_chance .. "%",
        "",
        "Time: " .. SaveSlots.format_playtime(Playtime.get())
    }
    return table.concat(lines, "\n")
end

--- Show the rest screen centered on a campfire
---@param world_x number Campfire center X in tile coordinates
---@param world_y number Campfire center Y in tile coordinates
---@param camera table Camera instance for position calculation
---@param player table|nil Player instance for stats display
function rest_screen.show(world_x, world_y, camera, player)
    if state == STATE.HIDDEN then
        campfire_x = world_x
        campfire_y = world_y
        camera_ref = camera
        player_ref = player
        state = STATE.FADING_IN
        fade_progress = 0
        elapsed_time = 0

        -- Use the last known good camera position (saved in main.lua before player:update)
        -- This ensures we capture the position before anything can modify it
        original_camera_x = last_camera_x
        original_camera_y = last_camera_y

        -- Initialize circle lerp: start at campfire, target bottom-left
        local sprites = require("sprites")
        local scaled_radius = CIRCLE_RADIUS * config.ui.SCALE

        -- Starting position (campfire screen coords)
        circle_start_x = (world_x - camera:get_x()) * sprites.tile_size
        circle_start_y = (world_y - camera:get_y()) * sprites.tile_size

        -- Target position: bottom-left with padding (circle center offset by radius)
        circle_target_x = CIRCLE_EDGE_PADDING + scaled_radius
        circle_target_y = canvas.get_height() - CIRCLE_EDGE_PADDING - scaled_radius

        circle_lerp_t = 0  -- Start at campfire position
    end

    -- Always reset navigation state when showing (in case returning from title)
    mouse_active = true
    focused_index = 1  -- Default to Status
    nav_mode = NAV_MODE.MENU  -- Start in menu mode
    active_panel_index = 1  -- Show stats by default
    audio_focus_index = 1
    confirm_selection = 2  -- Default to No
    hold_direction = 0
    hold_time = 0
    hovered_index = nil
    if controls_panel then
        controls_panel:reset_focus()
    end
end

--- Set the continue callback function (reloads level from checkpoint)
---@param fn function Function to call when continuing
function rest_screen.set_continue_callback(fn)
    continue_callback = fn
end

--- Set the return to title callback function
---@param fn function Function to call when returning to title
function rest_screen.set_return_to_title_callback(fn)
    return_to_title_callback = fn
end

--- Check if rest screen is blocking game input
---@return boolean is_active True if rest screen is visible or animating
function rest_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Get the original camera position from when rest screen was opened
---@return number x Camera X position in tiles
---@return number y Camera Y position in tiles
function rest_screen.get_original_camera_pos()
    return original_camera_x, original_camera_y
end

--- Check if the circle should be visible (during fade in/out or when open)
---@return boolean True if circle is visible
local function is_circle_visible()
    return state == STATE.FADING_IN or state == STATE.OPEN or state == STATE.FADING_OUT
end

--- Get the current camera offset to keep campfire centered in circle
---@return number offset_x Camera X offset in pixels
---@return number offset_y Camera Y offset in pixels
function rest_screen.get_camera_offset()
    if not is_circle_visible() then
        return 0, 0
    end

    local t = ease_out(circle_lerp_t)
    local offset_x = (circle_target_x - circle_start_x) * t
    local offset_y = (circle_target_y - circle_start_y) * t

    return offset_x, offset_y
end

--- Trigger the currently focused menu action based on focused_index
--- 1 = Status, 2 = Audio, 3 = Controls, 4 = Continue, 5 = Return to Title
---@return nil
local function trigger_focused_action()
    if focused_index == 1 then
        -- Show Status (player stats)
        return_to_status()
    elseif focused_index == 2 then
        -- Enter Audio settings
        nav_mode = NAV_MODE.SETTINGS
        active_panel_index = 2
        audio_focus_index = 1
    elseif focused_index == 3 then
        -- Enter Controls settings
        nav_mode = NAV_MODE.SETTINGS
        active_panel_index = 3
        controls_panel:reset_focus()
    elseif focused_index == 4 then
        rest_screen.trigger_continue()
    elseif focused_index == 5 then
        -- Show confirmation dialog
        nav_mode = NAV_MODE.CONFIRM
        confirm_selection = 2  -- Default to No
    end
end

--- Get the slider at the given focus index, or nil if index is out of range
---@param index number Focus index (1-3)
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

--- Handle input when in Audio settings mode
---@return nil
local function handle_audio_settings_input()
    -- Exit settings with left direction or back button (Escape/gamepad EAST)
    if controls.menu_left_pressed() or controls.menu_back_pressed() then
        return_to_status()
        hold_direction = 0
        hold_time = 0
        return
    end

    -- Up/Down navigation for sliders
    if controls.menu_up_pressed() then
        mouse_active = false
        audio_focus_index = wrap_index(audio_focus_index, -1, 3)
    elseif controls.menu_down_pressed() then
        mouse_active = false
        audio_focus_index = wrap_index(audio_focus_index, 1, 3)
    end

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
            if setter then
                local perceptual = focused_slider:get_value() * focused_slider:get_value()
                setter(perceptual)
            end
            if audio_focus_index == 3 then audio.play_sound_check() end
        end
    else
        hold_direction = 0
        hold_time = 0
    end
end

--- Handle input when in Controls settings mode
---@return nil
local function handle_controls_settings_input()
    -- If panel is listening for input, let it handle everything
    if controls_panel:is_listening() then
        return
    end

    -- Exit settings with back button (Escape/gamepad EAST)
    if controls.menu_back_pressed() then
        return_to_status()
        return
    end

    -- Exit settings with left direction (when not on scheme tab)
    if controls.menu_left_pressed() and controls_panel.focus_index ~= -1 then
        return_to_status()
        return
    end

    -- Handle scheme tab navigation
    if controls_panel.focus_index == -1 then
        if controls.menu_left_pressed() then
            controls_panel:cycle_scheme(-1)
            return
        elseif controls.menu_right_pressed() then
            controls_panel:cycle_scheme(1)
            return
        end
    end

    -- Let panel handle row navigation
    if controls.menu_up_pressed() or controls.menu_down_pressed() then
        mouse_active = false
    end
    controls_panel:input()

    -- If panel wrapped to -2 (settings tab header), wrap to reset button instead
    if controls_panel.focus_index == -2 then
        controls_panel.focus_index = #controls_panel.rows + 1
    end
end

--- Handle input when in confirmation dialog mode
local function handle_confirm_input()
    if controls.menu_back_pressed() then
        return_to_status()
        return
    end

    if controls.menu_left_pressed() or controls.menu_up_pressed() then
        mouse_active = false
        confirm_selection = 1
    elseif controls.menu_right_pressed() or controls.menu_down_pressed() then
        mouse_active = false
        confirm_selection = 2
    end

    if controls.menu_confirm_pressed() then
        if confirm_selection == 1 then
            rest_screen.hide()
            if return_to_title_callback then return_to_title_callback() end
        else
            return_to_status()
        end
    end
end

--- Handle input when in menu mode (navigating between menu items)
local function handle_menu_input()
    if controls.menu_up_pressed() then
        mouse_active = false
        focused_index = wrap_index(focused_index, -1, MENU_ITEM_COUNT)
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focused_index = wrap_index(focused_index, 1, MENU_ITEM_COUNT)
    end

    if controls.menu_right_pressed() then
        if focused_index == 2 and active_panel_index == 2 then
            nav_mode = NAV_MODE.SETTINGS
            audio_focus_index = 1
            return
        elseif focused_index == 3 and active_panel_index == 3 then
            nav_mode = NAV_MODE.SETTINGS
            controls_panel:reset_focus()
            return
        end
    end

    if controls.menu_confirm_pressed() then
        trigger_focused_action()
    end
end

--- Process keyboard and gamepad navigation input for the rest screen menu
function rest_screen.input()
    if state ~= STATE.OPEN then return end

    if nav_mode == NAV_MODE.CONFIRM then
        handle_confirm_input()
    elseif nav_mode == NAV_MODE.SETTINGS then
        if active_panel_index == 2 then
            handle_audio_settings_input()
        elseif active_panel_index == 3 then
            handle_controls_settings_input()
        end
    else
        handle_menu_input()
    end
end

--- Advance fade animations and handle state transitions
---@param dt number Delta time in seconds
---@param block_mouse boolean If true, skip mouse input processing (e.g., settings menu is open)
---@return nil
function rest_screen.update(dt, block_mouse)
    if state == STATE.HIDDEN then return end

    elapsed_time = elapsed_time + dt

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
        circle_lerp_t = math.min(circle_lerp_t + dt / CIRCLE_LERP_DURATION, 1)
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.RELOADING
            settings_storage.save_all(
                {
                    master = volume_sliders.master:get_value(),
                    music = volume_sliders.music:get_value(),
                    sfx = volume_sliders.sfx:get_value(),
                },
                controls.get_all_bindings("keyboard"),
                controls.get_all_bindings("gamepad")
            )
        end
        circle_lerp_t = math.max(circle_lerp_t - dt / CIRCLE_LERP_DURATION, 0)
    elseif state == STATE.RELOADING then
        fade_progress = fade_progress + dt / RELOAD_PAUSE
        if fade_progress >= 1 then
            if continue_callback then
                continue_callback()
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

    if state == STATE.OPEN then
        local scale = config.ui.SCALE
        local layout = calculate_layout(scale)
        position_buttons(layout.menu.x, layout.menu.y, layout.menu.width, layout.menu.height)

        if not block_mouse then
            local mx = canvas.get_mouse_x()
            local my = canvas.get_mouse_y()
            if mx ~= last_mouse_x or my ~= last_mouse_y then
                mouse_active = true
                last_mouse_x = mx
                last_mouse_y = my
            end

            local local_mx = mx / scale
            local local_my = my / scale

            if mouse_active then
                hovered_index = nil
                for i, btn in ipairs(buttons) do
                    if local_mx >= btn.x and local_mx <= btn.x + btn.width and
                       local_my >= btn.y and local_my <= btn.y + btn.height then
                        hovered_index = i
                        if nav_mode == NAV_MODE.MENU then
                            focused_index = i
                        end
                        if canvas.is_mouse_pressed(0) then
                            focused_index = i
                            trigger_focused_action()
                        end
                        break
                    end
                end
            else
                hovered_index = nil
            end

            if nav_mode == NAV_MODE.CONFIRM and mouse_active then
                local info = layout.info
                local center_x = info.x + info.width / 2
                local center_y = info.y + info.height / 2

                canvas.set_font_family("menu_font")
                canvas.set_font_size(7)
                local yes_metrics = canvas.get_text_metrics("Yes")
                local sep_metrics = canvas.get_text_metrics("   /   ")
                local no_metrics = canvas.get_text_metrics("No")
                local total_width = yes_metrics.width + sep_metrics.width + no_metrics.width
                local start_x = center_x - total_width / 2
                local button_y = center_y + 10

                if local_mx >= start_x and local_mx <= start_x + yes_metrics.width and
                   local_my >= button_y - 6 and local_my <= button_y + 6 then
                    confirm_selection = 1
                    if canvas.is_mouse_pressed(0) then
                        rest_screen.hide()
                        if return_to_title_callback then return_to_title_callback() end
                    end
                end

                local no_x = start_x + yes_metrics.width + sep_metrics.width
                if local_mx >= no_x and local_mx <= no_x + no_metrics.width and
                   local_my >= button_y - 6 and local_my <= button_y + 6 then
                    confirm_selection = 2
                    if canvas.is_mouse_pressed(0) then
                        return_to_status()
                    end
                end
            end

            local info = layout.info
            if active_panel_index == 2 then
                local slider_width = 80
                local slider_x = info.x + (info.width - slider_width) / 2
                local slider_start_y = info.y + 20
                local slider_spacing = 22

                for i, s in ipairs({ volume_sliders.master, volume_sliders.music, volume_sliders.sfx }) do
                    local offset_y = slider_start_y + slider_spacing * (i - 1)
                    s.x = slider_x
                    s.y = offset_y
                    s:update(local_mx, local_my)
                end
            elseif active_panel_index == 3 then
                local panel_x = info.x + (info.width - controls_panel.width) / 2
                local panel_y = info.y + 8

                controls_panel:update(dt, local_mx - panel_x, local_my - panel_y, mouse_active and nav_mode == NAV_MODE.SETTINGS)
            end
        end
    end
end

--- Draw the audio settings panel (volume sliders)
---@param x number Panel X position
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
local function draw_audio_panel(x, y, width, height)
    simple_dialogue.draw({ x = x, y = y, width = width, height = height, text = "" })

    local slider_width = 80
    local slider_start_y = y + 20
    local slider_spacing = 22
    local slider_x = x + (width - slider_width) / 2
    local label_center_x = x + width / 2

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("bottom")

    local slider_labels = {
        { label = "Master Volume", slider = volume_sliders.master },
        { label = "Music",         slider = volume_sliders.music },
        { label = "SFX",           slider = volume_sliders.sfx },
    }

    local in_settings = nav_mode == NAV_MODE.SETTINGS and active_panel_index == 2

    for i, item in ipairs(slider_labels) do
        local offset_y = slider_start_y + slider_spacing * (i - 1)
        local is_focused = in_settings and audio_focus_index == i
        local label_color = is_focused and "#FFFF00" or nil

        local metrics = canvas.get_text_metrics(item.label)
        utils.draw_outlined_text(item.label, label_center_x - metrics.width / 2, offset_y + 1, label_color)

        item.slider.x = slider_x
        item.slider.y = offset_y
        item.slider:draw(is_focused)
    end
end

--- Draw the controls settings panel (keybind rows)
---@param x number Panel X position
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
local function draw_controls_panel(x, y, width, height)
    simple_dialogue.draw({ x = x, y = y, width = width, height = height, text = "" })

    local panel_x = x + (width - controls_panel.width) / 2
    local panel_y = y + 8

    canvas.save()
    canvas.translate(panel_x, panel_y)
    controls_panel:draw()
    canvas.restore()
end

--- Draw the confirmation dialog panel
---@param x number Panel X position
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
local function draw_confirm_panel(x, y, width, height)
    simple_dialogue.draw({ x = x, y = y, width = width, height = height, text = "" })

    local center_x = x + width / 2
    local center_y = y + height / 2

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")

    local question = "Quit and return to title?"
    local question_metrics = canvas.get_text_metrics(question)
    utils.draw_outlined_text(question, center_x - question_metrics.width / 2, center_y - 12)

    local yes_color = confirm_selection == 1 and "#FFFF00" or "#FFFFFF"
    local no_color = confirm_selection == 2 and "#FFFF00" or "#FFFFFF"

    local yes_metrics = canvas.get_text_metrics("Yes")
    local sep_metrics = canvas.get_text_metrics("   /   ")
    local no_metrics = canvas.get_text_metrics("No")
    local total_width = yes_metrics.width + sep_metrics.width + no_metrics.width

    local start_x = center_x - total_width / 2
    utils.draw_outlined_text("Yes", start_x, center_y + 10, yes_color)
    utils.draw_outlined_text("   /   ", start_x + yes_metrics.width, center_y + 10, "#888888")
    utils.draw_outlined_text("No", start_x + yes_metrics.width + sep_metrics.width, center_y + 10, no_color)
end

--- Draw the rest screen overlay including circular viewport, vignette, and menu UI
function rest_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local t = ease_out(circle_lerp_t)
    local screen_x = circle_start_x + (circle_target_x - circle_start_x) * t
    local screen_y = circle_start_y + (circle_target_y - circle_start_y) * t

    local pulse = math.sin(elapsed_time * PULSE_SPEED * math.pi * 2) * PULSE_AMOUNT
    local radius = CIRCLE_RADIUS * scale * (1 + pulse)

    local overlay_alpha = 0
    local content_alpha = 0
    local hole_radius = radius

    if state == STATE.FADING_IN then
        overlay_alpha = fade_progress
        content_alpha = fade_progress
    elseif state == STATE.OPEN then
        overlay_alpha = 1
        content_alpha = 1
    elseif state == STATE.FADING_OUT then
        overlay_alpha = 1 - fade_progress
        content_alpha = 1 - fade_progress
    end

    canvas.set_global_alpha(overlay_alpha)

    -- Create circular viewport using evenodd clip (fills area outside circle)
    if hole_radius > 1 then
        canvas.save()
        canvas.begin_path()
        canvas.rect(0, 0, screen_w, screen_h)
        canvas.arc(screen_x, screen_y, hole_radius, 0, math.pi * 2)
        canvas.clip("evenodd")
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)
        canvas.restore()

        -- Vignette gradient
        local gradient = canvas.create_radial_gradient(
            screen_x, screen_y, hole_radius * 0.5,
            screen_x, screen_y, hole_radius
        )
        gradient:add_color_stop(0, "rgba(0,0,0,0)")
        gradient:add_color_stop(0.7, "rgba(0,0,0,0.3)")
        gradient:add_color_stop(1, "rgba(0,0,0,0.7)")
        canvas.set_fill_style(gradient)
        canvas.begin_path()
        canvas.arc(screen_x, screen_y, hole_radius, 0, math.pi * 2)
        canvas.fill()

        -- Glow ring
        local glow_alpha = 0.4 + pulse * 0.2
        local glow_inner = hole_radius * 0.85
        local glow_outer = hole_radius * 1.2

        local glow_gradient = canvas.create_radial_gradient(
            screen_x, screen_y, glow_inner,
            screen_x, screen_y, glow_outer
        )
        glow_gradient:add_color_stop(0, "rgba(255,180,50,0)")
        glow_gradient:add_color_stop(0.4, string.format("rgba(255,150,40,%.2f)", glow_alpha * 0.5))
        glow_gradient:add_color_stop(1, "rgba(255,80,20,0)")

        canvas.set_fill_style(glow_gradient)
        canvas.begin_path()
        canvas.arc(screen_x, screen_y, glow_outer, 0, math.pi * 2)
        canvas.fill()
    else
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)
    end

    if content_alpha > 0 then
        canvas.set_global_alpha(content_alpha)

        canvas.save()
        canvas.scale(scale, scale)

        local layout = calculate_layout(scale)

        menu_dialogue.x = layout.menu.x
        menu_dialogue.y = layout.menu.y
        menu_dialogue.width = layout.menu.width
        menu_dialogue.height = layout.menu.height

        rest_dialogue.x = layout.rest.x
        rest_dialogue.y = layout.rest.y
        rest_dialogue.width = layout.rest.width

        position_buttons(layout.menu.x, layout.menu.y, layout.menu.width, layout.menu.height)
        simple_dialogue.draw(menu_dialogue)

        local info = layout.info
        if nav_mode == NAV_MODE.CONFIRM then
            draw_confirm_panel(info.x, info.y, info.width, info.height)
        elseif active_panel_index == 1 then
            player_info_dialogue.x = info.x
            player_info_dialogue.y = info.y
            player_info_dialogue.width = info.width
            player_info_dialogue.height = info.height
            player_info_dialogue.text = build_stats_text(player_ref)
            simple_dialogue.draw(player_info_dialogue)
        elseif active_panel_index == 2 then
            draw_audio_panel(info.x, info.y, info.width, info.height)
        elseif active_panel_index == 3 then
            draw_controls_panel(info.x, info.y, info.width, info.height)
        end

        simple_dialogue.draw(rest_dialogue)

        for i, btn in ipairs(buttons) do
            btn:draw(focused_index == i or hovered_index == i)
        end

        canvas.restore()
    end

    canvas.set_global_alpha(1)
end

return rest_screen
