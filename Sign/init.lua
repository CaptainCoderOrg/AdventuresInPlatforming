--- Interactive sign system for displaying text prompts when player is nearby
local canvas = require("canvas")
local sprites = require("sprites")
local controls = require("controls")
local config = require("config")
local state = require("Sign/state")

local Sign = {}

local FONT_SIZE = 9 * config.ui.SCALE
local TEXT_PADDING = 2 * config.ui.SCALE
local LINE_SPACING = 2 * config.ui.SCALE
local FADE_DURATION = 0.25
local GAMEPAD_SPRITE_SCALE = 0.5
local GAMEPAD_SHOULDER_SCALE = 0.75
local KEYBOARD_SPRITE_SCALE = 0.125
local KEYBOARD_WORD_SCALE = 0.1875

--- Check if player is touching a sign (overlapping bounding boxes)
---@param sign table Sign instance
---@param player table Player instance
---@return boolean True if player overlaps sign tile
local function player_touching(sign, player)
    local px, py = player.x + player.box.x, player.y + player.box.y
    local pw, ph = player.box.w, player.box.h
    local sx, sy = sign.x, sign.y
    local sw, sh = 1, 1  -- sign is 1x1 tile

    return px < sx + sw and px + pw > sx and
           py < sy + sh and py + ph > sy
end

--- Parse text into segments of plain text, action placeholders, and explicit key/button placeholders
---@param text string Text with placeholders like {jump}, {key:SPACE}, {button:SOUTH}, {keyboard:jump}, or {gamepad:attack}
---@return table Array of {type="text"|"action"|"key"|"button"|"keyboard_action"|"gamepad_action", value=string|number}
local function parse_segments(text)
    local segments = {}
    local pos = 1

    while pos <= #text do
        -- Match {type:value} or {action_id}
        local start_brace, end_brace, prefix, suffix = text:find("{([%w_]+):?([%w_]*)}", pos)
        if start_brace then
            -- Add text before the placeholder
            if start_brace > pos then
                table.insert(segments, { type = "text", value = text:sub(pos, start_brace - 1) })
            end

            if suffix and suffix ~= "" then
                -- Prefixed placeholder: {prefix:value}
                if prefix == "key" then
                    -- Explicit keyboard key: {key:SPACE}
                    local key_code = canvas.keys[suffix]
                    if key_code then
                        table.insert(segments, { type = "key", value = key_code })
                    else
                        -- Fallback: show as text if key not found
                        table.insert(segments, { type = "text", value = suffix })
                    end
                elseif prefix == "button" then
                    -- Explicit gamepad button: {button:SOUTH}
                    local button_code = canvas.buttons[suffix]
                    if button_code then
                        table.insert(segments, { type = "button", value = button_code })
                    else
                        -- Fallback: show as text if button not found
                        table.insert(segments, { type = "text", value = suffix })
                    end
                elseif prefix == "keyboard" then
                    -- Keyboard binding for action: {keyboard:jump}
                    table.insert(segments, { type = "keyboard_action", value = suffix })
                elseif prefix == "gamepad" then
                    -- Gamepad binding for action: {gamepad:attack}
                    table.insert(segments, { type = "gamepad_action", value = suffix })
                else
                    -- Unknown prefix, show as text
                    table.insert(segments, { type = "text", value = prefix .. ":" .. suffix })
                end
            else
                -- Action placeholder: {action_id}
                table.insert(segments, { type = "action", value = prefix })
            end
            pos = end_brace + 1
        else
            -- Add remaining text
            table.insert(segments, { type = "text", value = text:sub(pos) })
            break
        end
    end

    return segments
end

--- Split text into lines and parse each line into segments
---@param text string Text with newlines and placeholders
---@return table Array of lines, each containing parsed segments
local function parse_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, parse_segments(line))
    end
    return lines
end

--- Get keyboard sprite scale for a specific key code
---@param code number Key code
---@return number Scale multiplier
local function get_key_scale(code)
    if sprites.controls.is_word_key(code) then
        return KEYBOARD_WORD_SCALE * config.ui.SCALE
    end
    return KEYBOARD_SPRITE_SCALE * config.ui.SCALE
end

--- Get gamepad button scale for a specific button code
---@param code number Button code
---@return number Scale multiplier
local function get_button_scale(code)
    if sprites.controls.is_shoulder_button(code) then
        return GAMEPAD_SHOULDER_SCALE * config.ui.SCALE
    end
    return GAMEPAD_SPRITE_SCALE * config.ui.SCALE
end

--- Get sprite size for the given scheme and optional key code
---@param scheme string "keyboard" or "gamepad"
---@param code number|nil Key/button code (for variable sizing)
---@return number Sprite size in pixels
local function get_sprite_size(scheme, code)
    if scheme == "gamepad" then
        local scale = code and get_button_scale(code) or (GAMEPAD_SPRITE_SCALE * config.ui.SCALE)
        return 16 * scale
    else
        local scale = code and get_key_scale(code) or (KEYBOARD_SPRITE_SCALE * config.ui.SCALE)
        return 64 * scale
    end
end

--- Resolve a segment to its scheme and code for sprite rendering
---@param segment table Parsed segment
---@param current_scheme string Current input scheme ("keyboard" or "gamepad")
---@return string|nil scheme The scheme to use for rendering
---@return number|nil code The key/button code
local function resolve_segment(segment, current_scheme)
    local seg_type = segment.type
    if seg_type == "action" then
        return current_scheme, controls.get_binding(current_scheme, segment.value)
    elseif seg_type == "key" then
        return "keyboard", segment.value
    elseif seg_type == "button" then
        return "gamepad", segment.value
    elseif seg_type == "keyboard_action" then
        return "keyboard", controls.get_binding("keyboard", segment.value)
    elseif seg_type == "gamepad_action" then
        return "gamepad", controls.get_binding("gamepad", segment.value)
    end
    return nil, nil
