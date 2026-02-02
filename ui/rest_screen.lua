--- Rest screen overlay with circular viewport effect around campfire
--- Shows player stats, audio settings, and controls while resting at a campfire.
--- Supports menu navigation, settings editing, and confirmation dialogs.
local canvas = require("canvas")
local controls = require("controls")
local controls_config = require("config/controls")
local button = require("ui/button")
local config = require("config")
local simple_dialogue = require("ui/simple_dialogue")
local slider = require("ui/slider")
local keybind_panel = require("ui/keybind_panel")
local status_panel = require("ui/status_panel")
local audio = require("audio")
local settings_storage = require("settings_storage")
local utils = require("ui/utils")
local sprites = require("sprites")
local SaveSlots = require("SaveSlots")

local rest_screen = {}

-- Mode constants (rest = campfire, pause = ESC/START during gameplay)
local MODE = { REST = "rest", PAUSE = "pause" }
local current_mode = nil

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
local FADE_OUT_DURATION = 0.5
local SLIDE_DURATION = 0.2
local SLIDE_OUT_DELAY = 0.2
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

-- Submenu arrow configuration
local ARROW_WIDTH = 4
local ARROW_HEIGHT = 6
local ARROW_INSET = 7  -- Inset from button right edge (accounts for text-only button centering)

-- Menu item descriptions (index 4 is set dynamically when mode changes)
local REST_CONTINUE_DESC = "Resting restores your hit points, energy, and saves your progress. Enemies also respawn when you rest."
local PAUSE_CONTINUE_DESC = "Resume gameplay."
local MENU_DESCRIPTIONS = {
    "View your current stats and progression. You can spend experience at campfires to increase your stats.",
    "Adjust master volume, music, and sound effects.",
    "View and customize keyboard and gamepad controls.",
    REST_CONTINUE_DESC,
    "Save and quit to the title screen.",
}

-- Level up icon configuration
local LEVEL_UP_ICON_SIZE = 10
local LEVEL_UP_ICON_INSET = 6  -- Inset from button left edge (accounts for text-only button centering)

-- Screen state
local state = STATE.HIDDEN
local fade_progress = 0
local slide_progress = 0
local fade_out_time = 0
local elapsed_time = 0
local nav_mode = NAV_MODE.MENU
local confirm_selection = 2

-- Navigation state
local focused_index = 1
local hovered_index = nil
local active_panel_index = 1
local audio_focus_index = 1
local upgrade_button_focus = nil  -- nil = stats focused, "confirm" or "cancel" for button focus

-- Hold-to-repeat state
local hold_direction = 0
local hold_time = 0

-- Campfire and camera state
local campfire_x = 0
local campfire_y = 0
local campfire_name = "Campfire"
local camera_ref = nil
local original_camera_x = 0
local original_camera_y = 0
local last_camera_x = 0
local last_camera_y = 0

-- Save state (set when rest screen opens)
local active_save_slot = nil
local current_level_id = nil

-- Circle lerp state (screen pixels)
local circle_start_x = 0
local circle_start_y = 0
local circle_target_x = 0
local circle_target_y = 0
local circle_lerp_t = 0

-- Callbacks
local continue_callback = nil
local return_to_title_callback = nil
local pause_continue_callback = nil

-- UI components (populated in init)
local status_button = nil
local audio_button = nil
local controls_button = nil
local continue_button = nil
local return_to_title_button = nil
local rest_dialogue = nil
local menu_dialogue = nil
local buttons = nil
local volume_sliders = {}
local controls_panel = nil
local player_status_panel = nil

---@type table|nil Player reference for stats display
local player_ref = nil

-- Track whether settings have been modified since last save
local settings_dirty = false

--- Mark settings as modified (called when sliders or keybinds change)
---@return nil
local function mark_settings_dirty()
    settings_dirty = true
end

--- Save current settings to local storage if modified
---@return nil
local function save_settings()
    if not settings_dirty then return end
    settings_storage.save_all(
        {
            master = volume_sliders.master:get_value(),
            music = volume_sliders.music:get_value(),
            sfx = volume_sliders.sfx:get_value(),
        },
        controls.get_all_bindings("keyboard"),
        controls.get_all_bindings("gamepad")
    )
    settings_dirty = false
end

--- Save player stats to the active save slot
---@return nil
local function save_player_stats()
    if not player_ref or not active_save_slot or not current_level_id then
        return
    end
    local save_data = SaveSlots.build_player_data(player_ref, current_level_id, campfire_name)
    SaveSlots.set(active_save_slot, save_data)
end

--- Return to menu mode showing the status panel
--- Saves settings when exiting Audio or Controls panels
---@return nil
local function return_to_status()
    if active_panel_index >= 2 then
        save_settings()
    end
    nav_mode = NAV_MODE.MENU
    active_panel_index = 1

    -- Ensure status panel is not in active navigation mode
    if player_status_panel then
        player_status_panel.active = false
    end

    -- Reset upgrade button focus
    upgrade_button_focus = nil

    -- Restore default rest dialogue text (already set in init_screen_state)
    rest_dialogue.text = MENU_DESCRIPTIONS[4]
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
    return ((index - 1 + delta) % max) + 1
end

-- Cached layout to avoid per-frame allocations
local cached_layout = {
    menu = { x = 0, y = 0, width = 0, height = 0 },
    info = { x = 0, y = 0, width = 0, height = 0 },
    rest = { x = 0, y = 0, width = 0, height = DIALOGUE_HEIGHT },
}
local cached_layout_scale = nil
local cached_layout_width = nil
local cached_layout_height = nil

-- Cached glow gradient colors to avoid per-frame string allocations
local glow_color_cache = {}

