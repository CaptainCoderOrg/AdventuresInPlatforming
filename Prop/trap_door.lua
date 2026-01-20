--- Trap door prop definition - Collapsing platform with 4-state cycle
--- States: closed -> opening -> open -> resetting -> closed
local sprites = require("sprites")
local Animation = require("Animation")
local Prop = require("Prop")
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
---@param prop table Trap door prop instance
---@param player table Player instance
---@return boolean True if player is standing on the door
local function is_player_standing(prop, player)
    if not player then return false end
    if not player.is_grounded then return false end
    if player.vy < 0 then return false end  -- Player is moving upward (jumping through)

    -- Check horizontal overlap (player within trap door width)
    local door_left = prop.x + prop.box.x
    local door_right = prop.x + prop.box.x + prop.box.w
    local player_left = player.x + player.box.x
    local player_right = player.x + player.box.x + player.box.w

    if player_right <= door_left or player_left >= door_right then
        return false
    end

    -- Check vertical alignment (player bottom near door top)
    local door_top = prop.y + prop.box.y
    local player_bottom = player.y + player.box.y + player.box.h

    return math.abs(player_bottom - door_top) < STANDING_TOLERANCE
end

--- Shared draw function for trap door states
---@param prop table Trap door prop instance
local function draw_trap_door(prop)
    local px = prop.x * sprites.tile_size
    local py = prop.y * sprites.tile_size
    prop.animation:draw(px, py)
end

--- Check if two trap doors are adjacent or overlapping (could both support player)
---@param a table First trap door
---@param b table Second trap door
---@return boolean True if they overlap or touch
local function overlaps_trap_door(a, b)
    -- Same Y position (same row)
    if a.y ~= b.y then return false end
    -- Check if adjacent or overlapping (use <= to include touching edges)
    local a_left = a.x + a.box.x
    local a_right = a.x + a.box.x + a.box.w
    local b_left = b.x + b.box.x
    local b_right = b.x + b.box.x + b.box.w
    return a_left <= b_right and a_right >= b_left
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
            draw = draw_trap_door
        },

        opening = {
            name = "opening",
            ---@param prop table Trap door prop instance
            ---@param def table Definition table
            ---@param skip_cascade boolean If true, don't trigger other trap doors (prevents infinite recursion)
            start = function(prop, def, skip_cascade)
                prop.animation = Animation.new(TRAP_DOOR_OPEN)
                -- Remove collider immediately so player falls
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                -- Trigger all adjacent/overlapping trap doors to open together (same frame)
                if not skip_cascade then
                    for other_prop in pairs(Prop.all) do
                        if other_prop.type_key == "trap_door" and other_prop ~= prop then
                            if other_prop.state_name == "closed" and overlaps_trap_door(prop, other_prop) then
                                Prop.set_state(other_prop, "opening", true)  -- skip_cascade = true
                            end
                        end
                    end
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
            draw = draw_trap_door
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
            draw = draw_trap_door
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
            draw = draw_trap_door
        }
    }
}

return definition
