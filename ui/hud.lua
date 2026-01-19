--- In-game HUD elements: health, projectile selector, game over, settings overlay, rest screen
local canvas = require("canvas")
local settings_menu = require("ui/settings_menu")
local game_over = require("ui/game_over")
local rest_screen = require("ui/rest_screen")
local sprites = require("sprites")
local config = require("config")

local hud = {}

canvas.assets.add_path("assets/")
canvas.assets.load_font("menu_font", "fonts/13px-sword.ttf")

--- Initialize HUD subsystems (settings menu, game over screen, rest screen)
--- Must be called after audio.init() for volume settings to apply
function hud.init()
    settings_menu.init()
    game_over.init()
    rest_screen.init()
end

--- Process HUD input
function hud.input()
    settings_menu.input()
    game_over.input()
    rest_screen.input()
end

--- Advance settings menu animations
---@param dt number Delta time in seconds
function hud.update(dt)
    settings_menu.update()
    game_over.update(dt)
    rest_screen.update(dt)
end

--- Check if settings menu is blocking game input
---@return boolean is_open True if settings menu is currently visible
function hud.is_settings_open()
    return settings_menu.is_open()
end

--- Draw player health hearts
---@param player table Player instance with health() method and max_health property
function hud.draw_player_health(player)
    local heart_size = 64
    local damage_size = 40
    local damage_off = (heart_size - damage_size) / 2
    local spacing_x = 64 + 4
    local off_x = canvas.get_width() - (player.max_health * spacing_x)
    local off_y = canvas.get_height() - 84
    for ix = 1, player:health() do
        canvas.draw_image(sprites.ui.heart, off_x + (ix - 1) * spacing_x, off_y, heart_size, heart_size)
    end
    for ix = player:health() + 1, player.max_health do
        canvas.draw_image(sprites.ui.heart, damage_off + off_x + (ix - 1) * spacing_x, damage_off + off_y, damage_size, damage_size)
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
---@param player table Player instance with health() method, max_health, and projectile properties
function hud.draw(player)
    hud.draw_player_health(player)
    draw_selected_projectile(player)
    settings_menu.draw()
    game_over.draw()
    rest_screen.draw()
end

--- Show the game over screen
function hud.show_game_over()
    game_over.show()
end

--- Check if game over screen is blocking game input
---@return boolean is_active True if game over is visible
function hud.is_game_over_active()
    return game_over.is_active()
end

--- Set the continue callback for game over (uses restore point)
---@param fn function Function to call when continuing from checkpoint
function hud.set_continue_callback(fn)
    game_over.set_continue_callback(fn)
end

--- Set the restart callback for game over (full restart)
---@param fn function Function to call when restarting
function hud.set_restart_callback(fn)
    game_over.set_restart_callback(fn)
end

--- Show the rest screen centered on a campfire
---@param world_x number Campfire center X in tile coordinates
---@param world_y number Campfire center Y in tile coordinates
---@param camera table Camera instance for position calculation
function hud.show_rest_screen(world_x, world_y, camera)
    rest_screen.show(world_x, world_y, camera)
end

--- Check if rest screen is blocking game input
---@return boolean is_active True if rest screen is visible
function hud.is_rest_screen_active()
    return rest_screen.is_active()
end

--- Set the continue callback for rest screen (reloads level from checkpoint)
---@param fn function Function to call when continuing from rest
function hud.set_rest_continue_callback(fn)
    rest_screen.set_continue_callback(fn)
end

return hud
