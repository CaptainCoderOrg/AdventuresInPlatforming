local canvas = require("canvas")
local bump = require("bump")
local player = require("player")
local walls = require("walls")
local config = require("config")
local sprites = require("sprites")

-- Set canvas size
canvas.set_size(config.width * sprites.tile_size, config.height * sprites.tile_size)
canvas.set_image_smoothing(false)
-- Handle input
local function user_input()
	-- if canvas.keys.P then
	-- 	config.bounding_boxes = not config.bounding_boxes
	-- end
	player.input()
end

-- Update game state
local function update()
	player.update()
end

-- Render the game
local function draw()
	canvas.clear()
	player.draw()
	walls.draw()
end

local function init()
    for x = 0, config.width - 1 do 
        walls.create(x, 0) 
        walls.create(x, config.height - 1)
    end
    for y = 1, config.height - 2 do 
        walls.create(0, y)
        walls.create(config.width - 1, y)
    end
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