--- Get cached glow color string for gradient (quantized to 50 levels)
---@param alpha number Alpha value (0-1)
---@return string RGBA color string
local function get_glow_color(alpha)
    local key = math.floor(alpha * 50)
    if not glow_color_cache[key] then
        glow_color_cache[key] = string.format("rgba(255,150,40,%.2f)", key / 50)
    end
    return glow_color_cache[key]
end

--- Calculate layout dimensions for all UI panels (cached)
---@param scale number UI scale factor
---@return table Layout dimensions for menu, info panel, and rest dialogue
local function calculate_layout(scale)
    local width = canvas.get_width()
    local height = canvas.get_height()

    -- Return cached layout if inputs haven't changed
    if scale == cached_layout_scale and width == cached_layout_width and height == cached_layout_height then
        return cached_layout
    end

    -- Update cache keys
    cached_layout_scale = scale
    cached_layout_width = width
    cached_layout_height = height

    local screen_w = width / scale
    local screen_h = height / scale

    -- Layout around circle viewport (bottom-left)
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

    -- Update cached layout tables in place
    cached_layout.menu.x = menu_x
    cached_layout.menu.y = menu_y
    cached_layout.menu.width = menu_width
    cached_layout.menu.height = menu_height

    cached_layout.info.x = info_x
    cached_layout.info.y = info_y
    cached_layout.info.width = info_width
    cached_layout.info.height = info_height

    cached_layout.rest.x = info_x
    cached_layout.rest.y = rest_y
    cached_layout.rest.width = info_width

    return cached_layout
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

--- Convert linear slider value (0-1) to perceptual volume (0-1)
--- Human hearing is logarithmic, so we apply a power curve for even-sounding volume steps
---@param linear number Slider value (0-1)
---@return number Perceptual volume (0-1)
local function linear_to_perceptual(linear)
    return linear * linear
end

--- Create a volume slider input callback
---@param slider_key string Key in volume_sliders table
---@param set_volume_fn function Volume setter (receives 0-1 value)
---@param on_change_fn function|nil Optional callback after volume change (e.g., play sound check)
---@return function Input handler for slider
local function create_volume_callback(slider_key, set_volume_fn, on_change_fn)
    return function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders[slider_key]:set_value(event.normalized_x)
            local perceptual = linear_to_perceptual(volume_sliders[slider_key]:get_value())
            set_volume_fn(perceptual)
            if on_change_fn then on_change_fn() end
            mark_settings_dirty()
        end
    end
end

-- Volume slider configuration
local SLIDER_WIDTH = 80
local SLIDER_HEIGHT = 14
local SLIDER_LABELS = { "Master Volume", "Music", "SFX" }
local SLIDER_KEYS = { "master", "music", "sfx" }
local VOLUME_SETTERS = {
    canvas.set_master_volume,
    audio.set_music_volume,
    audio.set_sfx_volume,
}

