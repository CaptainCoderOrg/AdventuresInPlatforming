--- Persistent state for bridges module.
--- Separated from init.lua so hot-swapping bridges.lua during development
--- doesn't clear existing bridges, allowing faster iteration.
---@class BridgesState
---@field tiles table<string, table> Bridge tiles by "x,y" key
---@field colliders table[] Array of bridge colliders
return {
    tiles = {},
    colliders = {}
}
