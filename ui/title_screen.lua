--- Title screen overlay with menu navigation and animated cursor
local canvas = require("canvas")
local controls = require("controls")
local config = require("config")
local Animation = require("Animation")
local sprites = require("sprites")

local title_screen = {}

-- State machine
local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
}

-- Timing configuration (seconds)
local FADE_DURATION = 0.25

-- Menu items
local MENU_ITEMS = {
    { id = "play_game", label = "Play Game" },
    { id = "audio", label = "Audio" },
    { id = "controls", label = "Controls" },
    { id = "settings", label = "Settings" },
    { id = "credits", label = "Credits" },
}

local state = STATE.HIDDEN
local fade_progress = 0
local focused_index = 1  -- Default to "Play Game" (index 1)
local blink_time = 0

-- Cursor animation (player idle sprite)
local cursor_animation = nil

-- Menu action callbacks (set by main.lua to handle game state transitions)
local play_game_callback = nil
local audio_callback = nil
local controls_callback = nil
local settings_callback = nil
local credits_callback = nil

-- Mouse input tracking
local mouse_active = false
local last_mouse_x = 0
local last_mouse_y = 0

-- Layout constants (at 1x scale, screen 384x216)
local TITLE_Y = 50
local MENU_START_Y = 100
local MENU_ITEM_SPACING = 16
local CURSOR_OFFSET_X = 20  -- Distance from menu item to cursor

-- Cached menu item positions (calculated once per draw)
local menu_item_positions = {}

--- Initialize title screen components (cursor animation)
--- Must be called once before showing the title screen
---@return nil
function title_screen.init()
    -- Create cursor animation using player idle sprite
    local idle_def = Animation.create_definition(sprites.player.idle, 6, {
        ms_per_frame = 240,
        width = 16,
        height = 16,
        loop = true
    })
    cursor_animation = Animation.new(idle_def, { flipped = 1 })
end

--- Set the play game callback function
---@param fn function Function to call when Play Game is selected
function title_screen.set_play_game_callback(fn)
    play_game_callback = fn
end

--- Set the audio callback function
---@param fn function Function to call when Audio is selected
function title_screen.set_audio_callback(fn)
    audio_callback = fn
end

--- Set the controls callback function
---@param fn function Function to call when Controls is selected
function title_screen.set_controls_callback(fn)
    controls_callback = fn
end

--- Set the settings callback function
---@param fn function Function to call when Settings is selected
function title_screen.set_settings_callback(fn)
    settings_callback = fn
end

--- Set the credits callback function
---@param fn function Function to call when Credits is selected
function title_screen.set_credits_callback(fn)
    credits_callback = fn
end

--- Show the title screen with fade-in animation
--- Resets focus to Play Game
---@return nil
function title_screen.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        mouse_active = false
        focused_index = 1  -- Default to Play Game
    end
end

--- Hide the title screen with fade out
---@return nil
function title_screen.hide()
    if state == STATE.OPEN or state == STATE.FADING_IN then
        state = STATE.FADING_OUT
        fade_progress = 0
    end
end

--- Check if title screen is blocking game input
---@return boolean is_active True if title screen is visible or animating
function title_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Trigger the selected menu action
---@return nil
local function trigger_selection()
    local item = MENU_ITEMS[focused_index]

    if item.id == "play_game" then
        -- Play Game opens slot screen on top of title screen, don't hide
        if play_game_callback then play_game_callback() end
    elseif item.id == "audio" then
        -- Audio dialog opens on top of title screen, don't hide
        if audio_callback then audio_callback() end
    elseif item.id == "controls" then
        -- Controls dialog opens on top of title screen, don't hide
        if controls_callback then controls_callback() end
    elseif item.id == "settings" then
        -- Settings dialog opens on top of title screen, don't hide
        if settings_callback then settings_callback() end
    elseif item.id == "credits" then
        if credits_callback then credits_callback() end
    end
end

--- Process title screen input (menu navigation and selection)
--- Only processes input when screen is in OPEN state
---@return nil
function title_screen.input()
    if state ~= STATE.OPEN then return end

    -- Navigation
    if controls.menu_up_pressed() then
        mouse_active = false
        focused_index = focused_index - 1
        if focused_index < 1 then focused_index = #MENU_ITEMS end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focused_index = focused_index + 1
        if focused_index > #MENU_ITEMS then focused_index = 1 end
    end

    -- Confirm selection
    if controls.menu_confirm_pressed() then
        trigger_selection()
    end
