local canvas = require("canvas")
local slider = require("slider")
local audio = require("audio")

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

local settings_width = 300
local settings_height = 260
local dialogue_slice = nine_slice.create("dialogue_lg", 144, 144, 34, 18, 34, 20)

local fade_duration = 0.15
local fade_state = "closed"
local fade_progress = 0

local volume_sliders = {}

volume_sliders.master = slider.create({
    x = 0, y = 0, width = 200, height = 24,
    color = "#4488FF", value = 0.75, scale = 2, animate_speed = 0.1,
    on_input = function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders.master:set_value(event.normalized_x)
            canvas.set_master_volume(volume_sliders.master:get_value())
        end
    end
})

volume_sliders.music = slider.create({
    x = 0, y = 0, width = 200, height = 24,
    color = "#44FF88", value = 0.4, scale = 2, animate_speed = 0.1,
    on_input = function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders.music:set_value(event.normalized_x)
            audio.set_music_volume(volume_sliders.music:get_value())
        end
    end
})

volume_sliders.sfx = slider.create({
    x = 0, y = 0, width = 200, height = 24,
    color = "#FF8844", value = 0.6, scale = 2, animate_speed = 0.1,
    on_input = function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders.sfx:set_value(event.normalized_x)
            audio.set_sfx_volume(volume_sliders.sfx:get_value())
            audio.play_sound_check()
        end
    end
})

--- Apply initial volume settings (call after audio.init)
function hud.init()
    canvas.set_master_volume(volume_sliders.master:get_value())
    audio.set_music_volume(volume_sliders.music:get_value())
    audio.set_sfx_volume(volume_sliders.sfx:get_value())
end

--- Process HUD input
function hud.input()
    if canvas.is_key_pressed(canvas.keys.ESCAPE) then
        if fade_state == "closed" or fade_state == "fading_out" then
            fade_state = "fading_in"
        elseif fade_state == "open" or fade_state == "fading_in" then
            fade_state = "fading_out"
        end
    end
end

--- Advance fade animation and update sliders
function hud.update()
    local dt = canvas.get_delta()
    local speed = dt / fade_duration

    if fade_state == "fading_in" then
        fade_progress = math.min(1, fade_progress + speed)
        if fade_progress >= 1 then
            fade_state = "open"
        end
    elseif fade_state == "fading_out" then
        fade_progress = math.max(0, fade_progress - speed)
        if fade_progress <= 0 then
            fade_state = "closed"
        end
    end

    if fade_state == "open" then
        for _, s in pairs(volume_sliders) do
            s:update()
        end
    end
end

--- Check if settings menu is blocking game input
---@return boolean
function hud.is_settings_open()
    return fade_state ~= "closed"
end

local function draw_centered_label(text, center_x, y)
    local metrics = canvas.get_text_metrics(text)
    local text_x = center_x - metrics.width / 2
    canvas.set_color("#000000")
    canvas.set_line_width(3)
    canvas.stroke_text(text_x, y, text)
    canvas.set_color("#FFFFFF")
    canvas.draw_text(text_x, y, text)
end

local function draw_settings()
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()
    local x = (screen_w - settings_width) / 2
    local y = (screen_h - settings_height) / 2

    canvas.set_global_alpha(fade_progress)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)
    nine_slice.draw(dialogue_slice, x, y, settings_width, settings_height, 2)

    local slider_width = 200
    local slider_x = x + (settings_width - slider_width) / 2
    local slider_center_x = slider_x + slider_width / 2
    local slider_start_y = y + 61
    local slider_spacing = 52
    local label_offset = 18

    canvas.set_font_family("menu_font")
    canvas.set_font_size(26)
    canvas.set_text_baseline("bottom")

    draw_centered_label("Master Volume", slider_center_x, slider_start_y - label_offset + 16)
    volume_sliders.master.x = slider_x
    volume_sliders.master.y = slider_start_y
    volume_sliders.master:draw()

    draw_centered_label("Music", slider_center_x, slider_start_y + slider_spacing - label_offset + 16)
    volume_sliders.music.x = slider_x
    volume_sliders.music.y = slider_start_y + slider_spacing
    volume_sliders.music:draw()

    draw_centered_label("SFX", slider_center_x, slider_start_y + slider_spacing * 2 - label_offset + 16)
    volume_sliders.sfx.x = slider_x
    volume_sliders.sfx.y = slider_start_y + slider_spacing * 2
    volume_sliders.sfx:draw()

    canvas.set_global_alpha(1)
end

--- Draw all HUD elements
function hud.draw()
    if fade_state ~= "closed" then
        draw_settings()
    end
end

return hud
