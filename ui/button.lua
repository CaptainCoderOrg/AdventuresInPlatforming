--- Button UI component with 9-slice rendering, hover/click states
local canvas = require("canvas")

local button = {}
button.__index = button

local SPRITE_W = 100
local SPRITE_H = 35
local BORDER_LEFT = 13
local BORDER_RIGHT = 14
local BORDER_TOP = 8
local BORDER_BOTTOM = 9

local OFFSET_NORMAL = 0
local OFFSET_HOVER = -2
local OFFSET_PRESSED = 2

local function draw_nine_slice(sprite, x, y, width, height, scale)
    local src_left = BORDER_LEFT
    local src_top = BORDER_TOP
    local src_right = BORDER_RIGHT
    local src_bottom = BORDER_BOTTOM
    local src_right_x = SPRITE_W - src_right
    local src_bottom_y = SPRITE_H - src_bottom
    local src_center_w = src_right_x - src_left
    local src_center_h = src_bottom_y - src_top

    local dst_left = src_left * scale
    local dst_top = src_top * scale
    local dst_right = src_right * scale
    local dst_bottom = src_bottom * scale
    local dst_center_w = width - dst_left - dst_right
    local dst_center_h = height - dst_top - dst_bottom

    local function draw_region(sx, sy, sw, sh, dx, dy, dw, dh)
        if dw > 0 and dh > 0 and sw > 0 and sh > 0 then
            canvas.draw_image(sprite, dx, dy, dw, dh, sx, sy, sw, sh)
        end
    end

    draw_region(0,           0,            src_left,     src_top,      x,                           y,                          dst_left,     dst_top)
    draw_region(src_left,    0,            src_center_w, src_top,      x + dst_left,                y,                          dst_center_w, dst_top)
    draw_region(src_right_x, 0,            src_right,    src_top,      x + dst_left + dst_center_w, y,                          dst_right,    dst_top)

    draw_region(0,           src_top,      src_left,     src_center_h, x,                           y + dst_top,                dst_left,     dst_center_h)
    draw_region(src_left,    src_top,      src_center_w, src_center_h, x + dst_left,                y + dst_top,                dst_center_w, dst_center_h)
    draw_region(src_right_x, src_top,      src_right,    src_center_h, x + dst_left + dst_center_w, y + dst_top,                dst_right,    dst_center_h)

    draw_region(0,           src_bottom_y, src_left,     src_bottom,   x,                           y + dst_top + dst_center_h, dst_left,     dst_bottom)
    draw_region(src_left,    src_bottom_y, src_center_w, src_bottom,   x + dst_left,                y + dst_top + dst_center_h, dst_center_w, dst_bottom)
    draw_region(src_right_x, src_bottom_y, src_right,    src_bottom,   x + dst_left + dst_center_w, y + dst_top + dst_center_h, dst_right,    dst_bottom)
end

local function point_in_rect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Create a new button component
---@param opts {x: number, y: number, width: number, height: number, label: string, scale: number, on_click: function}
---@return table button
function button.create(opts)
    local self = setmetatable({}, button)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 100
    self.height = opts.height or 35
    self.label = opts.label or ""
    self.scale = opts.scale or 1
    self.on_click = opts.on_click
    self.state = "normal"
    return self
end

--- Update button state based on mouse input
function button:update()
    local mx = canvas.get_mouse_x()
    local my = canvas.get_mouse_y()
    local inside = point_in_rect(mx, my, self.x, self.y, self.width, self.height)

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
function button:draw()
    local y_offset = OFFSET_NORMAL
    if self.state == "hovered" then
        y_offset = OFFSET_HOVER
    elseif self.state == "pressed" then
        y_offset = OFFSET_PRESSED
    end

    local draw_y = self.y + y_offset

    draw_nine_slice("button", self.x, draw_y, self.width, self.height, self.scale)

    canvas.set_font_family("menu_font")
    canvas.set_font_size(26)
    canvas.set_text_baseline("middle")

    local metrics = canvas.get_text_metrics(self.label)
    local text_x = self.x + (self.width - metrics.width) / 2
    local text_y = draw_y + self.height / 2

    canvas.set_color("#000000")
    canvas.set_line_width(3)
    canvas.stroke_text(text_x, text_y, self.label)
    canvas.set_color("#FFFFFF")
    canvas.draw_text(text_x, text_y, self.label)
end

return button
