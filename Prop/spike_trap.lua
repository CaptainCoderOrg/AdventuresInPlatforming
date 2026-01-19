--- Spike trap prop definition - Complex 4-state machine with groups
local sprites = require("sprites")
local Animation = require("Animation")
local Prop = require("Prop")
local common = require("Prop/common")

local SPIKE_ANIM = Animation.create_definition(sprites.environment.spikes, 6, {
    ms_per_frame = 480,
    width = 16,
    height = 16,
    loop = false
})

local DEFAULT_EXTEND_TIME = 1.5
local DEFAULT_RETRACT_TIME = 1.5

--- Check if spikes should damage the player and apply damage
---@param prop table SpikeTrap instance
---@param player table Player instance
local function check_damage(prop, player)
    if common.player_touching(prop, player) and not player:is_invincible() and player:health() > 0 then
        player:take_damage(1)
    end
end

local definition = {
    box = { x = 0, y = 0.2, w = 1, h = 0.8 },
    debug_color = "#FF00FF",
    initial_state = "extended",

    ---@param prop table The prop instance being spawned
    ---@param def table The spike trap definition
    ---@param options table Spawn options: mode, extend_time, retract_time, start_retracted
    on_spawn = function(prop, def, options)
        prop.mode = options.mode or "static"
        prop.extend_time = options.extend_time or DEFAULT_EXTEND_TIME
        prop.retract_time = options.retract_time or DEFAULT_RETRACT_TIME
        prop.timer = 0

        local start_retracted = options.start_retracted or false
        prop.initial_retracted = start_retracted
        prop.animation = Animation.new(SPIKE_ANIM, { start_frame = start_retracted and 5 or 0 })
        prop.animation:pause()

        if start_retracted then
            Prop.set_state(prop, "retracted")
        end
    end,

    states = {
        --- Spikes fully extended, damages player on contact
        extended = {
            name = "extended",
            start = function(prop, def)
                prop.timer = 0
                prop.animation:pause()
            end,
            --- Check damage and handle alternating mode timer
            update = function(prop, dt, player)
                check_damage(prop, player)

                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.extend_time then
                        Prop.set_state(prop, "retracting")
                    end
                end
            end,
            draw = common.draw
        },

        --- Spikes retracting into ground
        retracting = {
            name = "retracting",
            start = function(prop, def)
                -- New instance required to reset playback state from frame 0
                prop.animation = Animation.new(SPIKE_ANIM, { start_frame = 0 })
            end,
            update = function(prop, dt, player)
                prop.animation:play(dt)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "retracted")
                end
            end,
            draw = common.draw
        },

        --- Spikes fully retracted, safe to walk over
        retracted = {
            name = "retracted",
            start = function(prop, def)
                prop.timer = 0
                prop.animation:pause()
            end,
            --- Handle alternating mode timer
            update = function(prop, dt, player)
                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.retract_time then
                        Prop.set_state(prop, "extending")
                    end
                end
            end,
            draw = common.draw
        },

        --- Spikes extending from ground, damages player on contact
        extending = {
            name = "extending",
            start = function(prop, def)
                -- New instance required to play animation in reverse from frame 5
                prop.animation = Animation.new(SPIKE_ANIM, { start_frame = 5, reverse = true })
            end,
            update = function(prop, dt, player)
                prop.animation:play(dt)
                check_damage(prop, player)

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "extended")
                end
            end,
            draw = common.draw
        }
    }
}

--- Reset spike trap to initial state with animation
---@param prop table SpikeTrap instance
function definition.reset(prop)
    local current = prop.state.name
    local target_retracted = prop.initial_retracted

    if target_retracted and (current == "extended" or current == "extending") then
        Prop.set_state(prop, "retracting")
    elseif not target_retracted and (current == "retracted" or current == "retracting") then
        Prop.set_state(prop, "extending")
    end
end

return definition
