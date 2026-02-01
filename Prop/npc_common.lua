--- Shared utilities for NPC prop definitions
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")

local npc_common = {}

--- Create an NPC prop definition from configuration
--- All NPCs share the same interact/update/draw patterns with different:
---   - Animation (sprite, frame count, timing, dimensions)
---   - Collision box size
---   - Dialogue text
---   - Draw width (for text display centering)
---@param config {sprite: string, frame_count: number, ms_per_frame: number, width: number, height: number, dialogue: string, box_size: number|nil, draw_width: number|nil} NPC configuration
---@return table NPC prop definition
function npc_common.create(config)
    local animation_def = Animation.create_definition(config.sprite, config.frame_count, {
        ms_per_frame = config.ms_per_frame,
        width = config.width,
        height = config.height,
        loop = true
    })

    local box_size = config.box_size or 1
    local draw_width = config.draw_width or box_size

    return {
        box = { x = 0, y = 0, w = box_size, h = box_size },
        debug_color = "#FF00FF",

        ---@param prop table The NPC prop instance
        ---@param _player table The player instance (unused)
        ---@return boolean True to indicate interaction was handled
        interact = function(prop, _player)
            prop.dialogue_display.visible = true
            return true
        end,

        ---@param prop table The prop instance being spawned
        ---@param _def table The NPC definition (unused)
        ---@param _options table Spawn options (unused)
        on_spawn = function(prop, _def, _options)
            prop.animation = Animation.new(animation_def)
            prop.text_display = TextDisplay.new("Talk\n{move_up}", { anchor = "top" })
            prop.dialogue_display = TextDisplay.new(config.dialogue, { anchor = "top" })
            prop.dialogue_display.visible = false
        end,

        ---@param prop table NPC prop instance
        ---@param dt number Delta time in seconds
        ---@param player table Player instance for proximity check
        update = function(prop, dt, player)
            local is_active = common.player_touching(prop, player)
            prop.text_display:update(dt, is_active and not prop.dialogue_display.visible)
            prop.dialogue_display:update(dt, prop.dialogue_display.visible)

            if not is_active then
                prop.dialogue_display.visible = false
            end
        end,

        ---@param prop table NPC prop instance
        draw = function(prop)
            common.draw(prop)
            prop.text_display:draw(prop.x, prop.y, draw_width)
            prop.dialogue_display:draw(prop.x, prop.y - 1, draw_width)
        end,
    }
end

return npc_common
