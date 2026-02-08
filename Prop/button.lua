--- Button prop definition - Binary state (unpressed/pressed) with callback
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Prop = require("Prop")
local sprites = require("sprites")

local BUTTON_ANIM = Animation.create_definition(sprites.environment.button, 5, {
    ms_per_frame = 100,
    width = 16,
    height = 8,
    loop = false
})

--- Button Y offset (sprite is 8px tall, positioned in bottom half of tile)
local BUTTON_Y_OFFSET = 0.5

--- Shared draw function for button states
---@param prop table Button prop instance
local function draw_button(prop)
    common.draw(prop, BUTTON_Y_OFFSET)
end

local definition = {
    box = { x = 0, y = 0.5, w = 1, h = 0.5 },
    debug_color = "#00FF00",
    initial_state = "unpressed",

    ---@param prop table The prop instance being spawned
    ---@param def table The button definition
    ---@param options table Spawn options: on_press, target_group, target_action, persist
    on_spawn = function(prop, def, options)
        prop.animation = Animation.new(BUTTON_ANIM)
        prop.animation:pause()
        prop.is_pressed = false
        prop.on_press = options.on_press
        -- Auto-wire from Tiled properties if no explicit callback
        if not prop.on_press and options.target_group and options.target_action then
            local group = options.target_group
            local action = options.target_action
            prop.on_press = function()
                Prop.group_action(group, action)
            end
        end
        -- Opt-in persistence: button stays pressed across rest/reload
        if options.persist then
            prop.should_reset = false
        end
    end,

    states = {
        unpressed = {
            -- No start/update needed - static state until externally triggered
            draw = draw_button
        },
        pressed = {
            ---@param prop table Button prop instance
            ---@param _def table Button definition (unused)
            ---@param skip_callback boolean|nil If true, don't fire on_press callback
            start = function(prop, _def, skip_callback)
                prop.is_pressed = true
                prop.animation:resume()
                audio.play_sfx(audio.stone_slab_pressed)
                if prop.on_press and not skip_callback then
                    prop.on_press()
                end
            end,
            draw = draw_button
        },
        resetting = {
            start = function(prop, _def)
                prop.animation = Animation.new(BUTTON_ANIM, {
                    start_frame = BUTTON_ANIM.frame_count - 1,
                    reverse = true
                })
            end,
            update = function(prop, _dt)
                if prop.animation:is_finished() then
                    prop.is_pressed = false
                    Prop.set_state(prop, "unpressed")
                end
            end,
            draw = draw_button
        }
    }
}

--- Press the button (external API for hammer hits)
---@param prop table Button prop instance
function definition.press(prop)
    if not prop.is_pressed then
        Prop.set_state(prop, "pressed")
    end
end

--- Reset button to unpressed state with animation
---@param prop table Button prop instance
function definition.reset(prop)
    if prop.is_pressed then
        Prop.set_state(prop, "resetting")
    end
end

--- Save persistent button state
---@param prop table Button prop instance
---@return table state Saved state data
function definition.get_save_state(prop)
    return { state_name = prop.state_name }
end

--- Restore persistent button state silently (no sound) and re-fire callback
---@param prop table Button prop instance
---@param saved_state table Previously saved state data
function definition.restore_save_state(prop, saved_state)
    if saved_state.state_name == "pressed" then
        prop.is_pressed = true
        prop.animation = Animation.new(BUTTON_ANIM, {
            start_frame = BUTTON_ANIM.frame_count - 1
        })
        prop.animation:pause()
        prop.animation.flipped = prop.flipped
        prop.state = prop.states.pressed
        prop.state_name = "pressed"
        if prop.on_press then
            prop.on_press()
        end
    end
end

--- Re-fire callback for persistent buttons after campfire rest reset
---@param prop table Button prop instance
function definition.reapply_effects(prop)
    if prop.is_pressed and prop.on_press then
        prop.on_press()
    end
end

return definition
