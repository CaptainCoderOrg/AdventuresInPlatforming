--- Combat hitbox system - Spatial indexing for combat hit detection
--- Separate from physics collision (world.lua) for clean separation of concerns
local HC = require('hc')
local sprites = require('sprites')

local combat = {}

-- Separate HC world for combat (100px cell size for larger combat hitboxes)
combat.world = HC.new(100)

combat.shapes = {}

--- Add an entity to the combat world
---@param entity table Entity with x, y, box properties
---@return table The created HC shape
function combat.add(entity)
    local ts = sprites.tile_size
    local px = (entity.x + entity.box.x) * ts
    local py = (entity.y + entity.box.y) * ts
    local pw = entity.box.w * ts
    local ph = entity.box.h * ts

    local shape = combat.world:rectangle(px, py, pw, ph)
    shape.owner = entity
    combat.shapes[entity] = shape
    return shape
end

--- Remove an entity from the combat world
---@param entity table The entity to remove
function combat.remove(entity)
    local shape = combat.shapes[entity]
    if shape then
        combat.world:remove(shape)
        combat.shapes[entity] = nil
    end
end

--- Update an entity's combat hitbox position
---@param entity table Entity with x, y, box properties
---@param y_offset number|nil Optional Y offset in pixels (for slope rotation)
function combat.update(entity, y_offset)
    local shape = combat.shapes[entity]
    if not shape then return end

    local ts = sprites.tile_size
    local px = (entity.x + entity.box.x) * ts
    local py = (entity.y + entity.box.y) * ts + (y_offset or 0)

    -- Move shape to new position
    local old_x, old_y, _, _ = shape:bbox()
    local dx = px - old_x
    local dy = py - old_y
    shape:move(dx, dy)

    -- Apply rotation if entity has slope_rotation (negate to match visual)
    if entity.slope_rotation then
        local cx = px + (entity.box.w * ts / 2)
        local cy = py + (entity.box.h * ts / 2)
        shape:setRotation(-entity.slope_rotation, cx, cy)
    end
end

--- Query for entities overlapping a rectangular area
--- Uses spatial hashing for O(1) average lookup
---@param x number X position in tiles
---@param y number Y position in tiles
---@param w number Width in tiles
---@param h number Height in tiles
---@param filter function|nil Optional filter(entity) -> boolean. Entity has .is_enemy, .type_key, .box, .shape, etc.
---@return table Array of matching entities
function combat.query_rect(x, y, w, h, filter)
    local ts = sprites.tile_size
    local temp = combat.world:rectangle(x * ts, y * ts, w * ts, h * ts)
    local collisions = combat.world:collisions(temp)
    combat.world:remove(temp)

    local results = {}
    for other, _ in pairs(collisions) do
        if other.owner and (not filter or filter(other.owner)) then
            table.insert(results, other.owner)
        end
    end
    return results
end

--- Check if two entities in the combat world are colliding
---@param entity1 table First entity
---@param entity2 table Second entity
---@return boolean True if colliding
function combat.collides(entity1, entity2)
    local shape1 = combat.shapes[entity1]
    local shape2 = combat.shapes[entity2]
    if not shape1 or not shape2 then return false end

    local collides_result, _ = shape1:collidesWith(shape2)
    return collides_result
end

--- Clear all entities from the combat world
function combat.clear()
    for _, shape in pairs(combat.shapes) do
        combat.world:remove(shape)
    end
    combat.shapes = {}
    combat.world = HC.new(100)
end

return combat
