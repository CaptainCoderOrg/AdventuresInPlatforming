--- Spike trap prop that damages the player and teleports them to their last safe position
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local Animation = require("Animation")

local SpikeTrap = {}
SpikeTrap.all = {}  -- Object pool

-- Animation definition: 6 frames, 16x16, static (no playback for now)
local EXTENDED = Animation.create_definition(sprites.environment.spikes, 6, {
    ms_per_frame = 100,
    width = 16,
    height = 16,
    loop = false
})

--- Check if player is touching a spike trap (overlapping bounding boxes)
---@param trap table SpikeTrap instance
---@param player table Player instance
---@return boolean True if player overlaps trap tile
local function player_touching(trap, player)
    local px, py = player.x + player.box.x, player.y + player.box.y
    local pw, ph = player.box.w, player.box.h
    local sx, sy = trap.x, trap.y
    local sw, sh = 1, 1  -- trap is 1x1 tile

    return px < sx + sw and px + pw > sx and
           py < sy + sh and py + ph > sy
end

--- Create a new spike trap at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@return table SpikeTrap instance
function SpikeTrap.new(x, y)
    local self = {
        x = x,
        y = y,
        animation = Animation.new(EXTENDED, { start_frame = 0 }),
    }
    -- Pause animation since we're static on frame 0 (extended)
    self.animation:pause()

    table.insert(SpikeTrap.all, self)
    return self
end

--- Update all spike traps (check player overlap and apply damage/teleport)
---@param dt number Delta time in seconds
---@param player table Player instance
function SpikeTrap.update(dt, player)
    for _, trap in ipairs(SpikeTrap.all) do
        -- Only check collision if player is alive and not invincible
        if player_touching(trap, player) and not player:is_invincible() and player:health() > 0 then
            -- Deal damage (triggers hit state, respects invincibility)
            player:take_damage(1)

            -- Teleport to last safe position if still alive
            if player:health() > 0 then
                player:set_position(player.last_safe_position.x, player.last_safe_position.y)
                player.vx = 0
                player.vy = 0
            end
        end
    end
end

--- Draw all spike traps
function SpikeTrap.draw()
    local tile_size = sprites.tile_size

    for _, trap in ipairs(SpikeTrap.all) do
        local screen_x = trap.x * tile_size
        local screen_y = trap.y * tile_size
        trap.animation:draw(screen_x, screen_y)

        if config.bounding_boxes then
            canvas.set_color("#FF00FF")  -- Magenta for spike traps
            canvas.draw_rect(screen_x, screen_y, tile_size, tile_size)
        end
    end
end

--- Remove all spike traps (for level reload)
function SpikeTrap.clear()
    SpikeTrap.all = {}
end

return SpikeTrap
