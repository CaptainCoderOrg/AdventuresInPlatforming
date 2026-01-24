--- Button prop definition - Binary state (unpressed/pressed) with callback
local Animation = require("Animation")
local audio = require("audio")
local Prop = require("Prop")
local sprites = require("sprites")

local BUTTON_ANIM = Animation.create_definition(sprites.environment.button, 5, {
    ms_per_frame = 100,
    width = 16,
    height = 8,
    loop = false
})

--- Shared draw function for button states
---@param prop table Button prop instance
local function draw_button(prop)
    local px = prop.x * sprites.tile_size
    local py = (prop.y + 0.5) * sprites.tile_size
    prop.animation:draw(px, py)
end

local definition = {
    box = { x = 0, y = 0.5, w = 1, h = 0.5 },
    debug_color = "#00FF00",
    initial_state = "unpressed",

    ---@param prop table The prop instance being spawned
    ---@param def table The button definition
    ---@param options table Spawn options, may contain on_press callback
    on_spawn = function(prop, def, options)
        prop.animation = Animation.new(BUTTON_ANIM)
        prop.animation:pause()
        prop.is_pressed = false
        prop.on_press = options.on_press
    end,

    states = {
        unpressed = {
            -- No start/update needed - static state until externally triggered
            draw = draw_button
        },
        pressed = {
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

return definition
