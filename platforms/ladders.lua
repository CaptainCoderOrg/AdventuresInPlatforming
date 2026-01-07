local sprites = require('sprites')
local world = require('world')
local ladders = {}

ladders.tiles = {}

function ladders.add_ladder(x, y)
    local key = x .. "," .. y
    local ladder = { x = x, y = y, box = { x = 0, y = 0, w = 1, h = 1 }, is_ladder = true }
	ladders.tiles[key] = ladder
    world.add_trigger_collider(ladder)
end

function ladders.build_colliders()
    -- Find all "top" ladder tiles (no ladder directly above)
    for key, ladder in pairs(ladders.tiles) do
        local above_key = ladder.x .. "," .. (ladder.y - 1)
        if not ladders.tiles[above_key] then
            -- This is a top ladder tile - add a thin solid collider at top
            local top_collider = {
                x = ladder.x,
                y = ladder.y,
                box = { x = 0, y = 0, w = 1, h = 0.2 },
                is_ladder_top = true,
                ladder = ladder  -- Reference to the ladder below
            }
            ladder.is_top = true
            world.add_collider(top_collider)
        end
    end
end

function ladders.draw()
    for _, ladder in pairs(ladders.tiles) do
        sprites.draw_ladder(ladder.x * sprites.tile_size, ladder.y * sprites.tile_size)
    end
end

return ladders