end

--- Advance fade animations and handle state transitions
---@param dt number Delta time in seconds
---@param block_mouse boolean|nil If true, skip mouse input processing (e.g., settings menu is open)
function title_screen.update(dt, block_mouse)
    if state == STATE.HIDDEN then return end

    -- Update cursor animation
    if cursor_animation then
        cursor_animation:play(dt)
    end

    blink_time = blink_time + dt

    -- Handle fade transitions
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

    -- Handle mouse hover (only when menu is open and not blocked by overlay)
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

        -- Check mouse hover over menu items
        if mouse_active and #menu_item_positions > 0 then
            local local_my = my / scale
            for i, pos in ipairs(menu_item_positions) do
                -- Simple vertical hit test (items span full width conceptually)
                if local_my >= pos.y - 6 and local_my <= pos.y + 6 then
                    focused_index = i

                    -- Check for click
                    if canvas.is_mouse_pressed(0) then
                        trigger_selection()
                    end
                    break
                end
            end
        end
    end
end

--- Draw the title screen overlay (background, title, menu items, cursor)
---@return nil
function title_screen.draw()
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
    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Draw content at 1x scale
    canvas.save()
    canvas.scale(scale, scale)

    local center_x = screen_w / (2 * scale)

    -- Draw title "KNIGHTMARE"
    canvas.set_font_family("menu_font")
    canvas.set_font_size(16)
    canvas.set_text_baseline("middle")

    local title = "KNIGHTMARE"
    local title_metrics = canvas.get_text_metrics(title)
    local title_x = center_x - title_metrics.width / 2

    -- Title shadow
    canvas.set_color("#000000")
    canvas.draw_text(title_x + 1, TITLE_Y + 1, title)

    -- Title text (yellow)
    canvas.set_color("#FFFF00")
    canvas.draw_text(title_x, TITLE_Y, title)

    -- Draw menu items
    canvas.set_font_size(7)
    menu_item_positions = {}

    for i, item in ipairs(MENU_ITEMS) do
        local item_y = MENU_START_Y + (i - 1) * MENU_ITEM_SPACING
        local metrics = canvas.get_text_metrics(item.label)
        local item_x = center_x - metrics.width / 2

        -- Store position for mouse hit testing
        menu_item_positions[i] = { x = item_x, y = item_y }

        local focused = (i == focused_index)

        -- Text shadow
        canvas.set_color("#000000")
        canvas.draw_text(item_x + 1, item_y + 1, item.label)

        -- Draw main text
        canvas.set_color(focused and "#FFFF00" or "#FFFFFF")
        canvas.draw_text(item_x, item_y, item.label)
    end

    -- Draw "Full Screen: Press F11" hint at bottom
    local hint_y = screen_h / scale - 12
    local hint_alpha = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(blink_time * 6))
    canvas.set_global_alpha(alpha * hint_alpha)
    canvas.set_font_size(6)
    canvas.set_text_baseline("middle")

    local fs_text = "Full Screen: Press "
    local f11_text = "F11"
    local fs_metrics = canvas.get_text_metrics(fs_text)
    local f11_metrics = canvas.get_text_metrics(f11_text)
    local total_w = fs_metrics.width + f11_metrics.width
    local hint_x = center_x - total_w / 2

    canvas.set_color("#FFFF00")
    canvas.draw_text(hint_x, hint_y, fs_text)
    canvas.set_color("#00FF00")
    canvas.draw_text(hint_x + fs_metrics.width, hint_y, f11_text)

    canvas.set_global_alpha(alpha)

    canvas.restore()  -- Exit scaled context for cursor drawing

    -- Draw cursor (animated player sprite) next to focused item
    if cursor_animation and focused_index >= 1 and focused_index <= #menu_item_positions then
        local pos = menu_item_positions[focused_index]
        if pos then
            -- Position cursor to the left of the menu item
            local cursor_x = pos.x - CURSOR_OFFSET_X
            local cursor_y = pos.y - 8  -- Center vertically (sprite is 16px tall)

            -- Draw cursor at screen coordinates (animation applies its own scale)
            cursor_animation:draw(
                cursor_x * scale,
                cursor_y * scale
            )
        end
    end

    canvas.set_global_alpha(1)
end

return title_screen
