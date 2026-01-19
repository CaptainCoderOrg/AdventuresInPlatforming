--- Button prop that can be placed in levels and activated by hammer
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local Animation = require("Animation")

local Button = {}
Button.all = {}

-- Animation definition: 5 frames, 16x8 (half tile height)
-- Frame 0 = extended/unpressed, Frame 4 = fully pressed
local UNPRESSED = Animation.create_definition(sprites.environment.button, 5, {
    ms_per_frame = 100,
    width = 16,
    height = 8,
    loop = false
})

-- Button hitbox dimensions (in tiles)
local BOX = {
    x = 0,
    y = 0.5,  -- Offset to bottom half of tile
    w = 1.0,
    h = 0.5   -- Half tile height
}

--- Create a new button at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return table Button instance
function Button.new(x, y)
    local self = {
        x = x,
        y = y,
        box = BOX,
        is_pressed = false,
        animation = Animation.new(UNPRESSED, { start_frame = 0 }),
    }
    -- Pause animation since we're static on frame 0 (unpressed)
    self.animation:pause()

    table.insert(Button.all, self)
    return self
end

--- Press the button, starting the press animation
---@param button table Button instance
local function press(button)
    if button.is_pressed then return end
    button.is_pressed = true
    button.animation:resume()
end

--- Check if a hitbox overlaps with any unpressed button and press it
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@return boolean True if a button was pressed
function Button.check_hit(hitbox)
    if not hitbox then return false end

    for _, button in ipairs(Button.all) do
        if not button.is_pressed then
            local bx = button.x + button.box.x
            local by = button.y + button.box.y
            local bw = button.box.w
            local bh = button.box.h

            -- AABB overlap check
            if hitbox.x < bx + bw and hitbox.x + hitbox.w > bx and
               hitbox.y < by + bh and hitbox.y + hitbox.h > by then
                press(button)
                return true
            end
        end
    end
    return false
end

--- Update all buttons (plays animation for pressed buttons)
---@param dt number Delta time in seconds
function Button.update(dt)
    for _, button in ipairs(Button.all) do
        if button.is_pressed then
            button.animation:play(dt)
        end
    end
end

--- Draw all buttons
function Button.draw()
    local tile_size = sprites.tile_size

    for _, button in ipairs(Button.all) do
        local screen_x = button.x * tile_size
        -- Offset Y by half tile since sprite is 8px (sits at bottom of tile)
        local screen_y = (button.y + 0.5) * tile_size
        button.animation:draw(screen_x, screen_y)

        if config.bounding_boxes then
            canvas.set_color("#00FF00")
            canvas.draw_rect(screen_x, screen_y, tile_size, tile_size / 2)
        end
    end
end

--- Remove all buttons (for level reload)
function Button.clear()
    Button.all = {}
end

return Button
