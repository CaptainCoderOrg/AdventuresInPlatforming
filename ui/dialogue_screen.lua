--- Split-screen dialogue UI with camera shift
--- Displays dialogue in bottom area while showing map view in top area
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local dialogue_manager = require("dialogue/manager")
local dialogue_registry = require("dialogue/registry")

local dialogue_screen = {}

-- State machine states
local STATE = {
    HIDDEN = 1,
    FADING_IN = 2,
    OPEN = 3,
    FADING_OUT = 4,
}

-- Layout constants (at 1x scale, scaled by config.ui.SCALE)
local MAP_VIEW_HEIGHT = 48         -- Top area showing game world
local DIALOGUE_AREA_HEIGHT = 168   -- Bottom area for dialogue
local PLAYER_MARGIN = 8            -- Player's margin from bottom of map view
local FADE_DURATION = 0.3          -- Fade in/out duration in seconds

-- Dialogue box layout (at 1x scale)
local BOX_MARGIN_X = 32            -- Horizontal margin from screen edges
local BOX_MARGIN_BOTTOM = 16       -- Margin from bottom of screen
local BOX_HEIGHT = 100             -- Dialogue box height
local TEXT_PADDING_TOP = 10
local TEXT_PADDING_LEFT = 12
local TEXT_PADDING_RIGHT = 12
local LINE_HEIGHT = 12
local OPTION_INDENT = 8
local FONT_SIZE = 8

-- Selection indicator
local SELECTOR_CHAR = ">"
local SELECTOR_OFFSET_X = -10

-- 9-slice definition (reuse simple_dialogue sprite: 76x37, borders: left=10, top=7, right=9, bottom=7)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Module state
local state = STATE.HIDDEN
local fade_progress = 0
local current_tree = nil
local current_node = nil
local filtered_options = nil
local selected_option = 1
local player_ref = nil
local camera_ref = nil
local original_viewport_height = nil
local original_camera_y = nil
local target_camera_y = nil

-- On-close callback (invoked after fade-out completes)
local on_close_callback = nil
local keep_camera_on_close = false

-- Mouse support
local mouse_active = false
local last_mouse_x, last_mouse_y = 0, 0
local option_positions = {}

-- Sprite scales for dialogue (same as simple_dialogue.lua)
local KEYBOARD_SCALE = 0.125
local KEYBOARD_WORD_SCALE = 0.15
local GAMEPAD_SCALE = 0.5
local GAMEPAD_SHOULDER_SCALE = 0.6

--- Get sprite scale for a key code (dialogue-sized)
---@param code number Key code
---@return number Scale multiplier
local function get_dialogue_key_scale(code)
    if sprites.controls.is_word_key(code) then
        return KEYBOARD_WORD_SCALE
    end
    return KEYBOARD_SCALE
end

--- Get sprite scale for a button code (dialogue-sized)
---@param code number Button code
---@return number Scale multiplier
local function get_dialogue_button_scale(code)
    if sprites.controls.is_shoulder_button(code) then
        return GAMEPAD_SHOULDER_SCALE
    end
    return GAMEPAD_SCALE
end

--- Get sprite size for dialogue context
---@param scheme string "keyboard" or "gamepad"
---@param code number Key/button code
---@return number Sprite size in pixels
local function get_dialogue_sprite_size(scheme, code)
    if scheme == "gamepad" then
        return 16 * get_dialogue_button_scale(code)
    else
        return 64 * get_dialogue_key_scale(code)
    end
end

--- Draw a control sprite at dialogue scale
---@param scheme string "keyboard" or "gamepad"
---@param code number Key/button code
---@param x number X position
---@param y number Y position (text baseline)
---@return number Width of drawn sprite
local function draw_dialogue_sprite(scheme, code, x, y)
    local sprite_size = get_dialogue_sprite_size(scheme, code)
    local sprite_y = y - FONT_SIZE + (FONT_SIZE - sprite_size) / 2

    if scheme == "gamepad" then
        sprites.controls.draw_button(code, x, sprite_y, get_dialogue_button_scale(code))
    else
        sprites.controls.draw_key(code, x, sprite_y, get_dialogue_key_scale(code))
    end

    return sprite_size
end

