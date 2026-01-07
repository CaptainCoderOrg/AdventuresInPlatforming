local sprites = require('sprites')
local world = require('world')
local ladders = {}

ladders.tiles = {}

function ladders.add_ladder(x, y)
    local key = x .. "," .. y
    local ladder = { x = x, y = y, box = { x = 0, y = 0, w = 1, h = 1 }, is_ladder = true }
	ladders.tiles[key] = ladder
    world.add_trigger_collider(ladder)
    -- TODO: Add in collider for detecting if we can climb
end

function ladders.draw()
    for _, ladder in pairs(ladders.tiles) do
        sprites.draw_ladder(ladder.x * sprites.tile_size, ladder.y * sprites.tile_size)
    end
end

return ladders