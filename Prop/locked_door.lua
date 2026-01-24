--- Locked door prop definition - Blocks passage until unlocked
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Effects = require("Effects")
local Prop = require("Prop")
local sprites = require("sprites")
local world = require("world")

local DOOR_ANIM_OPTIONS = {
    ms_per_frame = 80,
    width = 16,
    height = 32,
    loop = false
}

local DOOR_LOCKED = Animation.create_definition(sprites.environment.locked_door, 1, DOOR_ANIM_OPTIONS)
local DOOR_UNLOCK = Animation.create_definition(sprites.environment.locked_door, 13, DOOR_ANIM_OPTIONS)

local FEEDBACK_DEBOUNCE = 5.0  -- Seconds between "Locked" feedback

return {
    box = { x = 0, y = 0, w = 1, h = 2 },
    debug_color = "#8B4513",
    initial_state = "locked",

    states = {
        locked = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_LOCKED)
                prop.animation:pause()
                prop.feedback_timer = 0
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,

            ---@param prop table The door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                if prop.feedback_timer > 0 then
                    prop.feedback_timer = prop.feedback_timer - dt
                end

                if player and common.player_touching(prop, player) and prop.feedback_timer <= 0 then
                    Effects.create_locked_text(prop.x + 0.5, prop.y, player)
                    audio.play_sfx(audio.locked_door)
                    prop.feedback_timer = FEEDBACK_DEBOUNCE
                end
            end,

            draw = common.draw
        },

        unlock = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_UNLOCK)
                audio.play_sfx(audio.unlock_door)
            end,

            ---@param prop table The door prop instance
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "unlocked")
                end
            end,

            draw = common.draw
        },

        unlocked = {
            ---@param prop table The door prop instance
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,

            update = function(_prop, _dt, _player) end,
            draw = function(_prop) end
        }
    }
}