--- Get the width of a word, accounting for keybinding placeholders
---@param word string Word possibly containing {action} placeholders
---@param scheme string "keyboard" or "gamepad"
---@return number Width in pixels
local function get_word_width(word, scheme)
    local segments = TextDisplay.parse_segments(word)
    local total_width = 0

    for _, segment in ipairs(segments) do
        if segment.type == "text" then
            total_width = total_width + canvas.get_text_width(segment.value)
        elseif segment.type == "color_start" or segment.type == "color_end" then
            -- Color tags have no width
        else
            local seg_scheme, code = TextDisplay.resolve_segment(segment, scheme)
            if seg_scheme and code then
                total_width = total_width + get_dialogue_sprite_size(seg_scheme, code)
            end
        end
    end

    return total_width
end

--- Draw a word with keybinding sprite support
---@param word string Word possibly containing {action} placeholders
---@param scheme string "keyboard" or "gamepad"
---@param x number X position
---@param y number Y position (baseline)
---@return number Width drawn
local function draw_word(word, scheme, x, y)
    local segments = TextDisplay.parse_segments(word)
    local current_x = x

    for _, segment in ipairs(segments) do
        if segment.type == "color_start" then
            canvas.set_color(segment.value)
        elseif segment.type == "color_end" then
            canvas.set_color("#FFFFFF")
        elseif segment.type == "text" then
            canvas.draw_text(current_x, y, segment.value)
            current_x = current_x + canvas.get_text_width(segment.value)
        else
            local seg_scheme, code = TextDisplay.resolve_segment(segment, scheme)
            if seg_scheme and code then
                current_x = current_x + draw_dialogue_sprite(seg_scheme, code, current_x, y)
            end
        end
    end

    return current_x - x
end

--- Draw word-wrapped text with keybinding support
---@param text string Text to draw (may contain {action} placeholders)
---@param x number Left edge X position
---@param y number Top Y position
---@param max_width number Maximum line width
---@param scheme string "keyboard" or "gamepad"
---@return number Total height drawn
local function draw_wrapped_text(text, x, y, max_width, scheme)
    local y_offset = 0

    -- Split text into lines first
    for input_line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if input_line == "" then
            y_offset = y_offset + LINE_HEIGHT
        else
            -- Word-wrap this line
            local words = {}
            for word in input_line:gmatch("%S+") do
                table.insert(words, word)
            end

            local line_words = {}
            local line_width = 0
            local space_width = canvas.get_text_width(" ")

            for _, word in ipairs(words) do
                local word_width = get_word_width(word, scheme)
                local test_width = line_width + (line_width > 0 and space_width or 0) + word_width

                if test_width > max_width and line_width > 0 then
                    -- Draw current line and start new one
                    local draw_x = x
                    local draw_y = y + y_offset + FONT_SIZE
                    for i, w in ipairs(line_words) do
                        if i > 1 then
                            canvas.draw_text(draw_x, draw_y, " ")
                            draw_x = draw_x + space_width
                        end
                        draw_x = draw_x + draw_word(w, scheme, draw_x, draw_y)
                    end
                    y_offset = y_offset + LINE_HEIGHT
                    line_words = { word }
                    line_width = word_width
                else
                    table.insert(line_words, word)
                    line_width = test_width
                end
            end

            -- Draw remaining words
            if #line_words > 0 then
                local draw_x = x
                local draw_y = y + y_offset + FONT_SIZE
                for i, w in ipairs(line_words) do
                    if i > 1 then
                        canvas.draw_text(draw_x, draw_y, " ")
                        draw_x = draw_x + space_width
                    end
                    draw_x = draw_x + draw_word(w, scheme, draw_x, draw_y)
                end
                y_offset = y_offset + LINE_HEIGHT
            end
        end
    end

    return y_offset
end

--- Set up the current dialogue node
---@param node_id string|nil Node ID to navigate to (nil to close dialogue)
local function set_node(node_id)
    if not node_id or not current_tree or not current_tree.nodes[node_id] then
        -- Close dialogue
        state = STATE.FADING_OUT
        fade_progress = 0
        return
    end

    current_node = current_tree.nodes[node_id]
    filtered_options = dialogue_manager.filter_options(current_node.options or {}, player_ref)
    selected_option = 1

    -- Execute any actions on entering this node
    if current_node.actions then
        dialogue_manager.execute_actions(current_node.actions, player_ref)
    end
end

