--- Boss door prop definition - Can be triggered to open/close programmatically
--- Unlike locked_door, has no key requirement. Controlled via group_action or set_state.
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Prop = require("Prop")
local sprites = require("sprites")
local world = require("world")

--- Create door animation definition for 32x32 frames
---@param row number Spritesheet row index
---@param frames number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@param loop boolean Whether animation should loop
---@return table Animation definition
local function create_door_anim(row, frames, ms_per_frame, loop)
    return Animation.create_definition(sprites.environment.boss_door, frames, {
        ms_per_frame = ms_per_frame,
        width = 32,
        height = 32,
        loop = loop,
        row = row
    })
end

local DOOR_IDLE = create_door_anim(0, 6, 160, false)    -- Row 0: Idle (non-looping, we handle pause manually)
local DOOR_CLOSING = create_door_anim(1, 7, 150, false) -- Row 1: Closing (slower for dramatic effect)
local DOOR_OPENING = create_door_anim(2, 6, 150, false) -- Row 2: Opening (matches closing speed)

-- 3 second pause before restarting idle animation
local IDLE_PAUSE_DURATION = 3

-- Frame to trigger sound effects (0-indexed, so 2 = frame 3)
local SFX_FRAME = 2

return {
    box = { x = 0.5, y = 0, w = 1, h = 2 },  -- 16x32 collider, centered horizontally
    debug_color = "#8B0000",
    initial_state = "closed",
    default_reset = false,  -- Persist door state across saves

    --- Get state data for saving (persistent props only)
    ---@param prop table The door prop instance
    ---@return table state_data Data to save
    get_save_state = function(prop)
        return { state_name = prop.state_name }
    end,

    --- Restore state from saved data
    ---@param prop table The door prop instance
    ---@param saved_state table Saved state data
    restore_save_state = function(prop, saved_state)
        if saved_state.state_name then
            Prop.set_state(prop, saved_state.state_name)
        end
    end,

    ---@param prop table The prop instance being spawned
    ---@param _def table The door definition (unused)
    ---@param options table Spawn options (contains optional state override)
    on_spawn = function(prop, _def, options)
        -- Allow initial state override from Tiled
        if options and options.state then
            prop._initial_state_override = options.state
        end
    end,

    states = {
        open = {
            ---@param prop table The door prop instance
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                prop.animation = nil  -- Clear animation so draw is no-op
            end,

            ---@param _prop table Unused
            ---@param _dt number Unused
            ---@param _player table Unused
            update = function(_prop, _dt, _player) end,

            ---@param _prop table Unused (door is invisible when open)
            draw = function(_prop) end
        },

        closed = {
            ---@param prop table The door prop instance
            start = function(prop)
                -- Handle initial state override from Tiled (checked once on first entry)
                if prop._initial_state_override then
                    local target_state = prop._initial_state_override
                    prop._initial_state_override = nil
                    if target_state ~= "closed" then
                        Prop.set_state(prop, target_state)
                        return
                    end
                end

                prop._timer = 0
                prop.animation = Animation.new(DOOR_IDLE)
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,

            ---@param prop table The door prop instance
            ---@param dt number Delta time in seconds
            ---@param _player table Player reference (unused)
            update = function(prop, dt, _player)
                -- Loop idle animation with 3 second pause on last frame
                if prop.animation:is_finished() then
                    prop._timer = prop._timer + dt
                    if prop._timer >= IDLE_PAUSE_DURATION then
                        prop._timer = 0
                        prop.animation:reset()
                    end
                end
            end,

            draw = common.draw
        },

        closing = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_CLOSING)
                prop._last_frame = 0
                prop._sfx_played = false
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                -- Play sound on frame 3 (index 2)
                local frame = prop.animation.frame
                if not prop._sfx_played and frame >= SFX_FRAME then
                    audio.play_boss_door_close()
                    prop._sfx_played = true
                end

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "closed")
                end
            end,

            draw = common.draw
        },

        opening = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_OPENING)
                prop._last_frame = 0
                prop._sfx_played = false
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                -- Play sound on frame 3 (index 2)
                local frame = prop.animation.frame
                if not prop._sfx_played and frame >= SFX_FRAME then
                    audio.play_boss_door_open()
                    prop._sfx_played = true
                end

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "open")
                end
            end,

            draw = common.draw
        }
    }
}
