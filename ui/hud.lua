--- In-game HUD elements: health, projectile selector, game over, rest screen, title screen, slot screen
local canvas = require("canvas")
local controls = require("controls")
local audio_dialog = require("ui/audio_dialog")
local controls_dialog = require("ui/controls_dialog")
local game_over = require("ui/game_over")
local rest_screen = require("ui/rest_screen")
local title_screen = require("ui/title_screen")
local slot_screen = require("ui/slot_screen")
local sprites = require("sprites")
local config = require("config")

local hud = {}

-- Player and camera references for pause screen
local player_ref = nil
local camera_ref = nil

canvas.assets.add_path("assets/")
canvas.assets.load_font("menu_font", "fonts/13px-sword.ttf")

--- Initialize HUD subsystems (game over screen, rest screen, title screen, slot screen, dialogs)
--- Must be called after audio.init() for volume settings to apply
---@return nil
function hud.init()
    audio_dialog.init()
    controls_dialog.init()
    game_over.init()
    rest_screen.init()
    title_screen.init()
    slot_screen.init()
end

--- Process HUD input for all overlay screens
--- Priority: audio dialog > controls dialog > pause/rest screen toggle > slot screen > title screen > game over > rest screen
---@return nil
function hud.input()
    -- Audio dialog blocks other input when open
    if audio_dialog.is_active() then
        audio_dialog.input()
        return
    end

    -- Controls dialog blocks other input when open
    if controls_dialog.is_active() then
        controls_dialog.input()
        return
    end

    -- Handle ESC/START for pause screen toggle
    if controls.settings_pressed() then
        if rest_screen.is_pause_mode() and not rest_screen.is_in_submenu() then
            -- Close pause screen (only if not in a submenu)
            rest_screen.trigger_continue()
        elseif not title_screen.is_active() and not slot_screen.is_active()
               and not game_over.is_active() and not rest_screen.is_active() then
            -- Open pause screen during gameplay
            rest_screen.show_pause(player_ref, camera_ref)
        end
    end

    -- Slot screen blocks other HUD input when active
    if slot_screen.is_active() then
        slot_screen.input()
        return
    end

    -- Title screen blocks other HUD input when active
    if title_screen.is_active() then
        title_screen.input()
        return
    end

    game_over.input()

    -- Rest screen input
    rest_screen.input()
end

--- Update all HUD overlay screens and handle mouse input blocking
--- Dialogs block mouse input for screens beneath them
---@param dt number Delta time in seconds
---@return nil
function hud.update(dt)
    audio_dialog.update(dt)
    controls_dialog.update(dt)
    -- Block mouse input on screens beneath active overlays
    local dialogs_block = audio_dialog.is_active() or controls_dialog.is_active()
    slot_screen.update(dt, dialogs_block)
    -- Title screen also blocked by slot screen
    local title_block = dialogs_block or slot_screen.is_active()
    title_screen.update(dt, title_block)
    game_over.update(dt)
    rest_screen.update(dt, dialogs_block)
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


--- Draw the currently selected projectile icon in the bottom-left HUD
---@param player table Player instance with projectile property
---@return nil
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
---@return nil
function hud.draw(player)
    -- Skip normal HUD when title screen or slot screen is active
    if not title_screen.is_active() and not slot_screen.is_active() then
        hud.draw_player_health(player)
        draw_selected_projectile(player)
    end
    game_over.draw()
    rest_screen.draw()
    title_screen.draw()
    slot_screen.draw()
    -- Dialogs drawn last so they appear on top of everything
    audio_dialog.draw()
    controls_dialog.draw()
end

--- Show the game over screen
---@return nil
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
---@param player table|nil Player instance for stats display
function hud.show_rest_screen(world_x, world_y, camera, player)
    rest_screen.show(world_x, world_y, camera, player)
end

--- Check if rest screen is blocking game input
---@return boolean is_active True if rest screen is visible
function hud.is_rest_screen_active()
    return rest_screen.is_active()
end

--- Check if pause mode is active (vs rest mode)
---@return boolean is_pause True if in pause mode
function hud.is_pause_mode()
    return rest_screen.is_pause_mode()
end

--- Set the continue callback for rest screen (reloads level from checkpoint)
---@param fn function Function to call when continuing from rest
function hud.set_rest_continue_callback(fn)
    rest_screen.set_continue_callback(fn)
end

--- Show the title screen
---@return nil
function hud.show_title_screen()
    title_screen.show()
end

--- Check if title screen is blocking game input
---@return boolean is_active True if title screen is visible
function hud.is_title_screen_active()
    return title_screen.is_active()
end

--- Hide the title screen
---@return nil
function hud.hide_title_screen()
    title_screen.hide()
end

--- Set the play game callback for title screen (opens slot screen)
---@param fn function Function to call when Play Game is selected
function hud.set_title_play_game_callback(fn)
    title_screen.set_play_game_callback(fn)
end

--- Set the audio callback for title screen
---@param fn function Function to call when Audio is selected
function hud.set_title_audio_callback(fn)
    title_screen.set_audio_callback(fn)
end

--- Set the controls callback for title screen
---@param fn function Function to call when Controls is selected
function hud.set_title_controls_callback(fn)
    title_screen.set_controls_callback(fn)
end

--- Show the slot selection screen
---@return nil
function hud.show_slot_screen()
    slot_screen.show()
end

--- Check if slot screen is blocking game input
---@return boolean is_active True if slot screen is visible
function hud.is_slot_screen_active()
    return slot_screen.is_active()
end

--- Set the slot selection callback
---@param fn function Function to call with slot_index when a slot is selected
function hud.set_slot_callback(fn)
    slot_screen.set_slot_callback(fn)
end

--- Set the player and camera references for pause screen
---@param player table Player instance
---@param camera table Camera instance
function hud.set_player(player, camera)
    player_ref = player
    camera_ref = camera
end

return hud
