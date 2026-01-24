--- Locked door prop definition - Blocks passage until unlocked
--- Can be unlocked by: required_key (player has item), or group_action("unlock")
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local controls = require("controls")
local Effects = require("Effects")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local world = require("world")

local DOOR_ANIM_OPTIONS = {
    ms_per_frame = 80,
    width = 16,
    height = 32,
    loop = false
}

local DOOR_LOCKED = Animation.create_definition(sprites.environment.locked_door, 1, DOOR_ANIM_OPTIONS)
local DOOR_UNLOCK = Animation.create_definition(sprites.environment.locked_door, 13, DOOR_ANIM_OPTIONS)

-- Prevents spamming "Locked" feedback; 5s gives player time to find key
local FEEDBACK_DEBOUNCE = 5.0

return {
    box = { x = 0, y = 0, w = 1, h = 2 },
    debug_color = "#8B4513",
    initial_state = "locked",

    ---@param prop table The prop instance being spawned
    ---@param _def table The door definition (unused)
    ---@param options table Spawn options (contains required_key)
    on_spawn = function(prop, _def, options)
        prop.required_key = options and options.required_key
        if prop.required_key then
            prop.text_display = TextDisplay.new("Open\n{move_down} + {attack}", { anchor = "top" })
        end
    end,

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

                local touching = player and common.player_touching(prop, player)

                if prop.text_display then
                    prop.text_display:update(dt, touching)
                end

                if not touching or not prop.required_key then return end
                if not controls.down_down() or not controls.attack_pressed() then return end

                if common.player_has_item(player, prop.required_key) then
                    Prop.set_state(prop, "unlock")
                elseif prop.feedback_timer <= 0 then
                    Effects.create_locked_text(prop.x + 0.5, prop.y, player)
                    audio.play_sfx(audio.locked_door)
                    prop.feedback_timer = FEEDBACK_DEBOUNCE
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

        unlock = {
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
            ---@param prop table The door prop instance
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,

            ---@param _prop table The door prop instance (unused)
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(_prop, _dt, _player) end,

            -- Empty draw hides the door after unlock animation completes
            ---@param _prop table The door prop instance (unused)
            draw = function(_prop) end
        }
    }
}
