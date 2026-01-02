local canvas = require("canvas")
local bump = require("bump")
local player = require("player")
local walls = require("walls")
local config = require("config")
local sprites = require("sprites")
local level1 = require("levels/level1")
local debug = require("debugger")

-- Set canvas size
canvas.set_size(config.width * sprites.tile_size, config.height * sprites.tile_size)
canvas.set_image_smoothing(false)
-- Handle input
local function user_input()
    if canvas.is_key_pressed(canvas.keys.P) then
        config.bounding_boxes = not config.bounding_boxes
        config.debug = not config.debug
    end
	player.input()
end

-- Update game state
local function update()
	player.update()
end

-- Render the game
local function draw()
	canvas.clear()
	walls.draw()
	player.draw()
    debug.draw()
end

local function init_walls()
    for y, row in ipairs(level1.map) do
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch == "#" then
                walls.create(x - 1, y - 1)
            elseif ch == 'S' then
                player.set_position(x - 1, y - 1)
            end
        end
        -- print(ix)
    end
end

local function init()
    init_walls()
end

-- Main game loop
local function game()
	user_input()
	update()
	draw()
end

init()
-- Register and start
canvas.tick(game)
canvas.start()