--- Start a dialogue with the given tree ID
---@param tree_id string Dialogue tree identifier
---@param player table Player instance
---@param camera table Camera instance
---@param start_node string|nil Optional node to start at (overrides tree.start_node)
function dialogue_screen.start(tree_id, player, camera, start_node)
    local tree = dialogue_registry.get(tree_id)
    if not tree then
        return
    end

    current_tree = tree
    player_ref = player
    camera_ref = camera

    -- Set player reference in manager for flag operations
    dialogue_manager.set_player(player)

    -- Save original camera state
    original_viewport_height = camera:get_viewport_height()
    original_camera_y = camera:get_y()

    -- Calculate target camera Y to position player with margin below their feet
    -- Map view is MAP_VIEW_HEIGHT pixels at 1x scale
    local tile_size = config.ui.TILE  -- base tile size (16px)
    local viewport_tiles = MAP_VIEW_HEIGHT / tile_size  -- 48/16 = 3 tiles
    local margin_tiles = PLAYER_MARGIN / tile_size  -- 8/16 = 0.5 tiles
    -- player.y is the player's feet position (bottom of sprite)
    -- We want margin_tiles of space visible BELOW the feet
    -- Feet should appear at: viewport_tiles - margin_tiles = 2.5 tiles from viewport top
    -- Camera Y calculation: camera_y = player.y - position_in_viewport
    -- Adding 1 tile to account for player sprite height (head to feet)
    target_camera_y = player.y - (viewport_tiles - margin_tiles) + 1

    on_close_callback = nil
    keep_camera_on_close = false
    state = STATE.FADING_IN
    fade_progress = 0
    set_node(start_node or tree.start_node)

    -- Reset mouse state
    mouse_active = false
    option_positions = {}
end

--- Set a callback to invoke when dialogue closes (after fade-out)
---@param fn fun(player: table, camera: table, original_camera_y: number)|nil Callback after fade-out, or nil to clear
function dialogue_screen.set_on_close(fn)
    on_close_callback = fn
end

--- Check if dialogue screen is currently active
---@return boolean True if dialogue is visible or transitioning
function dialogue_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Process input for dialogue navigation
function dialogue_screen.input()
    if state ~= STATE.OPEN then return end

    -- Navigate options
    if controls.menu_up_pressed() then
        mouse_active = false
        if selected_option > 1 then
            selected_option = selected_option - 1
        end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        if filtered_options and selected_option < #filtered_options then
            selected_option = selected_option + 1
        end
    elseif controls.menu_confirm_pressed() or controls.up_pressed() then
        -- Select current option
        if filtered_options and filtered_options[selected_option] then
            local option = filtered_options[selected_option]
            -- Execute option-specific actions
            if option.actions then
                dialogue_manager.execute_actions(option.actions, player_ref)
            end
            if option.keep_camera then
                keep_camera_on_close = true
            end
            set_node(option.next)
        end
    end
end

--- Update dialogue screen state
---@param dt number Delta time in seconds
function dialogue_screen.update(dt)
    if state == STATE.HIDDEN then return end

    -- Mouse hover detection (only when OPEN)
    if state == STATE.OPEN then
        local mx, my = canvas.get_mouse_x(), canvas.get_mouse_y()

        -- Detect mouse movement to enable mouse mode
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x, last_mouse_y = mx, my
        end

        -- Mouse hover over options
        if mouse_active and #option_positions > 0 then
            local half_line = (LINE_HEIGHT * config.ui.SCALE) / 2
            for i, pos in ipairs(option_positions) do
                if mx >= pos.x_start and mx <= pos.x_end and
                   my >= pos.y - half_line and my <= pos.y + half_line then
                    selected_option = i

                    -- Click to select
                    if canvas.is_mouse_pressed(0) then
                        if filtered_options and filtered_options[selected_option] then
                            local option = filtered_options[selected_option]
                            if option.actions then
                                dialogue_manager.execute_actions(option.actions, player_ref)
                            end
                            if option.keep_camera then
                                keep_camera_on_close = true
                            end
                            set_node(option.next)
                        end
                    end
                    break
                end
            end
        end
    end

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
        -- Update camera during fade
        if camera_ref and target_camera_y then
            local t = fade_progress
            local new_y = original_camera_y + (target_camera_y - original_camera_y) * t
            camera_ref:set_y(new_y)
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
            -- Save refs before cleanup for callback
            local saved_player = player_ref
            local saved_camera = camera_ref
            local saved_original_y = original_camera_y
            -- Restore camera unless an option requested keeping it
            if not keep_camera_on_close then
                if camera_ref then
                    camera_ref:set_y(original_camera_y)
                end
            end
            -- Clean up
            current_tree = nil
            current_node = nil
            filtered_options = nil
            player_ref = nil
            camera_ref = nil
            -- Invoke on-close callback with original camera Y for smooth transitions
            local cb = on_close_callback
            on_close_callback = nil
            keep_camera_on_close = false
            if cb then cb(saved_player, saved_camera, saved_original_y) end
        else
            -- Animate camera during fade out unless an option requested keeping it
            if not keep_camera_on_close then
                if camera_ref and target_camera_y then
                    local t = 1 - fade_progress
                    local new_y = original_camera_y + (target_camera_y - original_camera_y) * t
                    camera_ref:set_y(new_y)
                end
            end
        end
    end
