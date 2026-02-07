--- Shared UI utilities
local canvas = require("canvas")

local utils = {}

--- Check if a point is inside a rectangle
---@param px number Point X
---@param py number Point Y
---@param x number Rectangle X
---@param y number Rectangle Y
---@param w number Rectangle width
---@param h number Rectangle height
---@return boolean
function utils.point_in_rect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Draw text with black outline and colored fill
---@param text string Text to draw
---@param x number X position
---@param y number Y position
---@param fill_color? string Fill color (default "#FFFFFF")
function utils.draw_outlined_text(text, x, y, fill_color)
    canvas.set_color("#000000")
    canvas.set_line_width(3)
    canvas.stroke_text(x, y, text)
    canvas.set_color(fill_color or "#FFFFFF")
    canvas.draw_text(x, y, text)
end

--- Wrap a value within a range (1 to max, cycling)
---@param value number Current value
---@param delta number Change amount (-1 or 1)
---@param max number Maximum value
---@return number Wrapped value
function utils.wrap(value, delta, max)
    return ((value - 1 + delta) % max) + 1
end

return utils
