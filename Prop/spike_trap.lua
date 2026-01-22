--- Spike trap prop definition - Complex 4-state machine with groups
local sprites = require("sprites")
local Animation = require("Animation")
local Prop = require("Prop")
local common = require("Prop/common")
local audio = require("audio")
local proximity_audio = require("proximity_audio")

local SPIKE_ANIM = Animation.create_definition(sprites.environment.spikes, 6, {
    ms_per_frame = 40,
    width = 16,
    height = 16,
    loop = false
})

-- Default timing for alternating mode
local DEFAULT_EXTEND_TIME = 1.5
local DEFAULT_RETRACT_TIME = 1.5

-- Roughly one screen width; prevents distant traps from creating noise clutter
local SOUND_RADIUS = 8

--- Start animation transition
---@param prop table SpikeTrap instance with `animation` field
---@param anim_options {start_frame: number, reverse: boolean|nil} Animation playback options
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

        -- Register for spatial audio queries
        proximity_audio.register(prop, {
            sound_id = "spiketrap",
            radius = SOUND_RADIUS,
            max_volume = 0.4
        })

        local start_retracted = options.start_retracted or false
        local initial_frame = start_retracted and 5 or 0

        prop.animation = Animation.new(SPIKE_ANIM, { start_frame = initial_frame })
        prop.animation:pause()

        -- Override initial state if starting retracted
        if start_retracted then
            Prop.set_state(prop, "retracted")
        end
    end,

    disable = function(prop)
        prop.mode = "static"
        -- Only trigger retraction if not already retracted/retracting
        if prop.state_name == "extended" or prop.state_name == "extending" then
            Prop.set_state(prop, "retracting")
        end
    end,

    states = {
        extended = {
            start = function(prop, def)
                prop.timer = 0
                prop.animation:pause()
            end,
            update = function(prop, dt, player)
                common.damage_player(prop, player, 1)

                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.extend_time then
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
            update = function(prop, dt)
                if prop.animation:is_finished() then
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
                if prop.mode == "alternating" then
                    prop.timer = prop.timer + dt
                    if prop.timer >= prop.retract_time then
                        Prop.set_state(prop, "extending")
                    end
                end
            end,
            draw = common.draw
        },

        extending = {
            start = function(prop, def)
                start_animation(prop, { start_frame = 5, reverse = true })
                prop.sound_played = false
            end,
            update = function(prop, dt, player)
                if not prop.sound_played and player then
                    if proximity_audio.is_in_range(player.x, player.y, prop) then
                        audio.play_sfx(audio.spiketrap, 0.4)
                        prop.sound_played = true
                    end
                end

                common.damage_player(prop, player, 1)

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "extended")
                end
            end,
            draw = common.draw
        }
    }
}

return definition
