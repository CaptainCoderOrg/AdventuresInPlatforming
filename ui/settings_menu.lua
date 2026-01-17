--- Settings menu overlay with volume controls
local canvas = require("canvas")
local slider = require("ui/slider")
local button = require("ui/button")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")
local audio = require("audio")

local settings_menu = {}

local settings_width = 300
local settings_height = 310
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
    color = "#44FF88", value = 0.00, scale = 2, animate_speed = 0.1,
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

local close_button = button.create({
    x = 0, y = 0, width = 100, height = 35,
    label = "Close", scale = 1,
    on_click = function()
        fade_state = "fading_out"
    end
})

--- Apply initial volume settings (call after audio.init)
function settings_menu.init()
    canvas.set_master_volume(volume_sliders.master:get_value())
    audio.set_music_volume(volume_sliders.music:get_value())
    audio.set_sfx_volume(volume_sliders.sfx:get_value())
end

--- Process settings menu input
function settings_menu.input()
    if canvas.is_key_pressed(canvas.keys.ESCAPE) then
        if fade_state == "closed" or fade_state == "fading_out" then
            fade_state = "fading_in"
        elseif fade_state == "open" or fade_state == "fading_in" then
            fade_state = "fading_out"
        end
    end
end

--- Advance fade animation and update controls
function settings_menu.update()
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
        close_button:update()
    end
end

--- Check if settings menu is blocking game input
---@return boolean
function settings_menu.is_open()
    return fade_state ~= "closed"
end

local function draw_centered_label(text, center_x, y)
    local metrics = canvas.get_text_metrics(text)
    local text_x = center_x - metrics.width / 2
    utils.draw_outlined_text(text, text_x, y)
end

--- Draw the settings menu overlay
function settings_menu.draw()
    if fade_state == "closed" then
        return
    end

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

    local slider_labels = {
        { label = "Master Volume", slider = volume_sliders.master },
        { label = "Music",         slider = volume_sliders.music },
        { label = "SFX",           slider = volume_sliders.sfx },
    }
    for i, item in ipairs(slider_labels) do
        local offset_y = slider_start_y + slider_spacing * (i - 1)
        draw_centered_label(item.label, slider_center_x, offset_y - label_offset + 16)
        item.slider.x = slider_x
        item.slider.y = offset_y
        item.slider:draw()
    end

    close_button.x = x + (settings_width - close_button.width) / 2
    close_button.y = slider_start_y + slider_spacing * 3
    close_button:draw()

    canvas.set_global_alpha(1)
end

return settings_menu
