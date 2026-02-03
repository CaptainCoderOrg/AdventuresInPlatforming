--- Locked door prop definition - Blocks passage until unlocked
--- Can be unlocked by: required_key (player has item), or group_action("unlock")
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Effects = require("Effects")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local world = require("world")

--- Create door animation definition with standard size settings
---@param sprite string Sprite identifier
---@param frames number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@return table Animation definition
local function create_door_anim(sprite, frames, ms_per_frame)
    return Animation.create_definition(sprite, frames, {
        ms_per_frame = ms_per_frame,
        width = 16,
        height = 32,
        loop = false
    })
end

local DOOR_LOCKED = create_door_anim(sprites.environment.locked_door_idle, 6, 160)
local DOOR_LOCKED_JIGGLE = create_door_anim(sprites.environment.locked_door_jiggle, 5, 80)
local DOOR_UNLOCK = create_door_anim(sprites.environment.locked_door_open, 13, 80)

return {
    box = { x = 0, y = 0, w = 1, h = 2 },
    debug_color = "#8B4513",
    initial_state = "locked",
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
    ---@param options table Spawn options (contains required_key)
    on_spawn = function(prop, _def, options)
        prop.required_key = options and options.required_key
        if prop.required_key then
            prop.text_display = TextDisplay.new("Open: {move_up}", { anchor = "top" })
        end
    end,

    states = {
        locked = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop._timer = 0
                prop.animation = Animation.new(DOOR_LOCKED)
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,

            --- Handle player interaction - unlock if player has key, else show feedback
            ---@param prop table The door prop instance
            ---@param player table The player instance
            ---@return boolean True if interaction occurred
            interact = function(prop, player)
                if not prop.required_key then return false end
                if common.player_has_item(player, prop.required_key) then
                    -- Consume the key (works for both stackable and unique items)
                    common.consume_stackable_item(player, prop.required_key)
                    Prop.set_state(prop, "unlock")
                else
                    Effects.create_locked_text(player.x + 0.5, player.y - 1, player)
                    Prop.set_state(prop, "jiggle")
                end
                return true
            end,

            ---@param prop table The door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                local touching = player and common.player_touching(prop, player)

                if prop.text_display then
                    prop.text_display:update(dt, touching)
                end

                -- Restart idle animation every second to add visual life
                if prop.animation:is_finished() then
                    prop._timer = prop._timer + dt
                    if prop._timer > 1 then
                        prop._timer = 0
                        prop.animation:reset()
                    end
                end
            end,

            ---@param prop table The door prop instance
            draw = function(prop)
                common.draw(prop)
                if prop.text_display then
                    prop.text_display:draw(prop.x, prop.y)
                end
            end
        },

        jiggle = {
            --- Initialize jiggle feedback animation when player lacks required key
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_LOCKED_JIGGLE)
                audio.play_sfx(audio.locked_door)
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "locked")
                end
            end,

            draw = common.draw
        },

        unlock = {
            --- Begin unlock animation and play unlock sound
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_UNLOCK)
                audio.play_sfx(audio.unlock_door)
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "unlocked")
                end
            end,

            draw = common.draw
        },

        unlocked = {
            --- Remove door collision when unlocked
            ---@param prop table The door prop instance
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,

            ---@param _prop table Unused (door is open)
            ---@param _dt number Unused
            ---@param _player table Unused
            update = function(_prop, _dt, _player) end,

            ---@param _prop table Unused (door is invisible when unlocked)
            draw = function(_prop) end
        }
    }
}
