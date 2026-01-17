--- Button UI component with 9-slice rendering, hover/click states
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")

local button = {}
button.__index = button

-- Offsets at 1x scale (canvas transform handles scaling)
local OFFSET_NORMAL = 0
local OFFSET_HOVER = -1
local OFFSET_PRESSED = 1

local button_slice = nine_slice.create("button", 100, 35, 14, 9, 14, 9)

--- Create a new button component
---@param opts {x: number, y: number, width: number, height: number, label: string, on_click: function}
---@return table button
function button.create(opts)
    local self = setmetatable({}, button)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 100
    self.height = opts.height or 35
    self.label = opts.label or ""
    self.on_click = opts.on_click
    self.state = "normal"
    return self
end

--- Update button state based on mouse input
---@param mx number Mouse X in local coordinates (from parent)
---@param my number Mouse Y in local coordinates (from parent)
function button:update(mx, my)
    local inside = utils.point_in_rect(mx, my, self.x, self.y, self.width, self.height)

    if inside then
        if canvas.is_mouse_down(0) then
            self.state = "pressed"
        else
            self.state = "hovered"
        end

        if canvas.is_mouse_pressed(0) and self.on_click then
            self.on_click()
        end
    else
        self.state = "normal"
    end
end

--- Draw the button with state-based y-offset
---@param focused? boolean Whether this button is focused (draws overlay)
function button:draw(focused)
    -- Use hover state when focused (for visual lift effect)
    local effective_state = focused and "hovered" or self.state

    local y_offset = OFFSET_NORMAL
    if effective_state == "hovered" then
        y_offset = OFFSET_HOVER
    elseif effective_state == "pressed" then
        y_offset = OFFSET_PRESSED
    end

    local draw_y = self.y + y_offset

    nine_slice.draw(button_slice, self.x, draw_y, self.width, self.height)

    canvas.set_font_family("menu_font")
    canvas.set_font_size(9)
    canvas.set_text_baseline("middle")

    local metrics = canvas.get_text_metrics(self.label)
    local text_x = self.x + (self.width - metrics.width) / 2
    local text_y = draw_y + self.height / 2

    if focused then
        utils.draw_outlined_text(self.label, text_x, text_y, "#FFFF00")
    else
        utils.draw_outlined_text(self.label, text_x, text_y)
    end
end

return button
