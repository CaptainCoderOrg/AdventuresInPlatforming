--- 9-slice drawing utility for scalable UI panels
local canvas = require("canvas")

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
---@param src_y? number Source Y offset for sprite sheet rows (default 0)
function nine_slice.draw(slice, x, y, width, height, src_y)
    src_y = src_y or 0

    local src_left = slice.left
    local src_top = slice.top
    local src_right = slice.right
    local src_bottom = slice.bottom
    local src_right_x = slice.sprite_w - src_right
    local src_bottom_y = slice.sprite_h - src_bottom
    local src_center_w = src_right_x - src_left
    local src_center_h = src_bottom_y - src_top

    local dst_center_w = width - src_left - src_right
    local dst_center_h = height - src_top - src_bottom

    local function draw_region(sx, sy, sw, sh, dx, dy, dw, dh)
        if dw > 0 and dh > 0 and sw > 0 and sh > 0 then
            canvas.draw_image(slice.sprite, dx, dy, dw, dh, sx, src_y + sy, sw, sh)
        end
    end

    draw_region(0,           0,            src_left,     src_top,      x,                            y,                           src_left,     src_top)
    draw_region(src_left,    0,            src_center_w, src_top,      x + src_left,                 y,                           dst_center_w, src_top)
    draw_region(src_right_x, 0,            src_right,    src_top,      x + src_left + dst_center_w,  y,                           src_right,    src_top)

    draw_region(0,           src_top,      src_left,     src_center_h, x,                            y + src_top,                 src_left,     dst_center_h)
    draw_region(src_left,    src_top,      src_center_w, src_center_h, x + src_left,                 y + src_top,                 dst_center_w, dst_center_h)
    draw_region(src_right_x, src_top,      src_right,    src_center_h, x + src_left + dst_center_w,  y + src_top,                 src_right,    dst_center_h)

    draw_region(0,           src_bottom_y, src_left,     src_bottom,   x,                            y + src_top + dst_center_h,  src_left,     src_bottom)
    draw_region(src_left,    src_bottom_y, src_center_w, src_bottom,   x + src_left,                 y + src_top + dst_center_h,  dst_center_w, src_bottom)
    draw_region(src_right_x, src_bottom_y, src_right,    src_bottom,   x + src_left + dst_center_w,  y + src_top + dst_center_h,  src_right,    src_bottom)
end

return nine_slice
