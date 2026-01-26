--- Pressure plate prop - Triggered by player/enemy collision with press/release callbacks
local Animation = require("Animation")
local audio = require("audio")
local combat = require("combat")
local common = require("Prop/common")
local config = require("config")
local Prop = require("Prop")
local sprites = require("sprites")

-- Lift height in pixels per animation frame (0-indexed: frame 0, 1, 2, 3)
-- Frame 0 (unpressed): 0px, Frame 1: 3px, Frame 2: 2px, Frame 3 (fully pressed): 1px
local LIFT_BY_FRAME = { [0] = 0, [1] = 3*config.ui.SCALE, [2] = 2*config.ui.SCALE, [3] = 1*config.ui.SCALE }

local PLATE_ANIM = Animation.create_definition(sprites.environment.pressure_plate, 3, {
    ms_per_frame = 100,
    width = 32,
    height = 16,
    loop = false
})

-- Module-level filter function (avoids closure allocation per frame)
local function enemy_filter(entity)
    return entity.is_enemy
end

-- Module-level results table (avoids allocation per query)
local _enemy_query_results = {}

--- Check if any entity (player or enemy) is occupying the pressure plate.
--- Also sets pressure_plate_lift on occupying entities for efficient draw-time lookup.
---@param prop table Pressure plate prop instance
---@param player table|nil Player reference
---@return boolean True if any entity is on the plate
local function is_occupied(prop, player)
    local dominated = false
    local lift = prop.lift_amount or 0

    -- Check player
    if player and common.player_touching(prop, player) then
        player.pressure_plate_lift = lift
        dominated = true
    end

    -- Check enemies using combat spatial query (reuses filter and results table)
    local box = prop.box
    local hits = combat.query_rect(
        prop.x + box.x,
        prop.y + box.y,
        box.w,
        box.h,
        enemy_filter,
        _enemy_query_results
    )

    for i = 1, #hits do
        hits[i].pressure_plate_lift = lift
        dominated = true
    end

    return dominated
end

--- Updates the lift amount based on current animation frame.
---@param prop table Pressure plate prop instance
local function update_lift_amount(prop)
    local frame = prop.animation.frame
    prop.lift_amount = LIFT_BY_FRAME[frame] or 0
end

local definition = {
    -- Collider: 26px wide centered, 3px tall at bottom of 32x16 sprite
    box = { x = 0.1875, y = 0.8125, w = 1.625, h = 0.1875 },
    debug_color = "#00FF00",
    initial_state = "unpressed",

    ---@param prop table The prop instance being spawned
    ---@param def table The pressure plate definition
    ---@param options table Spawn options, may contain on_pressed/on_release callbacks
    on_spawn = function(prop, def, options)
        prop.animation = Animation.new(PLATE_ANIM)
        prop.animation:pause()
        prop.on_pressed = options.on_pressed
        prop.on_release = options.on_release
        prop.callback_fired = false
        prop.skip_callback = false
        prop.lift_amount = 0
    end,

    states = {
        unpressed = {
            start = function(prop)
                prop.animation = Animation.new(PLATE_ANIM)
                prop.animation:pause()
                prop.callback_fired = false
                prop.lift_amount = 0
            end,
            update = function(prop, _dt, player)
                if is_occupied(prop, player) then
                    Prop.set_state(prop, "pressed")
                end
            end,
            draw = common.draw
        },

        pressed = {
            start = function(prop)
                prop.animation = Animation.new(PLATE_ANIM)
                prop.animation:resume()
                prop.callback_fired = false
                audio.play_sfx(audio.stone_slab_pressed)
            end,
            update = function(prop, _dt, player)
                update_lift_amount(prop)

                -- Apply lift to entities every frame for smooth visual feedback during animation
                local occupied = is_occupied(prop, player)

                -- Callback timing: fire after visual feedback completes so player sees plate depress first
                if prop.animation:is_finished() then
                    if not prop.callback_fired then
                        prop.callback_fired = true
                        if prop.on_pressed and not prop.skip_callback then
                            prop.on_pressed()
                        end
                        prop.skip_callback = false
                    end

                    -- Only transition after animation to prevent rapid press/release flickering
                    if not occupied then
                        Prop.set_state(prop, "release")
                    end
                end
            end,
            draw = common.draw
        },

        release = {
            start = function(prop)
                -- Fire on_release callback at start of release state
                if prop.on_release and not prop.skip_callback then
                    prop.on_release()
                end
                prop.skip_callback = false

                -- Create reverse animation from last frame
                prop.animation = Animation.new(PLATE_ANIM, {
                    start_frame = PLATE_ANIM.frame_count - 1,
                    reverse = true
                })
                audio.play_sfx(audio.stone_slab_released)
            end,
            update = function(prop, _dt, _player)
                update_lift_amount(prop)

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "unpressed")
                end
            end,
            draw = common.draw
        }
    }
}

--- Force press the plate externally (skips callback)
---@param prop table Pressure plate prop instance
function definition.press(prop)
    if prop.state_name == "unpressed" then
        prop.skip_callback = true
        Prop.set_state(prop, "pressed")
    end
end

--- Force release the plate externally (skips callback)
---@param prop table Pressure plate prop instance
function definition.release(prop)
    if prop.state_name == "pressed" and prop.animation:is_finished() then
        prop.skip_callback = true
        Prop.set_state(prop, "release")
    end
end

--- Query if the plate is currently pressed
---@param prop table Pressure plate prop instance
---@return boolean True if pressed (in pressed state with animation done)
function definition.is_pressed(prop)
    return prop.state_name == "pressed" and prop.animation:is_finished()
end

--- Get the current lift amount in pixels for entities standing on this plate
---@param prop table Pressure plate prop instance
---@return number Lift amount in pixels (0-3)
function definition.get_lift(prop)
    return prop.lift_amount or 0
end

return definition
