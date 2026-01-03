local canvas = require("canvas")

local hud = {}

--- 9-slice drawing utility for scalable UI panels
local nine_slice = {}

--- Define a 9-slice from a sprite with specified border sizes
---@param sprite_name string Asset name
---@param sprite_w number Sprite width
---@param sprite_h number Sprite height
---@param left number Left border size
---@param top number Top border size
---@param right number Right border size
---@param bottom number Bottom border size
---@return table slice
function nine_slice.create(sprite_name, sprite_w, sprite_h, left, top, right, bottom)
    return {
        sprite = sprite_name,
        sprite_w = sprite_w,
        sprite_h = sprite_h,
        left = left,
        top = top,
        right = right,
        bottom = bottom,
    }
end

--- Draw a 9-slice scaled to fit the target dimensions
---@param slice table 9-slice definition
---@param x number X position
---@param y number Y position
---@param width number Target width
---@param height number Target height
---@param scale? number Border scale factor (default 1)
function nine_slice.draw(slice, x, y, width, height, scale)
    scale = scale or 1
    local sprite = slice.sprite

    local src_left = slice.left
    local src_top = slice.top
    local src_right = slice.right
    local src_bottom = slice.bottom
    local src_right_x = slice.sprite_w - src_right
    local src_bottom_y = slice.sprite_h - src_bottom
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

local settings_open = false
local settings_width = 300
local settings_height = 200
local dialogue_slice = nine_slice.create("dialogue_lg", 144, 144, 34, 18, 34, 20)

--- Process HUD input
function hud.input()
    if canvas.is_key_pressed(canvas.keys.ESCAPE) then
        settings_open = not settings_open
    end
end

--- Check if settings menu is blocking game input
---@return boolean
function hud.is_settings_open()
    return settings_open
end

local function draw_settings()
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()
    local x = (screen_w - settings_width) / 2
    local y = (screen_h - settings_height) / 2

    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)
    nine_slice.draw(dialogue_slice, x, y, settings_width, settings_height, 2)
end

--- Draw all HUD elements
function hud.draw()
    if settings_open then
        draw_settings()
    end
end

return hud
