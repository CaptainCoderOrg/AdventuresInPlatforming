--- Persistent state for Prop system (hot reload safe)
--- This file is required once and its tables are preserved across hot reloads

return {
    types = {},           -- Registry preserved during hot reload
    all = {},             -- Object pool preserved during hot reload
    groups = {},          -- Group mappings preserved
    next_id = 1,          -- ID counter preserved
    global_draws = {},    -- Draw functions called every frame regardless of prop visibility
    accumulated_states = {},  -- Prop states accumulated across level transitions
}
