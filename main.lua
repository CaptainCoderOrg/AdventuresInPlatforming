local canvas = require("canvas")
local player = require("player")
local platforms = require("platforms")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local level1 = require("levels/level1")
local debug = require("debugger")
local hud = require("ui/hud")

-- Set canvas size
canvas.set_size(config.width * sprites.tile_size, config.height * sprites.tile_size)
canvas.set_image_smoothing(false)
-- Handle input
local function user_input()
    hud.input()

    if hud.is_settings_open() then
        return
    end

    if canvas.is_key_pressed(canvas.keys.P) then
        config.bounding_boxes = not config.bounding_boxes
        config.debug = not config.debug
    elseif canvas.is_key_pressed(canvas.keys.DIGIT_1) then
        audio.play_music(audio.level1)
    elseif canvas.is_key_pressed(canvas.keys.DIGIT_2) then
        audio.play_music(audio.title_screen)
    end
    player.input()
end

-- Update game state
local function update()
    if hud.is_settings_open() then
        return
    end
    player.update()
end

-- Render the game
local function draw()
    canvas.clear()
    platforms.draw()
    player.draw()
    debug.draw()
    hud.draw()
end

local function init_level()
    local spawn = platforms.load_level(level1)
    if spawn then
        player.set_position(spawn.x, spawn.y)
    end
    platforms.build()
end

local function init()
    init_level()
end

local started = false

local function on_start()
    if started then return end
    audio.init()
    hud.init()
    audio.play_music(audio.title_screen)
    started = true
end



-- Main game loop
local function game()
    on_start()
    audio.update()
    hud.update()
    user_input()
    update()
    draw()
end

init()
-- Register and start
canvas.tick(game)
canvas.start()
