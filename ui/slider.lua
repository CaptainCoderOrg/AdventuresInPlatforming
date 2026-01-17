--- Slider UI component with 9-slice rendering, animated fill, and input handling
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")

local slider = {}
slider.__index = slider

local HIT_LEFT = 10
local HIT_RIGHT = 11

local slider_slice = nine_slice.create("slider", 96, 16, 16, 3, 16, 4)

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
    local inside = utils.point_in_rect(mx, my, self.x, self.y, self.width, self.height)

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

    nine_slice.draw(slider_slice, self.x, self.y, self.width, self.height, scale, 0)

    local fill_left = HIT_LEFT * scale
    local fill_top = slider_slice.top * scale
    local fill_right = HIT_RIGHT * scale
    local fill_bottom = slider_slice.bottom * scale
    local fill_max_w = self.width - fill_left - fill_right
    local fill_h = self.height - fill_top - fill_bottom
    local fill_w = fill_max_w * self.display_value

    if fill_w > 0 and fill_h > 0 then
        canvas.set_color(self.color)
        canvas.fill_rect(self.x + fill_left, self.y + fill_top, fill_w, fill_h)
    end

    nine_slice.draw(slider_slice, self.x, self.y, self.width, self.height, scale, 16)
end

return slider
