local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local walls = {}

walls.all = {}

function walls.create(x, y) 
    local wall = {
        x = x,
        y = y,
    }
    table.insert(walls.all, wall)
end

function walls.draw()
    for _, wall in pairs(walls.all) do
        sprites.draw_tile(4, 3, wall.x * sprites.tile_size, wall.y * sprites.tile_size)
        if config.bounding_boxes == true then
            canvas.set_color("#00ff1179")
            canvas.draw_rect(wall.x * sprites.tile_size, wall.y * sprites.tile_size, sprites.tile_size, sprites.tile_size)
        end
    end
end

return walls