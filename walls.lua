local canvas = require('canvas')
local sprites = require('sprites')
local config = require('config')
local world = require('world')
local walls = {}

walls.tiles = {}
walls.colliders = {}
walls.tile_to_collider = {}

--- @param tile_lookup table<string, {x: number, y: number}>
--- @return {x: number, y: number}[]
local function get_sorted_tiles(tile_lookup)
    local sorted = {}
    for _, tile in pairs(tile_lookup) do
        table.insert(sorted, tile)
    end
    table.sort(sorted, function(a, b)
        if a.x == b.x then return a.y < b.y end
        return a.x < b.x
    end)
    return sorted
end

--- Merges adjacent tiles into larger collision boxes.
--- @param tile_lookup table<string, {x: number, y: number}>
--- @param sorted_tiles {x: number, y: number}[]
--- @return table[]
local function merge_tiles_into_colliders(tile_lookup, sorted_tiles)
    local merged = {}
    local vertical_colliders = {}

    for _, tile in ipairs(sorted_tiles) do
        local key = tile.x .. "," .. tile.y
        if not merged[key] then
            local run_tiles = { tile }
            merged[key] = true

            local next_y = tile.y + 1
            local next_key = tile.x .. "," .. next_y
            while tile_lookup[next_key] and not merged[next_key] do
                table.insert(run_tiles, tile_lookup[next_key])
                merged[next_key] = true
                next_y = next_y + 1
                next_key = tile.x .. "," .. next_y
            end

            table.insert(vertical_colliders, {
                x = tile.x,
                y = tile.y,
                box = { x = 0, y = 0, w = 1, h = #run_tiles },
                tiles = run_tiles
            })
        end
    end

    local groups = {}
    for _, col in ipairs(vertical_colliders) do
        local key = col.y .. "," .. col.box.h
        groups[key] = groups[key] or {}
        table.insert(groups[key], col)
    end

    local result = {}
    for _, group in pairs(groups) do
        table.sort(group, function(a, b) return a.x < b.x end)

        local i = 1
        while i <= #group do
            local start_col = group[i]
            local merged_tiles = {}
            for _, t in ipairs(start_col.tiles) do
                table.insert(merged_tiles, t)
            end
            local total_width = start_col.box.w
            local j = i + 1

            while j <= #group and group[j].x == start_col.x + total_width do
                for _, t in ipairs(group[j].tiles) do
                    table.insert(merged_tiles, t)
                end
                total_width = total_width + group[j].box.w
                j = j + 1
            end

            table.insert(result, {
                x = start_col.x,
                y = start_col.y,
                box = { x = 0, y = 0, w = total_width, h = start_col.box.h },
                tiles = merged_tiles
            })

            i = j
        end
    end

    return result
end

--- @param colliders table[]
local function register_colliders(colliders)
    for _, col in ipairs(colliders) do
        table.insert(walls.colliders, col)
        world.add_collider(col)
        for _, t in ipairs(col.tiles) do
            walls.tile_to_collider[t.x .. "," .. t.y] = col
        end
    end
end

--- Adds a tile position to be merged later.
--- @param x number
--- @param y number
function walls.add_tile(x, y)
    local key = x .. "," .. y
    walls.tiles[key] = { x = x, y = y }
end

--- Builds merged collision boxes from all added tiles.
function walls.build_colliders()
    local sorted = get_sorted_tiles(walls.tiles)
    local colliders = merge_tiles_into_colliders(walls.tiles, sorted)
    register_colliders(colliders)
end

--- Removes a tile and re-merges affected colliders.
--- @param x number
--- @param y number
--- @return boolean success
function walls.remove_tile(x, y)
    local key = x .. "," .. y
    local tile = walls.tiles[key]
    if not tile then return false end

    local collider = walls.tile_to_collider[key]
    if not collider then return false end

    walls.tiles[key] = nil
    walls.tile_to_collider[key] = nil
    world.remove_collider(collider)

    for i, c in ipairs(walls.colliders) do
        if c == collider then
            table.remove(walls.colliders, i)
            break
        end
    end

    local temp_lookup = {}
    for _, t in ipairs(collider.tiles) do
        local tk = t.x .. "," .. t.y
        if tk ~= key then
            temp_lookup[tk] = t
            walls.tile_to_collider[tk] = nil
        end
    end

    if next(temp_lookup) then
        local sorted = get_sorted_tiles(temp_lookup)
        local new_colliders = merge_tiles_into_colliders(temp_lookup, sorted)
        register_colliders(new_colliders)
    end

    return true
end

--- Draws all wall tiles and debug bounding boxes.
function walls.draw()
    for _, tile in pairs(walls.tiles) do
        sprites.draw_tile(4, 3, tile.x * sprites.tile_size, tile.y * sprites.tile_size)
    end

    if config.bounding_boxes then
        canvas.set_color("#00ff1179")
        for _, col in pairs(walls.colliders) do
            canvas.draw_rect(
                col.x * sprites.tile_size,
                col.y * sprites.tile_size,
                col.box.w * sprites.tile_size,
                col.box.h * sprites.tile_size
            )
        end
    end
end

return walls
