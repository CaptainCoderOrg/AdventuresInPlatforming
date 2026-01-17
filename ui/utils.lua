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

--- Draw text with black outline and white fill
---@param text string Text to draw
---@param x number X position
---@param y number Y position
function utils.draw_outlined_text(text, x, y)
    canvas.set_color("#000000")
    canvas.set_line_width(3)
    canvas.stroke_text(x, y, text)
    canvas.set_color("#FFFFFF")
    canvas.draw_text(x, y, text)
end

return utils
