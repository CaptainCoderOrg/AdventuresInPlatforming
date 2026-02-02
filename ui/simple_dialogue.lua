--- Simple dialogue box using 9-slice rendering
--- Supports keybinding placeholders like {action} that render as button/key sprites
local canvas = require("canvas")
local controls = require("controls")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")

local simple_dialogue = {}

-- 9-slice definition (76x37 sprite, borders: left=10, top=7, right=9, bottom=7)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Text configuration
local TEXT_PADDING_TOP = 7
local TEXT_PADDING_LEFT = 10
local TEXT_PADDING_RIGHT = 9
local LINE_HEIGHT = 8       -- pixels between lines
local FONT_SIZE = 8

-- Sprite scales for dialogue (no UI scale - sized to match 8px font)
local KEYBOARD_SCALE = 0.125      -- 64px * 0.125 = 8px
local KEYBOARD_WORD_SCALE = 0.15  -- 64px * 0.15 = ~10px for word keys
local GAMEPAD_SCALE = 0.5         -- 16px * 0.5 = 8px
local GAMEPAD_SHOULDER_SCALE = 0.6 -- 16px * 0.6 = ~10px for shoulder buttons

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

--- Create a new dialogue box instance with the given dimensions and text
---@param opts {x: number, y: number, width: number, height: number, text: string}
---@return table dialogue Dialogue instance for use with simple_dialogue.draw()
function simple_dialogue.create(opts)
    return {
        x = opts.x or 0,
        y = opts.y or 0,
        width = opts.width or 100,
        height = opts.height or 40,
        text = opts.text or "",
    }
end

--- Get the width of a word, accounting for keybinding placeholders (dialogue-scaled)
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

--- Draw a word with keybinding sprite support (dialogue-scaled)
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
            canvas.set_color("#FFFFFF")
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

--- Render a dialogue box with 9-slice background and word-wrapped text
--- Supports keybinding placeholders like {block} that render as button/key sprites
---@param dialogue table Dialogue instance created by simple_dialogue.create()
---@return nil
function simple_dialogue.draw(dialogue)
    nine_slice.draw(slice, dialogue.x, dialogue.y, dialogue.width, dialogue.height)

    local text_x = dialogue.x + TEXT_PADDING_LEFT
    local text_y = dialogue.y + TEXT_PADDING_TOP
    local max_width = dialogue.width - TEXT_PADDING_LEFT - TEXT_PADDING_RIGHT
    local scheme = controls.get_binding_scheme()

    canvas.set_font_family("menu_font")
    canvas.set_font_size(FONT_SIZE)
    canvas.set_text_baseline("bottom")
    canvas.set_color("#FFFFFF")

    -- Split text into lines first, then word-wrap each line
    local y_offset = 0
    for input_line in (dialogue.text .. "\n"):gmatch("([^\n]*)\n") do
        -- Empty lines create blank spacing
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
                    local draw_x = text_x
                    local draw_y = text_y + y_offset + FONT_SIZE
                    for i, w in ipairs(line_words) do
                        if i > 1 then
                            canvas.set_color("#FFFFFF")
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
                local draw_x = text_x
                local draw_y = text_y + y_offset + FONT_SIZE
                for i, w in ipairs(line_words) do
                    if i > 1 then
                        canvas.set_color("#FFFFFF")
                        canvas.draw_text(draw_x, draw_y, " ")
                        draw_x = draw_x + space_width
                    end
                    draw_x = draw_x + draw_word(w, scheme, draw_x, draw_y)
                end
                y_offset = y_offset + LINE_HEIGHT
            end
        end
    end

    -- Restore defaults
    canvas.set_text_baseline("alphabetic")
end

return simple_dialogue
