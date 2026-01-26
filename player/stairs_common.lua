--- Shared factory for stairs states (up and down variants)
local Animation = require('Animation')
local common = require('player.common')
local sprites = require('sprites')

local stairs_common = {}

--- Create a stairs state definition for the given variant
---@param variant "up"|"down" The stairs direction
---@return table state The state definition with start, input, update, draw functions
function stairs_common.create_state(variant)
    local state = { name = "stairs_" .. variant }

    local animation_def = Animation.create_definition(sprites.player[state.name], 7, {
        ms_per_frame = 100,
        width = 32,
        height = 32,
        loop = false
    })

    --- Called when entering stairs state. Sets animation and locks movement.
    ---@param player table The player object
    function state.start(player)
        player.animation = Animation.new(animation_def)
        player.direction = 1  -- Always face right for stairs animation
        player.vx = 0
        player.vy = 0
        player.stairs_transition_ready = false
    end

    --- Input is locked during stairs animation.
    ---@param player table The player object
    function state.input(player)
    end

    --- Updates stairs state. Checks if animation finished to trigger transition.
    ---@param player table The player object
    ---@param dt number Delta time in seconds
    function state.update(player, dt)
        player.vx = 0
        player.vy = 0

        if player.animation:is_finished() then
            player.stairs_transition_ready = true
        end
    end

    --- Renders the player at the stair position during animation.
    ---@param player table The player object
    function state.draw(player)
        if player.animation:is_finished() then return end
        if not player.stairs_target then return end

        local x = sprites.px(player.stairs_target.stair_x)
        local y = sprites.px(player.stairs_target.stair_y)
        player.animation:draw(x, y)
    end

    return state
end

return stairs_common