end

--- Calculate total width of segments
---@param segments table Array of parsed segments
---@param scheme string "keyboard" or "gamepad"
---@return number Total width in pixels
local function get_segments_width(segments, scheme)
    local total_width = 0

    for _, segment in ipairs(segments) do
        if segment.type == "text" then
            total_width = total_width + canvas.get_text_width(segment.value)
        else
            local seg_scheme, code = resolve_segment(segment, scheme)
            if seg_scheme then
                total_width = total_width + get_sprite_size(seg_scheme, code)
            end
        end
    end

    return total_width
end

--- Draw a control sprite (keyboard key or gamepad button)
---@param seg_scheme string "keyboard" or "gamepad"
---@param code number Key or button code
---@param x number Screen X position
---@param text_y number Y position for text baseline
---@return number width Width of drawn sprite
local function draw_control_sprite(seg_scheme, code, x, text_y)
    local sprite_size = get_sprite_size(seg_scheme, code)
    local sprite_y = text_y - FONT_SIZE + (FONT_SIZE - sprite_size) / 2

    if seg_scheme == "gamepad" then
        sprites.controls.draw_button(code, x, sprite_y, get_button_scale(code))
    else
        sprites.controls.draw_key(code, x, sprite_y, get_key_scale(code))
    end

    return sprite_size
end

--- Draw segments with mixed text and sprites
---@param segments table Array of parsed segments
---@param scheme string "keyboard" or "gamepad"
---@param start_x number Starting X position (left edge)
---@param text_y number Y position for text baseline
local function draw_segments(segments, scheme, start_x, text_y)
    local x = start_x

    canvas.set_text_align("left")

    for _, segment in ipairs(segments) do
        if segment.type == "text" then
            canvas.draw_text(x, text_y, segment.value, {})
            x = x + canvas.get_text_width(segment.value)
        else
            local seg_scheme, code = resolve_segment(segment, scheme)
            if seg_scheme and code then
                x = x + draw_control_sprite(seg_scheme, code, x, text_y)
            end
        end
    end
end

--- Create a new sign at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param text string Display text (can include {action_id} variables)
---@return table Sign instance
function Sign.new(x, y, text)
    local self = {
        id = "sign_" .. state.next_id,
        x = x,
        y = y,
        text = text,
        is_active = false,
        alpha = 0,
    }
    state.next_id = state.next_id + 1
    state.all[self] = true
    return self
end

--- Update all signs (checks player proximity and fades text)
---@param dt number Delta time in seconds
---@param player table Player instance
function Sign.update(dt, player)
    for sign in pairs(state.all) do
        sign.is_active = player_touching(sign, player)

        local target = sign.is_active and 1 or 0
        local fade_rate = dt / FADE_DURATION
        if sign.alpha < target then
            sign.alpha = math.min(sign.alpha + fade_rate, 1)
        elseif sign.alpha > target then
            sign.alpha = math.max(sign.alpha - fade_rate, 0)
        end
    end
end

--- Draw all signs and their text popups.
--- Active signs also render their text bubble above the sprite.
function Sign.draw()
    local tile_size = sprites.tile_size

    for sign in pairs(state.all) do
        local screen_x = sign.x * tile_size
        local screen_y = sign.y * tile_size
        canvas.draw_image(
            sprites.environment.sign,
            screen_x, screen_y,
            tile_size, tile_size
        )

        if config.bounding_boxes then
            canvas.set_color("#FFA500")
            canvas.draw_rect(screen_x, screen_y, tile_size, tile_size)
        end

        if sign.alpha > 0 then
            local scheme = controls.get_last_input_device()
            local lines = parse_lines(sign.text)
            local num_lines = #lines

            canvas.set_font_family("menu_font")
            canvas.set_font_size(FONT_SIZE)
            canvas.set_text_baseline("bottom")

            -- Calculate max width across all lines
            local max_line_width = 0
            for _, segments in ipairs(lines) do
                local line_width = get_segments_width(segments, scheme)
                if line_width > max_line_width then
                    max_line_width = line_width
                end
            end

            -- Calculate content dimensions
            local content_width = max_line_width
            local content_height = num_lines * FONT_SIZE + (num_lines - 1) * LINE_SPACING
            local box_width = content_width + TEXT_PADDING * 2
            local box_height = content_height + TEXT_PADDING * 2

            local center_x = screen_x + tile_size / 2
            local box_top = screen_y - box_height

            canvas.set_global_alpha(sign.alpha)

            canvas.set_color("#00000099")
            canvas.fill_rect(
                center_x - box_width / 2,
                box_top,
                box_width,
                box_height
            )

            canvas.set_color("#ffffffee")
            for i, segments in ipairs(lines) do
                local line_width = get_segments_width(segments, scheme)
                local start_x = center_x - line_width / 2
                -- Position each line: box_top + padding + (line index * line height)
                local line_y = box_top + TEXT_PADDING + i * FONT_SIZE + (i - 1) * LINE_SPACING
                draw_segments(segments, scheme, start_x, line_y)
            end

            canvas.set_global_alpha(1)
            canvas.set_text_align("left")
            canvas.set_text_baseline("alphabetic")
        end
    end
end

--- Remove a specific sign from the active set.
---@param sign table Sign instance to remove
function Sign.remove(sign)
    state.all[sign] = nil
end

--- Remove all signs and reset ID counter.
--- Call before loading a new level to prevent stale signs.
function Sign.clear()
    state.all = {}
    state.next_id = 1
end

return Sign
