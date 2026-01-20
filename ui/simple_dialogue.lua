--- Simple dialogue box using 9-slice rendering
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")

local simple_dialogue = {}

-- 9-slice definition (76x37 sprite, borders: left=10, top=7, right=9, bottom=7)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Text configuration
local TEXT_PADDING_TOP = 7
local TEXT_PADDING_LEFT = 10
local TEXT_PADDING_RIGHT = 9
local LINE_HEIGHT = 8       -- pixels between lines

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

--- Render a dialogue box with 9-slice background and word-wrapped text
---@param dialogue table Dialogue instance created by simple_dialogue.create()
---@return nil
function simple_dialogue.draw(dialogue)
    nine_slice.draw(slice, dialogue.x, dialogue.y, dialogue.width, dialogue.height)

    local text_x = dialogue.x + TEXT_PADDING_LEFT
    local text_y = dialogue.y + TEXT_PADDING_TOP
    local max_width = dialogue.width - TEXT_PADDING_LEFT - TEXT_PADDING_RIGHT

    canvas.set_font_family("menu_font")
    canvas.set_font_size(8)
    canvas.set_text_baseline("top")
    canvas.set_color("#FFFFFF")

    -- Split text into lines first, then word-wrap each line
    -- Pattern appends \n to ensure final line is captured, then matches each line
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

            local line = ""
            for _, word in ipairs(words) do
                local test_line = line == "" and word or (line .. " " .. word)
                local metrics = canvas.get_text_metrics(test_line)
                if metrics.width > max_width and line ~= "" then
                    canvas.draw_text(text_x, text_y + y_offset, line)
                    y_offset = y_offset + LINE_HEIGHT
                    line = word
                else
                    line = test_line
                end
            end
            if line ~= "" then
                canvas.draw_text(text_x, text_y + y_offset, line)
                y_offset = y_offset + LINE_HEIGHT
            end
        end
    end
end

return simple_dialogue
