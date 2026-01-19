--- Text display system for rendering text popups with control sprite support
--- Extracted from Sign module to allow any prop to display text
local canvas = require("canvas")
local sprites = require("sprites")
local controls = require("controls")
local config = require("config")

local TextDisplay = {}

local FONT_SIZE = 9 * config.ui.SCALE
local TEXT_PADDING = 2 * config.ui.SCALE
local LINE_SPACING = 2 * config.ui.SCALE
local FADE_DURATION = 0.25
local DEFAULT_TEXT_COLOR = "#ffffffee"
local GAMEPAD_SPRITE_SCALE = 0.5
local GAMEPAD_SHOULDER_SCALE = 0.75
local KEYBOARD_SPRITE_SCALE = 0.125
local KEYBOARD_WORD_SCALE = 0.1875

--- Find the earliest position among candidates
---@param candidates table Array of {pos=number|nil, type=string}
---@return number|nil position Earliest position found
---@return string|nil tag_type Type of the earliest tag
local function find_earliest_tag(candidates)
    local earliest_pos = nil
    local earliest_type = nil

    for _, candidate in ipairs(candidates) do
        if candidate.pos and (not earliest_pos or candidate.pos < earliest_pos) then
            earliest_pos = candidate.pos
            earliest_type = candidate.type
        end
    end

    return earliest_pos, earliest_type
end

