--- Campfire prop with animated flame effect
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local Animation = require("Animation")

local Campfire = {}
Campfire.all = require("Campfire.state")

local CAMPFIRE = Animation.create_definition(sprites.environment.campfire, 5, {
    ms_per_frame = 160,
    width = 16,
    height = 80,
    loop = true
})

-- Campfire hitbox dimensions (in tiles)
local BOX = {
    x = 0,
    y = 0,
    w = 1,
    h = 1,
}

--- Create a new campfire at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return table Campfire instance
function Campfire.new(x, y)
    local self = {
        x = x,
        y = y,
        box = BOX,
        animation = Animation.new(CAMPFIRE, { start_frame = 0 }),
    }

    table.insert(Campfire.all, self)
    return self
end

--- Check if a hitbox overlaps with any campfire
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@return boolean True if overlapping a campfire
function Campfire.check_hit(hitbox)
    if not hitbox then return false end

    for _, campfire in ipairs(Campfire.all) do
        local bx = campfire.x + campfire.box.x
        local by = campfire.y + campfire.box.y
        local bw = campfire.box.w
        local bh = campfire.box.h

        if hitbox.x < bx + bw and hitbox.x + hitbox.w > bx and
            hitbox.y < by + bh and hitbox.y + hitbox.h > by then
            return true
        end
    end
    return false
end

--- Update all campfires (plays animation)
---@param dt number Delta time in seconds
function Campfire.update(dt)
    for _, campfire in ipairs(Campfire.all) do
        campfire.animation:play(dt)
    end
end

--- Renders all campfires to the screen.
--- Converts tile coordinates to screen pixels and draws debug hitboxes when enabled.
function Campfire.draw()
    local tile_size = sprites.tile_size

    for _, campfire in ipairs(Campfire.all) do
        local screen_x = campfire.x * tile_size
        local screen_y = campfire.y * tile_size
        campfire.animation:draw(screen_x, screen_y)

        if config.bounding_boxes then
            canvas.set_color("#FFA500")
            canvas.draw_rect(screen_x, screen_y, tile_size, tile_size)
        end
    end
end

--- Remove all campfires (for level reload)
function Campfire.clear()
    for i = #Campfire.all, 1, -1 do
        Campfire.all[i] = nil
    end
end

return Campfire
