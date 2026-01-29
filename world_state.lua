--- Persistent state for world/collision module.
--- Separated from world.lua so hot-swapping world.lua during development
--- doesn't clear collision data, allowing faster iteration.
local HC = require('hc')
local sprites = require('sprites')

---@class WorldState
---@field hc table HC collision instance
---@field shape_map table<table, table> Maps game objects to their HC shapes
---@field trigger_map table<table, table> Maps game objects to their trigger shapes
---@field hitbox_map table<table, table> Maps game objects to their combat hitboxes
---@field projectile_collider_map table<table, table> Maps objects to projectile-blocking colliders
---@field ground_probe table|nil Persistent probe shape for point_has_ground queries
return {
    -- Initialize HC with spatial hash cell size (50 tiles * tile_size in pixels)
    hc = HC:new(50 * sprites.tile_size),
    -- Maps game objects to their HC shapes (physics collisions)
    shape_map = {},
    -- Maps game objects to their HC trigger shapes
    trigger_map = {},
    -- Maps game objects to their combat hitboxes (for hit detection, can rotate)
    hitbox_map = {},
    -- Maps players to their shield colliders (for blocking projectiles/attacks)
    shield_map = {},
    -- Maps objects to projectile-blocking colliders (blocks projectiles without taking damage)
    projectile_collider_map = {},
    -- Persistent probe shape for point_has_ground queries (lazy-initialized)
    ground_probe = nil
}
