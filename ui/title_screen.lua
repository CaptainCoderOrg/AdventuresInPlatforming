--- Title screen overlay with menu navigation and animated cursor
local canvas = require("canvas")
local controls = require("controls")
local config = require("config")
local Animation = require("Animation")
local sprites = require("sprites")
local RestorePoint = require("RestorePoint")

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
    { id = "continue", label = "Continue", enabled_fn = function() return RestorePoint.get() ~= nil end },
    { id = "new_game", label = "New Game" },
    { id = "settings", label = "Settings" },
}

local state = STATE.HIDDEN
local fade_progress = 0
local focused_index = 2  -- Default to "New Game" (index 2)

-- Cursor animation (player idle sprite)
local cursor_animation = nil

-- Menu action callbacks (set by main.lua to handle game state transitions)
local continue_callback = nil
local new_game_callback = nil
local settings_callback = nil

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

--- Check if a menu item is enabled
---@param item table Menu item definition
---@return boolean enabled
local function is_item_enabled(item)
    if item.enabled_fn then
        return item.enabled_fn()
    end
    return true
end

--- Find next enabled menu item in direction
---@param start_index number Starting index
---@param direction number 1 for down, -1 for up
---@return number index Next enabled index (or start_index if none found)
local function find_next_enabled(start_index, direction)
    local index = start_index
    for _ = 1, #MENU_ITEMS do
        index = index + direction
        if index < 1 then index = #MENU_ITEMS end
        if index > #MENU_ITEMS then index = 1 end
        if is_item_enabled(MENU_ITEMS[index]) then
            return index
        end
    end
    return start_index
end

--- Initialize title screen components (cursor animation)
--- Must be called once before showing the title screen
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

--- Set the continue callback function
---@param fn function Function to call when Continue is selected
function title_screen.set_continue_callback(fn)
    continue_callback = fn
end

--- Set the new game callback function
---@param fn function Function to call when New Game is selected
function title_screen.set_new_game_callback(fn)
    new_game_callback = fn
end

--- Set the settings callback function
---@param fn function Function to call when Settings is selected
function title_screen.set_settings_callback(fn)
    settings_callback = fn
end

--- Show the title screen with fade-in animation
--- Resets focus to Continue (if available) or New Game
function title_screen.show()
    if state == STATE.HIDDEN then
        state = STATE.FADING_IN
        fade_progress = 0
        mouse_active = false
        -- Reset focus to first enabled item (prioritize Continue if available)
        if is_item_enabled(MENU_ITEMS[1]) then
            focused_index = 1
        else
            focused_index = 2
        end
    end
end

--- Hide the title screen with fade out
local function hide()
    if state == STATE.OPEN then
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
local function trigger_selection()
    local item = MENU_ITEMS[focused_index]
    if not is_item_enabled(item) then return end

    if item.id == "continue" then
        hide()
        if continue_callback then continue_callback() end
    elseif item.id == "new_game" then
        hide()
        if new_game_callback then new_game_callback() end
    elseif item.id == "settings" then
        -- Settings opens on top of title screen, don't hide
        if settings_callback then settings_callback() end
    end
end

--- Process title screen input (menu navigation and selection)
--- Only processes input when screen is in OPEN state
function title_screen.input()
    if state ~= STATE.OPEN then return end

    -- Navigation
    if controls.menu_up_pressed() then
        mouse_active = false
        focused_index = find_next_enabled(focused_index, -1)
    elseif controls.menu_down_pressed() then
        mouse_active = false
        focused_index = find_next_enabled(focused_index, 1)
    end

    -- Confirm selection
    if controls.menu_confirm_pressed() then
        trigger_selection()
    end
end

--- Advance fade animations and handle state transitions
---@param dt number Delta time in seconds
function title_screen.update(dt)
    if state == STATE.HIDDEN then return end

    -- Update cursor animation
    if cursor_animation then
        cursor_animation:play(dt)
    end

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

    -- Handle mouse hover (only when menu is open)
    if state == STATE.OPEN then
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
                if is_item_enabled(MENU_ITEMS[i]) then
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
end

--- Draw the title screen overlay (background, title, menu items, cursor)
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

        -- Determine text color
        local enabled = is_item_enabled(item)
        local focused = (i == focused_index)

        -- Text shadow (only for enabled items)
        if enabled then
            canvas.set_color("#000000")
            canvas.draw_text(item_x + 1, item_y + 1, item.label)
        end

        -- Draw main text with appropriate color
        if not enabled then
            canvas.set_color("#666666")  -- Gray for disabled
        elseif focused then
            canvas.set_color("#FFFF00")  -- Yellow for focused
        else
            canvas.set_color("#FFFFFF")  -- White for normal
        end

        canvas.draw_text(item_x, item_y, item.label)
    end

    canvas.restore()  -- Exit scaled context for cursor drawing

    -- Draw cursor (animated player sprite) next to focused item
    if cursor_animation and focused_index >= 1 and focused_index <= #menu_item_positions then
        local pos = menu_item_positions[focused_index]
        if pos and is_item_enabled(MENU_ITEMS[focused_index]) then
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