--- Initialize rest screen components (creates menu buttons)
---@return nil
function rest_screen.init()
    status_button = create_menu_button("Status")
    audio_button = create_menu_button("Audio")
    controls_button = create_menu_button("Controls")
    continue_button = create_menu_button("Continue")
    return_to_title_button = create_menu_button("Return to Title")

    -- Create volume sliders
    volume_sliders.master = slider.create({
        x = 0, y = 0, width = SLIDER_WIDTH, height = SLIDER_HEIGHT,
        color = "#4488FF", value = 0.75, animate_speed = 0.1,
        on_input = create_volume_callback("master", canvas.set_master_volume)
    })

    volume_sliders.music = slider.create({
        x = 0, y = 0, width = SLIDER_WIDTH, height = SLIDER_HEIGHT,
        color = "#44FF88", value = 0.20, animate_speed = 0.1,
        on_input = create_volume_callback("music", audio.set_music_volume)
    })

    volume_sliders.sfx = slider.create({
        x = 0, y = 0, width = SLIDER_WIDTH, height = SLIDER_HEIGHT,
        color = "#FF8844", value = 0.6, animate_speed = 0.1,
        on_input = create_volume_callback("sfx", audio.set_sfx_volume, audio.play_sound_check)
    })

    -- Load saved volumes from storage
    local saved_volumes = settings_storage.load_volumes()
    volume_sliders.master:set_value(saved_volumes.master)
    volume_sliders.music:set_value(saved_volumes.music)
    volume_sliders.sfx:set_value(saved_volumes.sfx)

    -- Create keybind panel (two-column layout: 72px * 2 + 22px gap = 166px)
    controls_panel = keybind_panel.create({
        x = 0,
        y = 0,
        width = 166,
        height = 110,
        on_change = mark_settings_dirty,
    })

    rest_dialogue = simple_dialogue.create({
        x = 0,
        y = 0,
        width = 100,
        height = DIALOGUE_HEIGHT,
        text = ""
    })

    player_status_panel = status_panel.create({
        x = 0,
        y = 0,
        width = 100,
        height = 100,
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
    slide_progress = 0
    if player_status_panel then
        player_status_panel:cancel_upgrades()
    end
    return_to_status()
end

--- Trigger the fade out and continue sequence
---@return nil
function rest_screen.trigger_continue()
    -- Cancel any pending upgrades when leaving
    if player_status_panel then
        player_status_panel:cancel_upgrades()
    end
    state = STATE.FADING_OUT
    fade_progress = 0
    fade_out_time = 0
end

--- Save camera position every frame (called from main.lua before player:update)
--- This ensures we capture the camera position before anything can modify it
---@param x number Camera X position in tiles
---@param y number Camera Y position in tiles
function rest_screen.save_camera_position(x, y)
    last_camera_x = x
    last_camera_y = y
end

--- Reset navigation state to defaults (called when showing rest/pause screen)
---@return nil
local function reset_navigation_state()
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

--- Initialize circle lerp animation from a world position to bottom-left corner
---@param center_x number Circle center X in tile coordinates
---@param center_y number Circle center Y in tile coordinates
---@param camera table Camera instance for screen coordinate conversion
---@return nil
local function init_circle_lerp(center_x, center_y, camera)
    local scaled_radius = CIRCLE_RADIUS * config.ui.SCALE

    -- Starting position (screen coords)
    circle_start_x = (center_x - camera:get_x()) * sprites.tile_size
    circle_start_y = (center_y - camera:get_y()) * sprites.tile_size

    -- Target position: bottom-left with padding (circle center offset by radius)
    circle_target_x = CIRCLE_EDGE_PADDING + scaled_radius
    circle_target_y = canvas.get_height() - CIRCLE_EDGE_PADDING - scaled_radius

    circle_lerp_t = 0
end

--- Initialize component layout and player data for first frame
--- Called when screen opens to ensure correct positioning before first draw
---@return nil
local function init_component_layout()
    local layout = calculate_layout(config.ui.SCALE)
    local menu = layout.menu
    local info = layout.info

    menu_dialogue.x = menu.x
    menu_dialogue.y = menu.y
    menu_dialogue.width = menu.width
    menu_dialogue.height = menu.height

    rest_dialogue.x = layout.rest.x
    rest_dialogue.y = layout.rest.y
    rest_dialogue.width = layout.rest.width

    player_status_panel.x = info.x
    player_status_panel.y = info.y
    player_status_panel.width = info.width
    player_status_panel.height = info.height
    player_status_panel:set_player(player_ref)

    position_buttons(menu.x, menu.y, menu.width, menu.height)
end

--- Initialize common state for rest/pause screen opening
---@param mode string MODE.REST or MODE.PAUSE
---@param player table Player instance for stats display
---@param camera table Camera instance for position calculation
---@param description string Description text for the continue action
---@param button_label string Label for the continue button
---@return nil
local function init_screen_state(mode, player, camera, description, button_label)
    current_mode = mode
    player_ref = player
    camera_ref = camera
    state = STATE.FADING_IN
    fade_progress = 0
    slide_progress = 0
    elapsed_time = 0

    campfire_x = player.x + 0.5
    campfire_y = player.y + 0.5

    original_camera_x = last_camera_x
    original_camera_y = last_camera_y

    init_circle_lerp(campfire_x, campfire_y, camera)

    rest_dialogue.text = description
    continue_button.label = button_label
    MENU_DESCRIPTIONS[4] = description

    -- Initialize layout immediately for correct first-frame rendering
    init_component_layout()
end

--- Show the rest screen centered on a campfire
---@param world_x number Campfire center X in tile coordinates (unused, kept for API compatibility)
---@param world_y number Campfire center Y in tile coordinates (unused, kept for API compatibility)
---@param camera table Camera instance for position calculation
---@param player table|nil Player instance for stats display
---@param save_slot number|nil Active save slot index
---@param level_id string|nil Current level identifier
---@param fire_name string|nil Campfire display name
---@return nil
function rest_screen.show(world_x, world_y, camera, player, save_slot, level_id, fire_name)
    if state == STATE.HIDDEN then
        init_screen_state(MODE.REST, player, camera, REST_CONTINUE_DESC, "Rest & Continue")
        campfire_name = fire_name or "Campfire"
        active_save_slot = save_slot
        current_level_id = level_id
    end

    reset_navigation_state()
end

--- Show the pause screen (circular viewport around player, no save, no level reload)
---@param player table Player instance for stats display and position
---@param camera table Camera instance for position calculation
---@return nil
function rest_screen.show_pause(player, camera)
    if state == STATE.HIDDEN then
        init_screen_state(MODE.PAUSE, player, camera, PAUSE_CONTINUE_DESC, "Continue")
    end

    reset_navigation_state()
end

--- Set the continue callback function (reloads level from checkpoint)
---@param fn function Function to call when continuing
---@return nil
function rest_screen.set_continue_callback(fn)
    continue_callback = fn
end

--- Set the return to title callback function
---@param fn function Function to call when returning to title
---@return nil
function rest_screen.set_return_to_title_callback(fn)
    return_to_title_callback = fn
end

--- Set the pause continue callback function (just resumes gameplay, no reload)
---@param fn function Function to call when continuing from pause
---@return nil
function rest_screen.set_pause_continue_callback(fn)
    pause_continue_callback = fn
end

--- Check if currently in pause mode (vs rest mode)
---@return boolean is_pause_mode True if screen is active and in pause mode
function rest_screen.is_pause_mode()
    return state ~= STATE.HIDDEN and current_mode == MODE.PAUSE
end

--- Check if rest screen is blocking game input
---@return boolean is_active True if rest screen is visible or animating
function rest_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Get the HUD slide offset (for sliding HUD off screen)
--- Returns 0.0 when hidden, increases to 1.0 as rest screen opens
---@return number offset Slide progress (0.0 = on screen, 1.0 = off screen)
function rest_screen.get_hud_slide()
    return slide_progress
end

--- Check if rest screen is in a submenu (settings or confirm dialog)
---@return boolean is_submenu True if in a submenu that should handle back separately
function rest_screen.is_in_submenu()
    return state == STATE.OPEN and (nav_mode == NAV_MODE.SETTINGS or nav_mode == NAV_MODE.CONFIRM)
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

--- Get the current camera offset to keep target centered in circle
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
        return_to_status()
    elseif focused_index == 2 or focused_index == 3 then
        nav_mode = NAV_MODE.SETTINGS
        active_panel_index = focused_index
        if focused_index == 2 then
            audio_focus_index = 1
        else
            controls_panel:reset_focus()
        end
    elseif focused_index == 4 then
        rest_screen.trigger_continue()
    elseif focused_index == 5 then
        nav_mode = NAV_MODE.CONFIRM
        confirm_selection = 2
    end
end

--- Get the slider at the given focus index, or nil if index is out of range
---@param index number Focus index (1-3)
---@return table|nil slider
local function get_focused_slider(index)
    return volume_sliders[SLIDER_KEYS[index]]
end

--- Get the volume setter function for a given focus index
---@param index number Focus index (1-3)
---@return function|nil setter
local function get_volume_setter(index)
    return VOLUME_SETTERS[index]
end

--- Handle input when in Audio settings mode
---@return nil
local function handle_audio_settings_input()
    if controls.menu_back_pressed() then
        return_to_status()
        hold_direction = 0
        hold_time = 0
        return
    end

    if controls.menu_up_pressed() then
        audio_focus_index = wrap_index(audio_focus_index, -1, 3)
    elseif controls.menu_down_pressed() then
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

        -- Determine current direction (-1 left, 0 none, 1 right)
        local current_dir = 0
        if left_down then
            current_dir = -1
        elseif right_down then
            current_dir = 1
        end

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
                setter(linear_to_perceptual(focused_slider:get_value()))
            end
            if audio_focus_index == 3 then audio.play_sound_check() end
            mark_settings_dirty()
        end
    else
        hold_direction = 0
        hold_time = 0
    end
end

--- Handle input when in Status panel navigation mode
---@return nil
local function handle_status_settings_input()
    -- Check if inventory is focused - delegate navigation to status panel
    if player_status_panel:is_inventory_focused() then
        -- Back exits inventory focus, returns to stats
        if controls.menu_back_pressed() then
            player_status_panel:focus_stats()
            return
        end

        -- Let status panel handle inventory navigation
        player_status_panel:input()
        return
    end

    local has_pending = player_status_panel:has_pending_upgrades()

    -- Handle back/cancel button
    if controls.menu_back_pressed() then
        if upgrade_button_focus == "cancel" then
            -- On Cancel button: cancel all and exit
            player_status_panel:cancel_upgrades()
            return_to_status()
            return
        elseif upgrade_button_focus == "confirm" then
            -- On Confirm button: move to Cancel button
            upgrade_button_focus = "cancel"
            return
        elseif has_pending then
            -- Try to remove upgrade from highlighted stat
            local stat = player_status_panel:get_highlighted_stat()
            local pending_on_stat = stat and player_status_panel:get_pending_count(stat) or 0
            if pending_on_stat > 0 then
                player_status_panel:remove_pending_upgrade()
            else
                -- No pending on this stat, jump to Cancel button
                upgrade_button_focus = "cancel"
            end
            return
        else
            -- No pending upgrades, exit
            return_to_status()
            return
        end
    end

    -- Confirm button behavior
    if controls.menu_confirm_pressed() then
        if upgrade_button_focus == "confirm" then
            -- Confirm all upgrades and save
            player_status_panel:confirm_upgrades()
            save_player_stats()
            upgrade_button_focus = nil
            return
        elseif upgrade_button_focus == "cancel" then
            -- Cancel all upgrades and exit
            player_status_panel:cancel_upgrades()
            return_to_status()
            return
        elseif current_mode == MODE.REST and player_status_panel:is_highlighted_levelable() then
            player_status_panel:add_pending_upgrade()
            return
        end
    end

    -- Navigation
    if controls.menu_up_pressed() or controls.menu_down_pressed() then
        if upgrade_button_focus then
            -- Up from buttons goes back to stats (bottom row)
            if controls.menu_up_pressed() then
                upgrade_button_focus = nil
                player_status_panel.selected_index = #player_status_panel.selectable_rows
            end
            -- Down from buttons does nothing (already at bottom)
        else
            -- Navigate stats, but check if we should move to buttons
            local old_index = player_status_panel.selected_index
            player_status_panel:input()

            -- If pressing down at the bottom of stats and there are pending upgrades, go to buttons
            if controls.menu_down_pressed() and has_pending and
               old_index == #player_status_panel.selectable_rows and
               player_status_panel.selected_index == 1 then
                -- Wrapped around, go to Confirm button instead
                player_status_panel.selected_index = old_index
                upgrade_button_focus = "confirm"
            end
        end
        return
    end

    -- Left/Right navigation
    if controls.menu_left_pressed() or controls.menu_right_pressed() then
        if upgrade_button_focus then
            -- Left/Right switches between Confirm and Cancel
            if controls.menu_left_pressed() then
                upgrade_button_focus = "confirm"
            elseif controls.menu_right_pressed() then
                upgrade_button_focus = "cancel"
            end
        else
            -- Right goes to inventory
            if controls.menu_right_pressed() then
                player_status_panel:input()
            end
            -- Left exits when no pending upgrades
            if controls.menu_left_pressed() and not has_pending then
                return_to_status()
            end
        end
        return
    end
end

--- Handle input when in Controls settings mode
---@return nil
local function handle_controls_settings_input()
    if controls_panel:is_listening() then
        return
    end

    if controls.menu_back_pressed() then
        return_to_status()
        return
    end

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
    controls_panel:input()

    -- If panel wrapped to -2 (settings tab header), wrap to reset button instead
    if controls_panel.focus_index == -2 then
        controls_panel.focus_index = #controls_panel.rows + 1
    end
end

--- Handle input when in confirmation dialog mode
---@return nil
local function handle_confirm_input()
    if controls.menu_back_pressed() then
        return_to_status()
        return
    end

    if controls.menu_left_pressed() or controls.menu_up_pressed() then
        confirm_selection = 1
    elseif controls.menu_right_pressed() or controls.menu_down_pressed() then
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

-- Upgrade confirmation button state (hover only, focus is in Navigation state)
local upgrade_confirm_hovered = false
local upgrade_cancel_hovered = false

--- Draw the upgrade confirm/cancel buttons below the stats area
--- Only visible in REST mode when there are pending upgrades
---@param info table Layout info with x, y, width, height
---@param local_mx number Local mouse X coordinate
---@param local_my number Local mouse Y coordinate
---@return nil
local function draw_upgrade_buttons(info, local_mx, local_my)
    local mouse_active = controls.is_mouse_active()
    -- Only show upgrade buttons in REST mode with pending upgrades
    if current_mode ~= MODE.REST or not player_status_panel:has_pending_upgrades() then
        upgrade_confirm_hovered = false
        upgrade_cancel_hovered = false
        upgrade_button_focus = nil
        return
    end

    canvas.save()

    -- Position below stats area (left side of panel)
    local stats_layout = player_status_panel:get_stats_layout()
    local button_y = info.y + stats_layout.bottom + 6
    local button_x = info.x + stats_layout.x
    local button_spacing = 12

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("top")

    local confirm_text = "Spend XP"
    local cancel_text = "Cancel"
    local confirm_metrics = canvas.get_text_metrics(confirm_text)
    local cancel_metrics = canvas.get_text_metrics(cancel_text)

    local confirm_x = button_x
    local cancel_x = confirm_x + confirm_metrics.width + button_spacing

    -- Check hover state (mouse)
    upgrade_confirm_hovered = false
    upgrade_cancel_hovered = false

    if mouse_active then
        local btn_height = 10

        if local_my >= button_y and local_my <= button_y + btn_height then
            if local_mx >= confirm_x and local_mx <= confirm_x + confirm_metrics.width then
                upgrade_confirm_hovered = true
                upgrade_button_focus = "confirm"  -- Sync mouse hover with focus
            elseif local_mx >= cancel_x and local_mx <= cancel_x + cancel_metrics.width then
                upgrade_cancel_hovered = true
                upgrade_button_focus = "cancel"  -- Sync mouse hover with focus
            end
        end
    end

    -- Determine highlight based on focus or hover
    local confirm_focused = upgrade_button_focus == "confirm" or upgrade_confirm_hovered
    local cancel_focused = upgrade_button_focus == "cancel" or upgrade_cancel_hovered

    -- Draw confirm button
    local confirm_color = confirm_focused and "#88FF88" or "#FFFFFF"
    canvas.set_color(confirm_color)
    canvas.set_text_align("left")
    canvas.draw_text(confirm_x, button_y, confirm_text)

    -- Draw cancel button
    local cancel_color = cancel_focused and "#FF8888" or "#AAAAAA"
    canvas.set_color(cancel_color)
    canvas.draw_text(cancel_x, button_y, cancel_text)

    canvas.restore()
end

--- Handle upgrade button clicks
---@return boolean handled True if a button was clicked
local function handle_upgrade_button_clicks()
    if not player_status_panel:has_pending_upgrades() then
        return false
    end

    if canvas.is_mouse_pressed(0) then
        if upgrade_confirm_hovered then
            player_status_panel:confirm_upgrades()
            save_player_stats()
            return true
        elseif upgrade_cancel_hovered then
            player_status_panel:cancel_upgrades()
            return true
        end
    end

    return false
end

--- Enter settings mode for the currently focused submenu panel
---@return nil
local function enter_settings_mode()
    nav_mode = NAV_MODE.SETTINGS
    if focused_index == 1 then
        player_status_panel.active = true
        player_status_panel:reset_selection()
    elseif focused_index == 2 then
        audio_focus_index = 1
    else
        controls_panel:reset_focus()
    end
end

--- Handle input when in menu mode (navigating between menu items)
---@return nil
local function handle_menu_input()
    -- ESC/Start triggers continue when not in a submenu
    if controls.menu_back_pressed() or controls.settings_pressed() then
        rest_screen.trigger_continue()
        return
    end

    if controls.menu_up_pressed() then
        focused_index = wrap_index(focused_index, -1, MENU_ITEM_COUNT)
    elseif controls.menu_down_pressed() then
        focused_index = wrap_index(focused_index, 1, MENU_ITEM_COUNT)
    end

    local right_pressed = controls.menu_right_pressed()
    local confirm_pressed = controls.menu_confirm_pressed()
    local is_submenu_item = focused_index <= 3

    -- Enter settings mode when pressing right/confirm on the active submenu panel
    if (right_pressed or confirm_pressed) and is_submenu_item and focused_index == active_panel_index then
        enter_settings_mode()
        return
    end

    -- Right arrow on submenu items switches to that panel
    if right_pressed and is_submenu_item then
        trigger_focused_action()
        return
    end

    -- Confirm triggers the focused action (submenu switch, continue, or return to title)
    if confirm_pressed then
        trigger_focused_action()
    end
end

--- Process keyboard and gamepad navigation input for the rest screen menu
---@return nil
function rest_screen.input()
    if state ~= STATE.OPEN then return end

    -- Block all input when controls panel is listening for or just captured a keybind
    if controls_panel and controls_panel:is_capturing_input() then
        return
    end

    if nav_mode == NAV_MODE.CONFIRM then
        handle_confirm_input()
    elseif nav_mode == NAV_MODE.SETTINGS then
        if active_panel_index == 1 then
            handle_status_settings_input()
        elseif active_panel_index == 2 then
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
        -- Animate slide (faster than fade)
        slide_progress = math.min(slide_progress + dt / SLIDE_DURATION, 1)
        -- Animate circle lerp for both modes
        circle_lerp_t = math.min(circle_lerp_t + dt / CIRCLE_LERP_DURATION, 1)
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        fade_out_time = fade_out_time + dt
        if fade_progress >= 1 then
            save_settings()
            fade_progress = 0
            slide_progress = 0
            fade_out_time = 0
            if current_mode == MODE.PAUSE then
                -- Pause mode: skip reload, just hide
                state = STATE.HIDDEN
                if pause_continue_callback then pause_continue_callback() end
            else
                -- Rest mode: proceed to reload sequence
                state = STATE.RELOADING
            end
        end
        -- Animate slide after delay
        if fade_out_time >= SLIDE_OUT_DELAY then
            slide_progress = math.max(slide_progress - dt / SLIDE_DURATION, 0)
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

        local is_capturing = controls_panel and controls_panel:is_capturing_input()

        if not block_mouse then
            local mouse_active = controls.is_mouse_active()
            local mx = canvas.get_mouse_x()
            local my = canvas.get_mouse_y()

            local local_mx = mx / scale
            local local_my = my / scale

            -- Block menu/confirm interactions when controls panel is capturing input
            if not is_capturing then
                hovered_index = nil
                if mouse_active then
                    for i, btn in ipairs(buttons) do
                        if local_mx >= btn.x and local_mx <= btn.x + btn.width and
                           local_my >= btn.y and local_my <= btn.y + btn.height then
                            hovered_index = i
                            -- Set focus on hover (menu mode) or click (any mode)
                            if nav_mode == NAV_MODE.MENU or canvas.is_mouse_pressed(0) then
                                focused_index = i
                            end
                            if canvas.is_mouse_pressed(0) then
                                trigger_focused_action()
                            end
                            break
                        end
                    end
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
            end

            -- Panels always receive updates
            local info = layout.info
            if active_panel_index == 1 then
                player_status_panel.x = info.x
                player_status_panel.y = info.y
                player_status_panel.width = info.width
                player_status_panel.height = info.height
                player_status_panel:set_player(player_ref)
                player_status_panel:update(dt, local_mx - info.x, local_my - info.y, mouse_active)

                -- Handle mouse clicks for stat upgrades (only in rest mode at campfires)
                if current_mode == MODE.REST and mouse_active then
                    -- First check if clicking confirm/cancel buttons
                    if not handle_upgrade_button_clicks() then
                        if canvas.is_mouse_pressed(0) then  -- Left click to add upgrade
                            if player_status_panel:is_highlighted_levelable() then
                                player_status_panel:add_pending_upgrade()
                            end
                        elseif canvas.is_mouse_pressed(2) then  -- Right click to remove upgrade
                            player_status_panel:remove_pending_upgrade()
                        end
                    end
                end

                -- Handle mouse clicks for inventory (toggle equipped)
                if mouse_active and canvas.is_mouse_pressed(0) then
                    player_status_panel:toggle_hovered_equipped()
                end

                -- Update rest dialogue with stat description when hovering or navigating
                local description = player_status_panel:get_description()
                if description then
                    rest_dialogue.text = description
                end
            elseif active_panel_index == 2 then
                local slider_x = info.x + (info.width - SLIDER_WIDTH) / 2
                local slider_start_y = info.y + 20
                local slider_spacing = 22

                for i, key in ipairs(SLIDER_KEYS) do
                    local s = volume_sliders[key]
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

        -- Update rest dialogue based on context
        if nav_mode == NAV_MODE.MENU then
            -- Check if status panel has a hovered stat
            local stat_desc = player_status_panel:get_description()
            if stat_desc then
                rest_dialogue.text = stat_desc
            elseif MENU_DESCRIPTIONS[hovered_index or focused_index] then
                rest_dialogue.text = MENU_DESCRIPTIONS[hovered_index or focused_index]
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

    local slider_start_y = y + 20
    local slider_spacing = 22
    local label_center_x = x + width / 2

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("bottom")

    local in_settings = nav_mode == NAV_MODE.SETTINGS and active_panel_index == 2

    for i, label in ipairs(SLIDER_LABELS) do
        local offset_y = slider_start_y + slider_spacing * (i - 1)
        local is_focused = in_settings and audio_focus_index == i
        local label_color = is_focused and "#FFFF00" or nil

        local metrics = canvas.get_text_metrics(label)
        utils.draw_outlined_text(label, label_center_x - metrics.width / 2, offset_y + 1, label_color)

        -- Slider positions are set in update(), just draw here
        volume_sliders[SLIDER_KEYS[i]]:draw(is_focused)
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

-- Icon scales for prompt icons
local PROMPT_KEY_SCALE = 0.125       -- 64 * 0.125 = 8px for keyboard
local PROMPT_BUTTON_SCALE = 0.5     -- 16 * 0.5 = 8px for gamepad
local PROMPT_ICON_SIZE = 8
local PROMPT_PADDING = 6
local PROMPT_ICON_SPACING = 4

--- Draw an input icon (mouse, keyboard, or gamepad) at the given position
---@param x number Icon X position
---@param y number Icon Y position
---@param use_mouse boolean Whether to show mouse icon instead of keyboard/gamepad
---@return nil
local function draw_input_icon(x, y, use_mouse)
    local mode = use_mouse and "mouse" or controls.get_last_input_device()

    if mode == "mouse" then
        sprites.controls.draw_key(controls_config.MOUSE_LEFT, x, y, PROMPT_KEY_SCALE)
    elseif mode == "gamepad" then
        sprites.controls.draw_button(canvas.buttons.SOUTH, x, y, PROMPT_BUTTON_SCALE)
    else
        sprites.controls.draw_key(canvas.keys.SPACE, x, y, PROMPT_KEY_SCALE)
    end
end

--- Check if the level-up prompt should be visible
--- Only true in REST mode on Status panel when a levelable stat is highlighted
---@return boolean
local function is_level_up_prompt_visible()
    if active_panel_index ~= 1 or current_mode ~= MODE.REST then
        return false
    end

    -- Don't show if inventory has mouse hover or keyboard focus (without stats mouse hover)
    local inventory_has_hover = player_status_panel.inventory.hovered_col ~= nil
    local inventory_has_focus = player_status_panel.focus_area == "inventory" and
                                player_status_panel.hovered_index == nil
    if inventory_has_hover or inventory_has_focus then
        return false
    end

    return player_status_panel:is_highlighted_levelable()
end

--- Draw the level-up prompt in the bottom right of the rest dialogue
---@param dialogue table The rest dialogue with x, y, width, height
---@return nil
local function draw_level_up_prompt(dialogue)
    if not is_level_up_prompt_visible() then
        return
    end

    local cost = player_status_panel:get_level_cost()
    if not cost then return end

    local stat = player_status_panel:get_highlighted_stat()
    local can_afford = player_status_panel:can_afford_upgrade(stat)

    local text
    if can_afford then
        text = "Spend " .. cost .. " XP to increase"
    else
        text = "Not enough XP (" .. cost .. " required)"
    end
    local text_color = can_afford and "#FFFFFF" or "#888888"

    canvas.save()

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")
    canvas.set_text_align("right")

    local text_x = dialogue.x + dialogue.width - PROMPT_PADDING
    local text_y = dialogue.y + dialogue.height - PROMPT_PADDING - 4

    canvas.set_color(text_color)
    canvas.draw_text(text_x, text_y, text)

    if can_afford then
        local text_metrics = canvas.get_text_metrics(text)
        local icon_x = text_x - text_metrics.width - PROMPT_ICON_SPACING - PROMPT_ICON_SIZE
        local icon_y = text_y - PROMPT_ICON_SIZE / 2
        draw_input_icon(icon_x, icon_y, player_status_panel:is_mouse_hover())
    end

    canvas.restore()
end

--- Check if the inventory equip prompt should be visible
--- Only true when inventory has a hovered/selected item AND level-up prompt is not visible
---@return boolean
local function is_inventory_prompt_visible()
    -- Only on status panel, and mutually exclusive with level-up prompt
    if active_panel_index ~= 1 or is_level_up_prompt_visible() then
        return false
    end

    -- Don't show if stats has mouse hover or keyboard focus (without inventory mouse hover)
    local stats_has_hover = player_status_panel.hovered_index ~= nil
    local stats_has_focus = player_status_panel.focus_area == "stats" and
                            player_status_panel.active and
                            player_status_panel.inventory.hovered_col == nil
    if stats_has_hover or stats_has_focus then
        return false
    end

    return player_status_panel:is_hovered_item_equipped() ~= nil
end

--- Draw the submenu entry prompt in the bottom right of the info panel
---@param dialogue table The rest dialogue with x, y, width, height
---@return nil
local function draw_submenu_prompt(dialogue)
    -- Only show in menu mode for submenu items (Status, Audio, Controls)
    if nav_mode ~= NAV_MODE.MENU or focused_index < 1 or focused_index > 3 then
        return
    end

    -- Mutual exclusion: never show if level-up or inventory prompts are visible
    if is_level_up_prompt_visible() or is_inventory_prompt_visible() then
        return
    end

    local mouse_on_submenu = hovered_index and hovered_index >= 1 and hovered_index <= 3

    -- Don't show if mouse is hovering over status panel stats
    if not mouse_on_submenu and player_status_panel:is_mouse_hover() then
        return
    end

    local text = "Enter"

    canvas.save()

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")
    canvas.set_text_align("right")

    local text_metrics = canvas.get_text_metrics(text)
    local text_x = dialogue.x + dialogue.width - PROMPT_PADDING
    local text_y = dialogue.y + dialogue.height - PROMPT_PADDING - 4

    canvas.set_color("#FFFFFF")
    canvas.draw_text(text_x, text_y, text)

    local icon_x = text_x - text_metrics.width - PROMPT_ICON_SPACING - PROMPT_ICON_SIZE
    local icon_y = text_y - PROMPT_ICON_SIZE / 2
    draw_input_icon(icon_x, icon_y, mouse_on_submenu)

    canvas.restore()
end

--- Draw the inventory equip/unequip prompt in the bottom right of the rest dialogue
---@param dialogue table The rest dialogue with x, y, width, height
---@return nil
local function draw_inventory_equip_prompt(dialogue)
    if not is_inventory_prompt_visible() then
        return
    end

    local is_equipped = player_status_panel:is_hovered_item_equipped()
    local text = is_equipped and "Unequip" or "Equip"

    canvas.save()

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")
    canvas.set_text_align("right")

    local text_metrics = canvas.get_text_metrics(text)
    local text_x = dialogue.x + dialogue.width - PROMPT_PADDING
    local text_y = dialogue.y + dialogue.height - PROMPT_PADDING - 4

    canvas.set_color("#FFFFFF")
    canvas.draw_text(text_x, text_y, text)

    local icon_x = text_x - text_metrics.width - PROMPT_ICON_SPACING - PROMPT_ICON_SIZE
    local icon_y = text_y - PROMPT_ICON_SIZE / 2

    -- Use mouse icon if inventory has mouse hover
    local use_mouse = player_status_panel.inventory.hovered_col ~= nil
    draw_input_icon(icon_x, icon_y, use_mouse)

    canvas.restore()
end

--- Draw a right-pointing arrow triangle for submenu items
---@param x number Arrow tip X position
---@param y number Arrow center Y position
---@param focused boolean Whether the menu item is focused/hovered
---@return nil
local function draw_submenu_arrow(x, y, focused)
    local color = focused and "#FFFF00" or "#FFFFFF"
    canvas.set_color(color)

    canvas.begin_path()
    canvas.move_to(x, y)  -- Tip (right point)
    canvas.line_to(x - ARROW_WIDTH, y - ARROW_HEIGHT / 2)  -- Top left
    canvas.line_to(x - ARROW_WIDTH, y + ARROW_HEIGHT / 2)  -- Bottom left
    canvas.close_path()
    canvas.fill()
end

--- Draw circular viewport mask (fills area outside the circle with black)
---@param x number Circle center X in screen pixels
---@param y number Circle center Y in screen pixels
---@param radius number Circle radius in pixels
---@param screen_w number Screen width
---@param screen_h number Screen height
---@return nil
local function draw_circular_viewport(x, y, radius, screen_w, screen_h)
    if radius > 1 then
        canvas.save()
        canvas.begin_path()
        canvas.rect(0, 0, screen_w, screen_h)
        canvas.arc(x, y, radius, 0, math.pi * 2)
        canvas.clip("evenodd")
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)
        canvas.restore()
    else
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)
    end
