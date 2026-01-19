--- Shared utilities for prop definitions
local sprites = require("sprites")

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

--- Check if player is touching a prop (AABB overlap)
---@param prop table Prop instance with box
---@param player table Player instance with box
---@return boolean True if overlapping
function common.player_touching(prop, player)
    local px = player.x + player.box.x
    local py = player.y + player.box.y
    local pw = player.box.w
    local ph = player.box.h

    local bx = prop.x + prop.box.x
    local by = prop.y + prop.box.y
    local bw = prop.box.w
    local bh = prop.box.h

    return px < bx + bw and px + pw > bx and
           py < by + bh and py + ph > by
end

return common
