--- Persistent state for proximity audio system (hot reload safe)
--- HC world for spatial hashing of audio emitters

local HC = require('hc')

-- 200px cell size (larger than combat's 100px) for audio radii (3-5 tiles = 144-240px)
local CELL_SIZE = 200

return {
    world = HC.new(CELL_SIZE),  -- HC world for spatial queries
    emitters = {},               -- emitter -> config mapping
    shapes = {},                 -- emitter -> HC shape mapping
    cell_size = CELL_SIZE,
    cached_results = nil,        -- Query results cache (nil = invalid)
    query_point = nil,           -- Persistent query point shape (avoids allocations)
    query_results = {},          -- Reusable results array
    result_pool = {},            -- Pool of reusable entry tables
    result_pool_idx = 0          -- Current index into pool
}