end

--- Draw the dialogue screen overlay
function dialogue_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Calculate alpha based on state
    local alpha = 0
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.OPEN then
        alpha = 1
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    -- Calculate dialogue area position (bottom portion of screen)
    local map_view_height = MAP_VIEW_HEIGHT * scale
    local dialogue_area_y = map_view_height

    canvas.set_global_alpha(alpha)

    -- Draw black overlay over dialogue area
    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, dialogue_area_y, screen_w, screen_h - dialogue_area_y)

    -- Draw dialogue box if we have content
    if current_node and alpha > 0 then
        canvas.save()
        canvas.scale(scale, scale)

        -- Calculate box dimensions (at 1x scale)
        local base_w = screen_w / scale
        local base_h = screen_h / scale
        local box_x = BOX_MARGIN_X
        local box_w = base_w - BOX_MARGIN_X * 2
        local box_y = base_h - BOX_MARGIN_BOTTOM - BOX_HEIGHT
        local box_h = BOX_HEIGHT

        -- Draw 9-slice background
        nine_slice.draw(slice, box_x, box_y, box_w, box_h)

        -- Set up text rendering
        canvas.set_font_family("menu_font")
        canvas.set_font_size(FONT_SIZE)
        canvas.set_text_baseline("bottom")
        canvas.set_color("#FFFFFF")

        local scheme = controls.get_binding_scheme()
        local text_x = box_x + TEXT_PADDING_LEFT
        local text_y = box_y + TEXT_PADDING_TOP
        local max_text_width = box_w - TEXT_PADDING_LEFT - TEXT_PADDING_RIGHT

        -- Draw NPC text
        local text_height = draw_wrapped_text(
            current_node.text or "",
            text_x,
            text_y,
            max_text_width,
            scheme
        )

        -- Draw options
        option_positions = {}
        if filtered_options and #filtered_options > 0 then
            local option_y = text_y + text_height + LINE_HEIGHT

            for i, option in ipairs(filtered_options) do
                local option_x = text_x + OPTION_INDENT
                local draw_y = option_y + FONT_SIZE

                -- Store option position in screen coordinates for mouse detection
                option_positions[i] = {
                    y = draw_y * scale,
                    x_start = (option_x + SELECTOR_OFFSET_X) * scale,
                    x_end = (box_x + box_w - TEXT_PADDING_RIGHT) * scale,
                }

                -- Draw selection indicator
                if i == selected_option then
                    canvas.set_color("#FFCC00")
                    canvas.draw_text(option_x + SELECTOR_OFFSET_X, draw_y, SELECTOR_CHAR)
                else
                    canvas.set_color("#AAAAAA")
                end

                -- Draw option text
                draw_word(option.text or "", scheme, option_x, draw_y)
                option_y = option_y + LINE_HEIGHT
            end
        end

        canvas.restore()
    end

    canvas.set_global_alpha(1)
    canvas.set_text_baseline("alphabetic")
end

--- Get the camera Y offset for world rendering during dialogue
--- This shifts the world view up so player is visible in the small map area
---@return number offset_y Y offset in pixels (0 when not active)
function dialogue_screen.get_camera_offset_y()
    if state == STATE.HIDDEN then return 0 end

    local scale = config.ui.SCALE
    local dialogue_area_height = DIALOGUE_AREA_HEIGHT * scale

    local alpha = 0
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.OPEN then
        alpha = 1
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    -- Return the offset to shift camera view
    return dialogue_area_height * alpha
end

return dialogue_screen
