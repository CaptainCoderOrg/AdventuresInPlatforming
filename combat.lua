--- Combat hitbox system - Spatial indexing for combat hit detection
--- Separate from physics collision (world.lua) for clean separation of concerns
local HC = require('hc')
local sprites = require('sprites')

local combat = {}

-- Separate HC world for combat (100px cell size for larger combat hitboxes)
combat.world = HC.new(100)

combat.shapes = {}
combat.shields = {}

-- Persistent query shape to avoid per-frame allocations in query_rect
local query_shape = nil
local query_shape_size = { w = 0, h = 0 }

-- Persistent shield query shape
local shield_query_shape = nil
local shield_query_size = { w = 0, h = 0 }

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
--- Uses a persistent query shape to avoid allocations (recreated only on size change)
---@param x number X position in tiles
---@param y number Y position in tiles
---@param w number Width in tiles
---@param h number Height in tiles
---@param filter function|nil Optional filter(entity) -> boolean. Entity has .is_enemy, .type_key, .box, .shape, etc.
---@param out table|nil Optional output table to reuse (avoids allocation)
---@return table Array of matching entities
function combat.query_rect(x, y, w, h, filter, out)
    local ts = sprites.tile_size
    local px, py = x * ts, y * ts
    local pw, ph = w * ts, h * ts

    -- Lazy-init or recreate if size changed
    if not query_shape or query_shape_size.w ~= pw or query_shape_size.h ~= ph then
        if query_shape then
            combat.world:remove(query_shape)
        end
        query_shape = combat.world:rectangle(px, py, pw, ph)
        query_shape.is_query = true
        query_shape_size.w = pw
        query_shape_size.h = ph
    else
        -- moveTo uses center coordinates, not top-left
        query_shape:moveTo(px + pw/2, py + ph/2)
    end

    local collisions = combat.world:collisions(query_shape)

    local results
    if out then
        for i = 1, #out do out[i] = nil end
        results = out
    else
        results = {}
    end

    local count = 0
    for other, _ in pairs(collisions) do
        if not other.is_query and other.owner and (not filter or filter(other.owner)) then
            count = count + 1
            results[count] = other.owner
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

--- Clears all entities from the combat world.
--- Recreates the HC world instance and resets the persistent query shape.
---@return nil
function combat.clear()
    for _, shape in pairs(combat.shapes) do
        combat.world:remove(shape)
    end
    for _, shape in pairs(combat.shields) do
        combat.world:remove(shape)
    end
    combat.shapes = {}
    combat.shields = {}
    combat.world = HC.new(100)
    -- Reset persistent query shapes (invalidated by world recreation)
    query_shape = nil
    query_shape_size = { w = 0, h = 0 }
    shield_query_shape = nil
    shield_query_size = { w = 0, h = 0 }
end

--- Add a shield to the combat world
---@param owner table The owning entity (e.g., enemy)
---@param x number X position in tiles
---@param y number Y position in tiles
---@param w number Width in tiles
---@param h number Height in tiles
---@return table The created HC shape
function combat.add_shield(owner, x, y, w, h)
    local ts = sprites.tile_size
    local px, py = x * ts, y * ts
    local pw, ph = w * ts, h * ts

    local shape = combat.world:rectangle(px, py, pw, ph)
    shape.owner = owner
    shape.is_shield = true
    combat.shields[owner] = shape
    return shape
end

--- Update a shield's position in the combat world
---@param owner table The owning entity
---@param x number X position in tiles
---@param y number Y position in tiles
---@param w number Width in tiles
---@param h number Height in tiles
function combat.update_shield(owner, x, y, w, h)
    local shape = combat.shields[owner]
    if not shape then return end

    local ts = sprites.tile_size
    local px, py = x * ts, y * ts
    local pw, ph = w * ts, h * ts

    -- Check if size changed (requires recreate) vs just position change
    local x1, y1, x2, y2 = shape:bbox()
    local old_w, old_h = x2 - x1, y2 - y1

    if math.abs(old_w - pw) > 0.001 or math.abs(old_h - ph) > 0.001 then
        -- Size changed: must recreate shape
        combat.world:remove(shape)
        local new_shape = combat.world:rectangle(px, py, pw, ph)
        new_shape.owner = owner
        new_shape.is_shield = true
        combat.shields[owner] = new_shape
    else
        -- Position only: move existing shape
        shape:moveTo(px + pw / 2, py + ph / 2)
    end
end

--- Remove a shield from the combat world
---@param owner table The owning entity
function combat.remove_shield(owner)
    local shape = combat.shields[owner]
    if shape then
        combat.world:remove(shape)
        combat.shields[owner] = nil
    end
end

--- Check if a rectangular area overlaps any shield
--- Uses spatial hashing for O(1) average lookup
---@param x number X position in tiles
---@param y number Y position in tiles
---@param w number Width in tiles
---@param h number Height in tiles
---@return table|nil Shield owner if blocked, nil otherwise
---@return number|nil Shield center X in tiles
---@return number|nil Shield center Y in tiles
function combat.check_shield_block(x, y, w, h)
    local ts = sprites.tile_size
    local px, py = x * ts, y * ts
    local pw, ph = w * ts, h * ts

    -- Lazy-init or recreate if size changed
    if not shield_query_shape or shield_query_size.w ~= pw or shield_query_size.h ~= ph then
        if shield_query_shape then
            combat.world:remove(shield_query_shape)
        end
        shield_query_shape = combat.world:rectangle(px, py, pw, ph)
        shield_query_shape.is_query = true
        shield_query_size.w = pw
        shield_query_size.h = ph
    else
        -- moveTo uses center coordinates
        shield_query_shape:moveTo(px + pw/2, py + ph/2)
    end

    local collisions = combat.world:collisions(shield_query_shape)

    for other, _ in pairs(collisions) do
        if other.is_shield and other.owner then
            -- Return shield center position in tiles
            local sx1, sy1, sx2, sy2 = other:bbox()
            local shield_cx = (sx1 + sx2) / 2 / ts
            local shield_cy = (sy1 + sy2) / 2 / ts
            return other.owner, shield_cx, shield_cy
        end
    end
    return nil
end

return combat
