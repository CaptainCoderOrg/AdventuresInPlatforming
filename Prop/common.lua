--- Shared utilities for prop definitions
local sprites = require("sprites")
local combat = require("combat")

local common = {}

--- Standard animation draw for props
---@param prop table Prop instance with animation
function common.draw(prop)
    if prop.animation then
        local px = prop.x * sprites.tile_size
        local py = prop.y * sprites.tile_size
        prop.animation:draw(px, py)
    end
end

--- Check if player is touching a prop
--- Uses combat system spatial indexing for efficient overlap detection
---@param prop table Prop instance with box
---@param player table Player instance with box
---@return boolean True if overlapping
function common.player_touching(prop, player)
    return combat.collides(prop, player)
end

return common