--- Expand 3-character hex color to 6-character format
---@param hex string 3 or 6 character hex string (without #)
---@return string Full hex color with # prefix
local function normalize_hex_color(hex)
    if #hex == 3 then
        return "#" .. hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end
    return "#" .. hex
end

--- Parse text into segments of plain text, action placeholders, color tags, and explicit key/button placeholders
---@param text string Text with placeholders like {jump}, {key:SPACE}, {button:SOUTH}, {keyboard:jump}, {gamepad:attack}, or [color=#RRGGBB]...[/color]
---@return table Array of {type="text"|"action"|"key"|"button"|"keyboard_action"|"gamepad_action"|"color_start"|"color_end", value=string|number}
local function parse_segments(text)
    local segments = {}
    local pos = 1

    while pos <= #text do
        local next_pos, next_type = find_earliest_tag({
            { pos = text:find("%[color=#", pos), type = "color_start" },
            { pos = text:find("%[/color%]", pos), type = "color_end" },
            { pos = text:find("{", pos), type = "brace" },
        })

        if not next_pos then
            -- No more tags, add remaining text
            if pos <= #text then
                table.insert(segments, { type = "text", value = text:sub(pos) })
            end
            break
        end

        -- Add text before the tag
        if next_pos > pos then
            table.insert(segments, { type = "text", value = text:sub(pos, next_pos - 1) })
        end

        if next_type == "color_start" then
            -- Match [color=#RGB] or [color=#RRGGBB], capture hex digits and position after ]
            local hex, tag_end = text:match("^%[color=#([%dA-Fa-f]+)%]()", next_pos)
            -- Support shorthand (#F00) and full (#FF0000) hex color notation
            if hex and (#hex == 6 or #hex == 3) then
                table.insert(segments, { type = "color_start", value = normalize_hex_color(hex) })
                pos = tag_end
            else
                table.insert(segments, { type = "text", value = "[" })
                pos = next_pos + 1
            end
        elseif next_type == "color_end" then
            table.insert(segments, { type = "color_end" })
            pos = next_pos + 8 -- length of "[/color]"
        else
            -- Handle brace placeholder
            local start_brace, end_brace, prefix, suffix = text:find("{([%w_]+):?([%w_]*)}", next_pos)
            if start_brace == next_pos then
                if suffix and suffix ~= "" then
                    if prefix == "key" then
                        local key_code = canvas.keys[suffix]
                        if key_code then
                            table.insert(segments, { type = "key", value = key_code })
                        else
                            table.insert(segments, { type = "text", value = suffix })
                        end
                    elseif prefix == "button" then
                        local button_code = canvas.buttons[suffix]
                        if button_code then
                            table.insert(segments, { type = "button", value = button_code })
                        else
                            table.insert(segments, { type = "text", value = suffix })
                        end
                    elseif prefix == "keyboard" then
                        table.insert(segments, { type = "keyboard_action", value = suffix })
                    elseif prefix == "gamepad" then
                        table.insert(segments, { type = "gamepad_action", value = suffix })
                    else
                        table.insert(segments, { type = "text", value = prefix .. ":" .. suffix })
                    end
                else
                    table.insert(segments, { type = "action", value = prefix })
                end
                pos = end_brace + 1
            else
                -- Lone brace, treat as text
                table.insert(segments, { type = "text", value = "{" })
                pos = next_pos + 1
            end
        end
    end

    return segments
end

--- Split text into lines and parse each line into segments
---@param text string Text with newlines and placeholders
---@return table Array of lines, each containing parsed segments
function TextDisplay.parse_lines(text)
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
        elseif segment.type == "color_start" or segment.type == "color_end" then
            -- Color tags have no width, skip
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
    local current_color = DEFAULT_TEXT_COLOR

    canvas.set_text_align("left")

    for _, segment in ipairs(segments) do
        if segment.type == "color_start" then
            current_color = segment.value
        elseif segment.type == "color_end" then
            current_color = DEFAULT_TEXT_COLOR
        elseif segment.type == "text" then
            canvas.set_color(current_color)
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

--- Get rendered dimensions for text
---@param text string Text with placeholders
---@return number width Maximum line width
---@return number height Total height including line spacing
function TextDisplay.get_dimensions(text)
    local lines = TextDisplay.parse_lines(text)
    local scheme = controls.get_last_input_device()

    canvas.set_font_family("menu_font")
    canvas.set_font_size(FONT_SIZE)

    local max_width = 0
    for _, segments in ipairs(lines) do
        local line_width = get_segments_width(segments, scheme)
        if line_width > max_width then
            max_width = line_width
        end
    end

    local num_lines = #lines
    local height = num_lines * FONT_SIZE + (num_lines - 1) * LINE_SPACING

    return max_width, height
end

--- Create a new TextDisplay instance
---@param text string Display text (can include {action_id} variables)
---@param options table|nil Optional settings {anchor = "top"|"bottom", offset_y = number}
---@return table TextDisplay instance
function TextDisplay.new(text, options)
    options = options or {}
    local self = {
        text = text,
        parsed_lines = TextDisplay.parse_lines(text),
        alpha = 0,
        anchor = options.anchor or "top",
        offset_y = options.offset_y or 0,
    }
    setmetatable(self, { __index = TextDisplay })
    return self
end

--- Update text display fade based on active state
---@param dt number Delta time in seconds
---@param is_active boolean Whether the display should be visible
function TextDisplay:update(dt, is_active)
    local target = is_active and 1 or 0
    local fade_rate = dt / FADE_DURATION
    if self.alpha < target then
        self.alpha = math.min(self.alpha + fade_rate, 1)
    elseif self.alpha > target then
        self.alpha = math.max(self.alpha - fade_rate, 0)
    end
end

--- Check if the display is currently visible
---@return boolean True if alpha > 0
function TextDisplay:is_visible()
    return self.alpha > 0
end

--- Set new text content
---@param text string New display text
function TextDisplay:set_text(text)
    self.text = text
    self.parsed_lines = TextDisplay.parse_lines(text)
end

--- Draw the text popup at the specified tile position
---@param tile_x number X position in tile coordinates
---@param tile_y number Y position in tile coordinates
---@param tile_w number|nil Width of the anchor tile (default 1)
---@param tile_h number|nil Height of the anchor tile (default 1)
function TextDisplay:draw(tile_x, tile_y, tile_w, tile_h)
    if self.alpha <= 0 then return end

    tile_w = tile_w or 1
    tile_h = tile_h or 1

    local tile_size = sprites.tile_size
    local screen_x = tile_x * tile_size
    local screen_y = tile_y * tile_size
    local scheme = controls.get_last_input_device()
    local lines = self.parsed_lines
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
    local content_height = num_lines * FONT_SIZE + (num_lines - 1) * LINE_SPACING
    local box_width = max_line_width + TEXT_PADDING * 2
    local box_height = content_height + TEXT_PADDING * 2

    local center_x = screen_x + (tile_w * tile_size) / 2
    local box_top

    if self.anchor == "bottom" then
        box_top = screen_y + tile_h * tile_size + self.offset_y
    else
        box_top = screen_y - box_height + self.offset_y
    end

    canvas.set_global_alpha(self.alpha)

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
        local line_y = box_top + TEXT_PADDING + i * FONT_SIZE + (i - 1) * LINE_SPACING
        draw_segments(segments, scheme, start_x, line_y)
    end

    canvas.set_global_alpha(1)
    canvas.set_text_align("left")
    canvas.set_text_baseline("alphabetic")
end

return TextDisplay
