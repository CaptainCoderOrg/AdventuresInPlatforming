--- Spike trap prop definition - Complex 5-state machine with groups
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

local SPIKE_DISABLED_ANIM = Animation.create_definition(sprites.environment.spike_trap_disabled, 1, {
    ms_per_frame = 1000,
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

---@class SpikeTrapOptions
---@field mode string|nil "static" or "alternating" (default: "static")
---@field extend_time number|nil Time in extended state (default: 1.5)
---@field retract_time number|nil Time in retracted state (default: 1.5)
---@field alternating_offset number|nil Initial timer offset for staggered groups (default: 0)
---@field start_retracted boolean|nil Whether to start in retracted state (default: false)

local definition = {
    box = { x = 0.1, y = 0.2, w = 0.8, h = 0.8 },
    debug_color = "#FF00FF",  -- Magenta
    initial_state = "extended",

    --- Initializes a new spike trap instance with mode and timing configuration
    ---@param prop table The prop instance being spawned
    ---@param def table The prop definition table
    ---@param options SpikeTrapOptions Spawn options for behavior configuration
    on_spawn = function(prop, def, options)
        prop.mode = options.mode or "static"
        prop.extend_time = options.extend_time or DEFAULT_EXTEND_TIME
        prop.retract_time = options.retract_time or DEFAULT_RETRACT_TIME
        prop.alternating_offset = options.alternating_offset or 0
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

        if start_retracted then
            Prop.set_state(prop, "retracted")
        end
    end,

    --- Permanently disables the spike trap, transitioning to retracted/disabled state
    ---@param prop table The prop instance to disable
    disable = function(prop)
        prop.mode = "static"
        prop.is_disabled = true
        -- Transition based on current state
        if prop.state_name == "extended" or prop.state_name == "extending" then
            Prop.set_state(prop, "retracting")
        elseif prop.state_name == "retracted" then
            Prop.set_state(prop, "disabled")
        end
        -- If already retracting, the state will check is_disabled when animation finishes
    end,

    --- Retract spikes and stop cycling (non-permanent, can be reactivated with set_alternating).
    ---@param prop table The prop instance to retract
    retract = function(prop)
        prop.mode = "static"
        if prop.state_name == "extended" or prop.state_name == "extending" then
            Prop.set_state(prop, "retracting")
        end
        -- If already retracting or retracted, no action needed
    end,

    --- Activates alternating mode with the configured offset.
    --- The offset is applied once to stagger this trap relative to others in the group.
    ---@param prop table The prop instance to configure
    ---@param config table|nil Optional config from group_config (extend_time, retract_time)
    set_alternating = function(prop, config)
        if config then
            if config.extend_time then prop.extend_time = config.extend_time end
            if config.retract_time then prop.retract_time = config.retract_time end
        end
        prop.mode = "alternating"

        -- Normalize offset to within a single cycle for predictable behavior
        local cycle_time = prop.extend_time + prop.retract_time
        local effective_offset = prop.alternating_offset % cycle_time
        prop.timer = effective_offset

        -- When offset exceeds extend_time, the trap will transition through retracting
        -- and into retracted state. Pre-calculate how far into the retracted phase it should start.
        if effective_offset > prop.extend_time then
            prop.retracted_timer_start = effective_offset - prop.extend_time
        end
    end,

    states = {
        extended = {
            start = function(prop, _def)
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
            start = function(prop, _def)
                start_animation(prop, { start_frame = 0 })
            end,
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    if prop.is_disabled then
                        Prop.set_state(prop, "disabled")
                    else
                        Prop.set_state(prop, "retracted")
                    end
                end
            end,
            draw = common.draw
        },

        retracted = {
            start = function(prop, _def)
                prop.timer = prop.retracted_timer_start or 0
                prop.retracted_timer_start = nil
                prop.animation:pause()
            end,
            update = function(prop, dt, _player)
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
            start = function(prop, _def)
                start_animation(prop, { start_frame = 5, reverse = true })
                prop.sound_played = false
            end,
            update = function(prop, _dt, player)
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
        },

        disabled = {
            start = function(prop, _def)
                prop.animation = Animation.new(SPIKE_DISABLED_ANIM)
                prop.animation:pause()
            end,
            update = function(_prop, _dt, _player)
                -- No collision damage, no state transitions - permanently disabled
            end,
            draw = common.draw
        }
    }
}

return definition