end

--- Draw campfire glow effects (vignette and glow ring)
---@param x number Circle center X in screen pixels
---@param y number Circle center Y in screen pixels
---@param radius number Circle radius in pixels
---@param pulse number Pulse amount for animation
---@return nil
local function draw_campfire_glow(x, y, radius, pulse)
    -- Vignette gradient
    local gradient = canvas.create_radial_gradient(x, y, radius * 0.5, x, y, radius)
    gradient:add_color_stop(0, "rgba(255, 106, 0, 0.1)")
    gradient:add_color_stop(0.7, "rgba(255, 106, 0, 0.3)")
    gradient:add_color_stop(0.7, "rgba(255, 106, 0, 0.3)")
    gradient:add_color_stop(1, "rgba(0,0,0,0.7)")
    canvas.set_fill_style(gradient)
    canvas.begin_path()
    canvas.arc(x, y, radius, 0, math.pi * 2)
    canvas.fill()

    -- Glow ring
    local glow_alpha = 0.4 + pulse * 0.2
    local glow_inner = radius * 0.85
    local glow_outer = radius * 1.2

    local glow_gradient = canvas.create_radial_gradient(x, y, glow_inner, x, y, glow_outer)
    glow_gradient:add_color_stop(0, "rgba(255,180,50,0)")
    glow_gradient:add_color_stop(0.4, get_glow_color(glow_alpha * 0.5))
    glow_gradient:add_color_stop(1, "rgba(255,80,20,0)")

    canvas.set_fill_style(glow_gradient)
    canvas.begin_path()
    canvas.arc(x, y, glow_outer, 0, math.pi * 2)
    canvas.fill()
