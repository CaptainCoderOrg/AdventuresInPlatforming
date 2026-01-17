--- In-game HUD elements: health, projectile selector, game over, settings overlay
local canvas = require("canvas")
local settings_menu = require("ui/settings_menu")
local sprites = require("sprites")
local config = require("config")

local hud = {}

canvas.assets.add_path("assets/")
canvas.assets.load_font("menu_font", "fonts/13px-sword.ttf")

--- Apply initial volume settings (call after audio.init)
function hud.init()
    settings_menu.init()
end

--- Process HUD input
function hud.input()
    settings_menu.input()
end

--- Advance settings menu animations
function hud.update()
    settings_menu.update()
end

--- Check if settings menu is blocking game input
---@return boolean
function hud.is_settings_open()
    return settings_menu.is_open()
end

--- Draw player health hearts
---@param player table
function hud.draw_player_health(player)
    local heart_size = 64
    local damage_size = 40
    local damage_off = (heart_size - damage_size) / 2
    local spacing_x = 64 + 4
    local off_x = canvas.get_width() - (player.max_health * spacing_x)
    local off_y = canvas.get_height() - 84
    for ix = 1, player:health() do
        canvas.draw_image(sprites.HEART, off_x + (ix - 1) * spacing_x, off_y, heart_size, heart_size)
    end
    for ix = player:health() + 1, player.max_health do
        canvas.draw_image(sprites.HEART, damage_off + off_x + (ix - 1) * spacing_x, damage_off + off_y, damage_size, damage_size)
    end
end

local function draw_game_over(player)
    if player.is_dead then
        canvas.set_font_family("menu_font")
        canvas.set_font_size(52)
        canvas.set_text_baseline("middle")
        canvas.set_text_align("center")
        local x = canvas.get_width() / 2
        local y = canvas.get_height() / 2
        canvas.set_color("#472727ff")
        canvas.draw_text(x + 2, y + 2, "GAME OVER", {})
        canvas.set_color("#ebe389ff")
        canvas.draw_text(x, y, "GAME OVER", {})
        canvas.set_text_align("left")
    end
end

local function draw_selected_projectile(player)
    local scale = config.ui.SCALE
    canvas.save()
    canvas.set_global_alpha(0.9)
    canvas.translate(8, canvas.get_height() - 24*scale - 8)
    canvas.scale(scale, scale)
    canvas.draw_image(sprites.ui.small_circle_ui, 0, 0)
    canvas.translate(8, 8)
    canvas.draw_image(player.projectile.sprite, 0, 0, 8, 8, 0, 0, 8, 8)
    canvas.restore()
end

--- Draw all HUD elements
---@param player table
function hud.draw(player)
    hud.draw_player_health(player)
    draw_selected_projectile(player)
    draw_game_over(player)
    settings_menu.draw()
end

return hud
