--- Persistent state for Sign module.
--- Separated from init.lua so hot-swapping init.lua during development
--- doesn't clear existing signs, allowing faster iteration on visuals.
---@class SignState
---@field all table<table, boolean> Set of active Sign instances
---@field next_id number Auto-incrementing ID for new signs
return {
    all = {},
    next_id = 1
}