end

--- Draw the rest screen overlay including circular viewport, vignette, and menu UI
---@return nil
function rest_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local alpha = 0
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.OPEN then
        alpha = 1
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    canvas.set_global_alpha(alpha)

    -- Calculate circle position
    local t = ease_out(circle_lerp_t)
    local screen_x = circle_start_x + (circle_target_x - circle_start_x) * t
    local screen_y = circle_start_y + (circle_target_y - circle_start_y) * t
    local hole_radius = CIRCLE_RADIUS * scale

    -- Rest mode adds pulse and glow effects to the circular viewport
    local pulse = 0
    if current_mode == MODE.REST then
        pulse = math.sin(elapsed_time * PULSE_SPEED * math.pi * 2) * PULSE_AMOUNT
        hole_radius = hole_radius * (1 + pulse)
    end

    draw_circular_viewport(screen_x, screen_y, hole_radius, screen_w, screen_h)

    if current_mode == MODE.REST and hole_radius > 1 then
        draw_campfire_glow(screen_x, screen_y, hole_radius, pulse)
    end

    if alpha > 0 then
        canvas.save()
        canvas.scale(scale, scale)

        local layout = calculate_layout(scale)
        local menu = layout.menu

        menu_dialogue.x = menu.x
        menu_dialogue.y = menu.y
        menu_dialogue.width = menu.width
        menu_dialogue.height = menu.height

        rest_dialogue.x = layout.rest.x
        rest_dialogue.y = layout.rest.y
        rest_dialogue.width = layout.rest.width

        position_buttons(menu.x, menu.y, menu.width, menu.height)
        simple_dialogue.draw(menu_dialogue)

        local info = layout.info
        if nav_mode == NAV_MODE.CONFIRM then
            draw_confirm_panel(info.x, info.y, info.width, info.height)
        elseif active_panel_index == 1 then
            player_status_panel:draw()

            -- Draw confirm/cancel buttons if there are pending upgrades (scaled mouse coordinates)
            local local_mx = canvas.get_mouse_x() / scale
            local local_my = canvas.get_mouse_y() / scale
            draw_upgrade_buttons(info, local_mx, local_my)
        elseif active_panel_index == 2 then
            draw_audio_panel(info.x, info.y, info.width, info.height)
        elseif active_panel_index == 3 then
            draw_controls_panel(info.x, info.y, info.width, info.height)
        end

        simple_dialogue.draw(rest_dialogue)
        draw_level_up_prompt(rest_dialogue)
        draw_submenu_prompt(rest_dialogue)
        draw_inventory_equip_prompt(rest_dialogue)

        for i, btn in ipairs(buttons) do
            local is_focused = focused_index == i or hovered_index == i
            btn:draw(is_focused)

            -- Draw level up icon to the left of Status button when player can level up (rest mode only)
            if i == 1 and current_mode == MODE.REST and player_status_panel:can_level_up() then
                local icon_x = btn.x + LEVEL_UP_ICON_INSET
                local icon_y = btn.y + (btn.height - LEVEL_UP_ICON_SIZE) / 2
                canvas.draw_image(sprites.ui.level_up_icon, icon_x, icon_y, LEVEL_UP_ICON_SIZE, LEVEL_UP_ICON_SIZE)
            end

            -- Draw arrow for submenu items (Status, Audio, Controls)
            if i <= 3 then
                local arrow_x = btn.x + btn.width - ARROW_INSET
                local arrow_y = btn.y + btn.height / 2
                draw_submenu_arrow(arrow_x, arrow_y, is_focused)
            end
        end

        canvas.restore()
    end

    canvas.set_global_alpha(1)
end

return rest_screen
