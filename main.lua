local canvas = require("canvas")
local player = require("player")
local walls = require("walls")
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
    walls.draw()
    player.draw()
    debug.draw()
    hud.draw()
end

local function init_walls()
    -- Phase 1: Collect tile positions
    for y, row in ipairs(level1.map) do
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch == "#" then
                walls.add_tile(x - 1, y - 1)
            elseif ch == 'S' then
                player.set_position(x - 1, y - 1)
            end
        end
    end
    -- Phase 2: Build merged colliders
    walls.build_colliders()
end

local function init()
    init_walls()
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
