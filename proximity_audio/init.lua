--- Proximity audio system - Spatial indexing for distance-based audio
--- Uses HC spatial hashing for O(1) average emitter queries

local canvas = require('canvas')
local HC = require('hc')
local sprites = require('sprites')
local state = require('proximity_audio/state')
local falloff = require('proximity_audio/falloff')

local proximity_audio = {}

-- Expose state for external access (hot reload)
proximity_audio.emitters = state.emitters
proximity_audio.shapes = state.shapes

local CONFIG_DEFAULTS = {
    sound_id = "unknown",
    radius = 4,
    max_volume = 1.0,
    falloff = "smooth",
    inner_radius = 0.5
}

--- Convert tile position to pixel center coordinates
---@param tile_x number X position in tiles
---@param tile_y number Y position in tiles
---@return number, number Pixel center coordinates
local function tile_to_pixel_center(tile_x, tile_y)
    local ts = sprites.tile_size
    return (tile_x + 0.5) * ts, (tile_y + 0.5) * ts
end

--- Register a sound emitter
---@param emitter table Entity with x, y position in tiles
---@param config {sound_id: string, radius: number, max_volume: number, falloff: string, inner_radius: number}|nil Configuration (all fields optional with defaults)
function proximity_audio.register(emitter, config)
    config = config or {}
    for key, default in pairs(CONFIG_DEFAULTS) do
        if config[key] == nil then
            config[key] = default
        end
    end

    local cx, cy = tile_to_pixel_center(emitter.x, emitter.y)
    local radius_px = config.radius * sprites.tile_size

    local shape = state.world:circle(cx, cy, radius_px)
    shape.owner = emitter

    state.emitters[emitter] = config
    state.shapes[emitter] = shape
end

--- Remove an emitter from the system
---@param emitter table The emitter to remove
function proximity_audio.remove(emitter)
    local shape = state.shapes[emitter]
    if shape then
        state.world:remove(shape)
        state.shapes[emitter] = nil
        state.emitters[emitter] = nil
    end
end

--- Update emitter position (for moving sound sources)
---@param emitter table Entity with x, y position in tiles
function proximity_audio.update_position(emitter)
    local shape = state.shapes[emitter]
    if not shape then return end

    local cx, cy = tile_to_pixel_center(emitter.x, emitter.y)
    shape:moveTo(cx, cy)
end

--- Calculate volume for a given distance
---@param distance number Distance in tiles
---@param config table Emitter config
---@return number Volume (0 to max_volume)
local function calculate_volume(distance, config)
    -- Full volume within inner radius
    if distance <= config.inner_radius then
        return config.max_volume
    end

    -- No volume beyond outer radius
    if distance >= config.radius then
        return 0
    end

    local t = (distance - config.inner_radius) / (config.radius - config.inner_radius)

    local falloff_fn = falloff[config.falloff] or falloff.smooth
    return config.max_volume * falloff_fn(t)
end

--- Query nearby emitters and calculate volumes
---@param x number Query X position in tiles
---@param y number Query Y position in tiles
---@return table Array of {emitter, distance, volume, config}
function proximity_audio.query(x, y)
    local px, py = tile_to_pixel_center(x, y)

    -- HC requires a shape for collision queries; 1px circle approximates a point
    local point = state.world:circle(px, py, 1)
    local collisions = state.world:collisions(point)
    state.world:remove(point)

    local results = {}
    for shape, _ in pairs(collisions) do
        local emitter = shape.owner
        if emitter then
            local config = state.emitters[emitter]
            if config then
                local dx = x - emitter.x
                local dy = y - emitter.y
                local distance = math.sqrt(dx * dx + dy * dy)

                local volume = calculate_volume(distance, config)
                if volume > 0 then
                    table.insert(results, {
                        emitter = emitter,
                        distance = distance,
                        volume = volume,
                        config = config
                    })
                end
            end
        end
    end

    return results
end

--- Invalidate cache (call at start of each frame)
---@return nil
function proximity_audio.invalidate_cache()
    state.cached_results = nil
end

--- Get cached results, querying if needed
--- NOTE: Cache assumes single query position per frame (player). Calling with
--- different coordinates after cache is populated returns stale results.
---@param x number Query X position in tiles
---@param y number Query Y position in tiles
---@return table Array of {emitter, distance, volume, config}
function proximity_audio.get_cached(x, y)
    if state.cached_results then
        return state.cached_results
    end
    state.cached_results = proximity_audio.query(x, y)
    return state.cached_results
end

--- Check if a specific emitter is in range of a position
---@param x number Query X position in tiles
---@param y number Query Y position in tiles
---@param emitter table Emitter to check for
---@return boolean True if emitter is in range
function proximity_audio.is_in_range(x, y, emitter)
    local results = proximity_audio.get_cached(x, y)
    for _, result in ipairs(results) do
        if result.emitter == emitter then
            return true
        end
    end
    return false
end

--- Clear all emitters (for level cleanup)
---@return nil
function proximity_audio.clear()
    for _, shape in pairs(state.shapes) do
        state.world:remove(shape)
    end
    state.emitters = {}
    state.shapes = {}
    state.cached_results = nil
    state.world = HC.new(state.cell_size)

    -- Update module references
    proximity_audio.emitters = state.emitters
    proximity_audio.shapes = state.shapes
end

--- Draw debug visualization for audio emitter radii
---@return nil
function proximity_audio.draw_debug()
    for emitter, config in pairs(state.emitters) do
        local cx, cy = tile_to_pixel_center(emitter.x, emitter.y)
        local radius_px = config.radius * sprites.tile_size
        canvas.draw_circle(cx, cy, radius_px, "#FF00FF")
    end
end

return proximity_audio
