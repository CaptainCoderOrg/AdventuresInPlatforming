local canvas = require("canvas")
local Player = require("player")
local platforms = require("platforms")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local level1 = require("levels/level1")
local debug = require("debugger")
local hud = require("ui/hud")
local Projectile = require("Projectile")
local Effects = require("Effects")
local Camera = require("Camera")

local player  -- Instance created in init_level
local camera  -- Camera instance created in init_level
local level_info  -- Level dimensions from loaded level

-- Set canvas size
canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
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
    player:input()
end

-- Update game state
local function update()
    if hud.is_settings_open() then
        return
    end
    local dt = canvas.get_delta()
    if dt > 0.5 then dt = 0.5 end
    camera:update(sprites.tile_size, dt, 0.3)
    player:update(dt)
    Projectile.update(dt)
    Effects.update(dt)
end

-- Render the game
local function draw()
    canvas.clear()

    -- Draw world-space entities (affected by camera)
    canvas.save()
    camera:apply_transform(sprites.tile_size)
    platforms.draw(camera)
    player:draw()
    Projectile.draw()
    Effects.draw()
    canvas.restore()

    -- Draw screen-space UI (not affected by camera)
    debug.draw(player)
    hud.draw(player)
end

local function init_level()
    player = Player.new()
    level_info = platforms.load_level(level1)
    if level_info.spawn then
        player:set_position(level_info.spawn.x, level_info.spawn.y)
    end
    platforms.build()

    -- Initialize camera after player
    camera = Camera.new(
        config.ui.canvas_width,   -- Viewport width in pixels
        config.ui.canvas_height,  -- Viewport height in pixels
        level_info.width,         -- World width in tiles (from level)
        level_info.height         -- World height in tiles (from level)
    )
    camera:set_target(player)
    camera:set_look_ahead(3, 2, 0.05, 0.03)
end

local function init()
    init_level()
end

local started = false

local function on_start()
    if started then return end
    audio.init()
    hud.init()
    audio.play_music(audio.level1)
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
