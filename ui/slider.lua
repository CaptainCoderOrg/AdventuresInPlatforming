--- Slider UI component with 9-slice rendering, animated fill, and input handling
local canvas = require("canvas")

local slider = {}
slider.__index = slider

local SPRITE_W = 96
local SPRITE_H = 16
local BORDER_LEFT = 16
local BORDER_RIGHT = 16
local BORDER_TOP = 3
local BORDER_BOTTOM = 4
local HIT_LEFT = 10
local HIT_RIGHT = 11

--- Draw a 9-slice from a sprite sheet row
local function draw_nine_slice(sprite, src_y, x, y, width, height, scale)
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
            canvas.draw_image(sprite, dx, dy, dw, dh, sx, src_y + sy, sw, sh)
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

--- Create a new slider component
---@param opts {x: number, y: number, width: number, height: number, color: string, value: number, scale: number, animate_speed: number, on_input: function}
---@return table slider
function slider.create(opts)
    local self = setmetatable({}, slider)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 100
    self.height = opts.height or 32
    self.color = opts.color or "#FFFFFF"
    self.scale = opts.scale or 1
    self.value = opts.value or 0
    self.display_value = self.value
    self.animate_duration = opts.animate_speed or 0
    self.anim_start = self.value
    self.anim_elapsed = 0
    self.on_input = opts.on_input
    self.dragging = false
    return self
end

--- Set the slider's target value
---@param v number Value between 0 and 1
function slider:set_value(v)
    local new_value = math.max(0, math.min(1, v))
    if new_value ~= self.value then
        self.anim_start = self.display_value
        self.anim_elapsed = 0
        self.value = new_value
    end
end

---@return number value Current target value (0-1)
function slider:get_value()
    return self.value
end

local function point_in_rect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Update slider animation and handle mouse input
function slider:update()
    local dt = canvas.get_delta()

    if self.animate_duration == 0 then
        self.display_value = self.value
    else
        self.anim_elapsed = self.anim_elapsed + dt
        local t = math.min(1, self.anim_elapsed / self.animate_duration)
        self.display_value = self.anim_start + (self.value - self.anim_start) * t
    end

    local mx = canvas.get_mouse_x()
    local my = canvas.get_mouse_y()
    local inside = point_in_rect(mx, my, self.x, self.y, self.width, self.height)

    local local_x = mx - self.x
    local local_y = my - self.y

    local hit_start = HIT_LEFT * self.scale
    local hit_end = self.width - HIT_RIGHT * self.scale
    local hit_width = hit_end - hit_start
    local normalized_x = math.max(0, math.min(1, (local_x - hit_start) / hit_width))

    if canvas.is_mouse_pressed(0) and inside then
        self.dragging = true
        if self.on_input then
            self.on_input({
                type = "press",
                x = local_x,
                y = local_y,
                normalized_x = normalized_x
            })
        end
    end

    if self.dragging then
        if canvas.is_mouse_down(0) then
            if self.on_input then
                self.on_input({
                    type = "drag",
                    x = local_x,
                    y = local_y,
                    normalized_x = normalized_x
                })
            end
        else
            self.dragging = false
            if self.on_input then
                self.on_input({
                    type = "release",
                    x = local_x,
                    y = local_y,
                    normalized_x = normalized_x
                })
            end
        end
    end
end

--- Draw the slider (background, fill, border)
function slider:draw()
    local scale = self.scale

    draw_nine_slice("slider", 0, self.x, self.y, self.width, self.height, scale)

    local fill_left = HIT_LEFT * scale
    local fill_top = BORDER_TOP * scale
    local fill_right = HIT_RIGHT * scale
    local fill_bottom = BORDER_BOTTOM * scale
    local fill_max_w = self.width - fill_left - fill_right
    local fill_h = self.height - fill_top - fill_bottom
    local fill_w = fill_max_w * self.display_value

    if fill_w > 0 and fill_h > 0 then
        canvas.set_color(self.color)
        canvas.fill_rect(self.x + fill_left, self.y + fill_top, fill_w, fill_h)
    end

    draw_nine_slice("slider", 16, self.x, self.y, self.width, self.height, scale)
end

return slider
