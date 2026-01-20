--- Spike trap prop definition - Complex 4-state machine with groups
local sprites = require("sprites")
local Animation = require("Animation")
local common = require("Prop/common")

local SPIKE_ANIM = Animation.create_definition(sprites.environment.spikes, 6, {
    ms_per_frame = 160,
    width = 16,
    height = 16,
    loop = false
})

-- Default timing for alternating mode
local DEFAULT_EXTEND_TIME = 1.5
local DEFAULT_RETRACT_TIME = 1.5

--- Start animation transition
---@param prop table SpikeTrap instance
---@param anim_options table Animation options (start_frame, reverse)
local function start_animation(prop, anim_options)
    prop.animation = Animation.new(SPIKE_ANIM, anim_options)
end

local definition = {
    box = { x = 0, y = 0.2, w = 1, h = 0.8 },
    debug_color = "#FF00FF",  -- Magenta
    initial_state = "extended",

    on_spawn = function(prop, def, options)
        prop.mode = options.mode or "static"
        prop.extend_time = options.extend_time or DEFAULT_EXTEND_TIME
        prop.retract_time = options.retract_time or DEFAULT_RETRACT_TIME
        prop.timer = 0

        local start_retracted = options.start_retracted or false
        local initial_frame = start_retracted and 5 or 0

        prop.animation = Animation.new(SPIKE_ANIM, { start_frame = initial_frame })
        prop.animation:pause()

        -- Override initial state if starting retracted
        if start_retracted then
            local Prop = require("Prop")
            Prop.set_state(prop, "retracted")
        end
    end,

    states = {
        extended = {
            start = function(prop, def)
                prop.timer = 0
                prop.animation:pause()
            end,
            update = function(prop, dt, player)
                -- Check damage
                if common.player_touching(prop, player) and not player:is_invincible() and player:health() > 0 then
                    player:take_damage(1)
                end

                -- Alternating mode timer
                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.extend_time then
                        local Prop = require("Prop")
                        Prop.set_state(prop, "retracting")
                    end
                end
            end,
            draw = common.draw
        },

        retracting = {
            start = function(prop, def)
                start_animation(prop, { start_frame = 0 })
            end,
            update = function(prop, dt, player)
                prop.animation:play(dt)
                if prop.animation:is_finished() then
                    local Prop = require("Prop")
                    Prop.set_state(prop, "retracted")
                end
            end,
            draw = common.draw
        },

        retracted = {
            start = function(prop, def)
                prop.timer = 0
                prop.animation:pause()
            end,
            update = function(prop, dt, player)
                -- Alternating mode timer
                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.retract_time then
                        local Prop = require("Prop")
                        Prop.set_state(prop, "extending")
                    end
                end
            end,
            draw = common.draw
        },

        extending = {
            start = function(prop, def)
                start_animation(prop, { start_frame = 5, reverse = true })
            end,
            update = function(prop, dt, player)
                prop.animation:play(dt)

                -- Check damage while extending
                if common.player_touching(prop, player) and not player:is_invincible() and player:health() > 0 then
                    player:take_damage(1)
                end

                if prop.animation:is_finished() then
                    local Prop = require("Prop")
                    Prop.set_state(prop, "extended")
                end
            end,
            draw = common.draw
        }
    }
}

return definition
