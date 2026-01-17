--- Settings menu overlay with volume controls
local canvas = require("canvas")
local slider = require("ui/slider")
local button = require("ui/button")
local nine_slice = require("ui/nine_slice")
local utils = require("ui/utils")
local audio = require("audio")
local config = require("config")

local settings_menu = {}

-- Base dimensions at 1x scale (will be scaled by canvas transform)
local base_width = 135
local base_height = 170
local slider_width = 100
local slider_height = 16
local button_width = 100
local button_height = 30

local dialogue_slice = nine_slice.create("dialogue_lg", 144, 144, 34, 18, 34, 20)

local fade_duration = 0.15
local fade_state = "closed"
local fade_progress = 0

local volume_sliders = {}

---@param slider_key string Key in volume_sliders table
---@param set_volume_fn function Volume setter (receives 0-1 value)
---@param on_change function|nil Optional callback after volume change
---@return function Input handler for slider
local function create_volume_callback(slider_key, set_volume_fn, on_change)
    return function(event)
        if event.type == "press" or event.type == "drag" then
            volume_sliders[slider_key]:set_value(event.normalized_x)
            set_volume_fn(volume_sliders[slider_key]:get_value())
            if on_change then on_change() end
        end
    end
end

volume_sliders.master = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#4488FF", value = 0.75, animate_speed = 0.1,
    on_input = create_volume_callback("master", canvas.set_master_volume)
})

volume_sliders.music = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#44FF88", value = 0.00, animate_speed = 0.1,
    on_input = create_volume_callback("music", audio.set_music_volume)
})

volume_sliders.sfx = slider.create({
    x = 0, y = 0, width = slider_width, height = slider_height,
    color = "#FF8844", value = 0.6, animate_speed = 0.1,
    on_input = create_volume_callback("sfx", audio.set_sfx_volume, audio.play_sound_check)
})

local close_button = button.create({
    x = 0, y = 0, width = button_width, height = button_height,
    label = "Close",
    on_click = function()
        fade_state = "fading_out"
    end
})

--- Apply initial volume settings (call after audio.init)
---@return nil
function settings_menu.init()
    canvas.set_master_volume(volume_sliders.master:get_value())
    audio.set_music_volume(volume_sliders.music:get_value())
    audio.set_sfx_volume(volume_sliders.sfx:get_value())
end

--- Process settings menu input (handles ESC key for toggle)
---@return nil
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
---@return nil
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
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local screen_h = canvas.get_height()

        -- Must match draw() positioning for correct mouse coordinate conversion
        local menu_x = (screen_w - base_width * scale) / 2
        local menu_y = (screen_h - base_height * scale) / 2

        -- Convert screen mouse to local 1x coordinates
        local local_mx = (canvas.get_mouse_x() - menu_x) / scale
        local local_my = (canvas.get_mouse_y() - menu_y) / scale

        for _, s in pairs(volume_sliders) do
            s:update(local_mx, local_my)
        end
        close_button:update(local_mx, local_my)
    end
end

--- Check if settings menu is blocking game input
---@return boolean
function settings_menu.is_open()
    return fade_state ~= "closed"
end

---@param text string Label text to draw
---@param center_x number Center X position
---@param y number Y position (baseline)
local function draw_centered_label(text, center_x, y)
    local metrics = canvas.get_text_metrics(text)
    local text_x = center_x - metrics.width / 2
    utils.draw_outlined_text(text, text_x, y)
end

--- Draw the settings menu overlay
---@return nil
function settings_menu.draw()
    if fade_state == "closed" then
        return
    end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - base_width * scale) / 2
    local menu_y = (screen_h - base_height * scale) / 2

    -- Draw background overlay (before transform, covers full screen)
    canvas.set_global_alpha(fade_progress)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Apply canvas transform for pixel-perfect scaling
    canvas.save()
    canvas.translate(menu_x, menu_y)
    canvas.scale(scale, scale)

    nine_slice.draw(dialogue_slice, 0, 0, base_width, base_height)

    -- Slider layout at 1x scale
    local slider_x = (base_width - slider_width) / 2
    local slider_center_x = slider_x + slider_width / 2
    local slider_start_y = 30
    local slider_spacing = 30
    local label_offset = 4

    canvas.set_font_family("menu_font")
    canvas.set_font_size(12)
    canvas.set_text_baseline("bottom")

    local slider_labels = {
        { label = "Master Volume", slider = volume_sliders.master },
        { label = "Music",         slider = volume_sliders.music },
        { label = "SFX",           slider = volume_sliders.sfx },
    }
    for i, item in ipairs(slider_labels) do
        local offset_y = slider_start_y + slider_spacing * (i - 1)
        draw_centered_label(item.label, slider_center_x, offset_y - label_offset + 5)
        item.slider.x = slider_x
        item.slider.y = offset_y
        item.slider:draw()
    end

    close_button.x = (base_width - close_button.width) / 2
    close_button.y = slider_start_y + slider_spacing * 3
    close_button:draw()

    canvas.restore()
    canvas.set_global_alpha(1)
end

return settings_menu
