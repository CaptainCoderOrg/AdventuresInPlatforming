--- Trap door prop definition - Collapsing platform with 4-state cycle
--- States: closed -> opening -> open -> resetting -> closed
local Animation = require("Animation")
local combat = require("combat")
local prop_common = require("Prop/common")
local Prop = require("Prop")
local sprites = require("sprites")
local world = require("world")

-- Animation definitions (32x16 per frame)
local TRAP_DOOR_CLOSED = Animation.create_definition(sprites.environment.trap_door, 1, {
    ms_per_frame = 1000,
    width = 32,
    height = 16,
    loop = false
})

local TRAP_DOOR_OPEN = Animation.create_definition(sprites.environment.trap_door_open, 9, {
    width = 32,
    height = 16,
    loop = false
})

local TRAP_DOOR_RESET = Animation.create_definition(sprites.environment.trap_door_reset, 4, {
    width = 32,
    height = 16,
    loop = false
})

-- Constants
local STAND_DELAY = 0.4           -- Seconds player must stand before triggering
local OPEN_DURATION = 2.0         -- Seconds door stays open
local STANDING_TOLERANCE = 0.3    -- Vertical tolerance for standing detection (accounts for slopes/floating point)

--- Check if player is standing on the trap door
--- Uses combat system for spatial proximity, then checks vertical alignment
---@param prop table Trap door prop instance
---@param player table Player instance
---@return boolean True if player is standing on the door
local function is_player_standing(prop, player)
    if not player then return false end
    if not player.is_grounded then return false end
    if player.vy < 0 then return false end  -- Player is moving upward (jumping through)

    -- Quick spatial check using combat system
    if not combat.collides(prop, player) then
        -- Also check if player is just above (within tolerance) since trap door is thin
        local door_top = prop.y + prop.box.y
        local player_bottom = player.y + player.box.y + player.box.h
        if math.abs(player_bottom - door_top) >= STANDING_TOLERANCE then
            return false
        end
        -- Player is vertically close, but we still need horizontal overlap
        local door_left = prop.x + prop.box.x
        local door_right = prop.x + prop.box.x + prop.box.w
        local player_left = player.x + player.box.x
        local player_right = player.x + player.box.x + player.box.w
        if player_right <= door_left or player_left >= door_right then
            return false
        end
        return true
    end

    -- Combat system detected overlap - verify vertical alignment (player standing on top)
    local door_top = prop.y + prop.box.y
    local player_bottom = player.y + player.box.y + player.box.h

    return math.abs(player_bottom - door_top) < STANDING_TOLERANCE
end

local definition = {
    box = { x = 0, y = 0, w = 2, h = 0.1875 },  -- 2 tiles wide, 3px thin top collider
    debug_color = "#FFA500",  -- Orange
    initial_state = "closed",

    ---@param prop table The prop instance being spawned
    ---@param def table Trap door definition (box, states, initial_state)
    ---@param options table|nil Spawn options (reserved for future use)
    on_spawn = function(prop, def, options)
        prop.animation = Animation.new(TRAP_DOOR_CLOSED)
        prop.stand_timer = 0
        prop.open_timer = 0
        prop.triggered = false  -- Once triggered, always opens
        prop.collider_shape = nil  -- Store shape reference for removal
    end,

    states = {
        closed = {
            name = "closed",
            ---@param prop table Trap door prop instance
            ---@param def table Trap door definition (box, states, initial_state)
            start = function(prop, def)
                prop.animation = Animation.new(TRAP_DOOR_CLOSED)
                prop.stand_timer = 0
                prop.triggered = false
                -- Collider must exist for player to stand on door
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,
            ---@param prop table Trap door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table Player instance
            update = function(prop, dt, player)
                -- Once triggered (player landed), always continue to opening
                if prop.triggered or is_player_standing(prop, player) then
                    prop.triggered = true
                    prop.stand_timer = prop.stand_timer + dt
                    if prop.stand_timer >= STAND_DELAY then
                        Prop.set_state(prop, "opening")
                    end
                end
            end,
            draw = prop_common.draw
        },

        opening = {
            name = "opening",
            ---@param prop table Trap door prop instance
            ---@param def table Definition table
            start = function(prop, def)
                prop.animation = Animation.new(TRAP_DOOR_OPEN)
                -- Remove collider immediately so player falls
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,
            ---@param prop table Trap door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table Player instance
            update = function(prop, dt, player)
                -- Animation is advanced by Prop.update; just check completion
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "open")
                end
            end,
            draw = prop_common.draw
        },

        open = {
            name = "open",
            ---@param prop table Trap door prop instance
            ---@param def table Definition table
            start = function(prop, def)
                -- Keep last frame of open animation
                prop.animation = Animation.new(TRAP_DOOR_OPEN, {
                    start_frame = TRAP_DOOR_OPEN.frame_count - 1
                })
                prop.animation:pause()
                prop.open_timer = 0
            end,
            ---@param prop table Trap door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table Player instance
            update = function(prop, dt, player)
                prop.open_timer = prop.open_timer + dt
                if prop.open_timer >= OPEN_DURATION then
                    Prop.set_state(prop, "resetting")
                end
            end,
            draw = prop_common.draw
        },

        resetting = {
            name = "resetting",
            ---@param prop table Trap door prop instance
            ---@param def table Definition table
            start = function(prop, def)
                prop.animation = Animation.new(TRAP_DOOR_RESET)
            end,
            ---@param prop table Trap door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table Player instance
            update = function(prop, dt, player)
                -- Animation is advanced by Prop.update; just check completion
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "closed")
                end
            end,
            draw = prop_common.draw
        }
    }
}

return definition
