--- Shared utilities for NPC prop definitions
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")
local dialogue_screen = require("ui/dialogue_screen")
local shop_screen = require("ui/shop_screen")

local npc_common = {}

-- References set by main.lua for dialogue/shop screens
local player_ref = nil
local camera_ref = nil

--- Set references needed for dialogue/shop screens
---@param player table Player instance
---@param camera table Camera instance
function npc_common.set_refs(player, camera)
    player_ref = player
    camera_ref = camera
end

--- Get the camera reference
---@return table|nil Camera instance or nil if not set
function npc_common.get_camera()
    return camera_ref
end

--- Create an NPC prop definition from configuration
--- All NPCs share the same interact/update/draw patterns with different:
---   - Animation (sprite, frame count, timing, dimensions)
---   - Collision box size
---   - Dialogue text (simple fallback)
---   - Draw width (for text display centering)
--- Dialogue trees and shop IDs are specified via Tiled properties:
---   - on_dialogue: dialogue tree ID (from dialogue/registry)
---   - shop_id: shop inventory ID (from shop/registry)
---@param config {sprite: string, frame_count: number, ms_per_frame: number, width: number, height: number, dialogue: string|nil, box_size: number|nil, draw_width: number|nil} NPC configuration
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
        -- 1 tile x-axis padding on each side for easier interaction
        box = { x = -1, y = 0, w = box_size + 2, h = box_size },
        debug_color = "#FF00FF",

        ---@param prop table The NPC prop instance
        ---@param _player table The player instance (unused)
        ---@return boolean True to indicate interaction was handled
        interact = function(prop, _player)
            -- Priority: shop > dialogue tree > simple dialogue
            -- These are set from Tiled properties in on_spawn
            if prop.shop_id and player_ref and camera_ref then
                shop_screen.start(prop.shop_id, player_ref, camera_ref)
                return true
            elseif prop.on_dialogue and player_ref and camera_ref then
                dialogue_screen.start(prop.on_dialogue, player_ref, camera_ref)
                return true
            elseif prop.dialogue_display then
                -- Fall back to simple dialogue display
                prop.dialogue_display.visible = true
                return true
            end
            return false
        end,

        ---@param prop table The prop instance being spawned
        ---@param _def table The NPC definition (unused)
        ---@param options table Spawn options from Tiled (on_dialogue, shop_id)
        on_spawn = function(prop, _def, options)
            prop.animation = Animation.new(animation_def)
            prop.text_display = TextDisplay.new("Talk\n{move_up}", { anchor = "top" })

            -- Store Tiled properties for use in interact
            prop.on_dialogue = options.on_dialogue
            prop.shop_id = options.shop_id

            -- Only create simple dialogue display if no dialogue tree or shop
            if not options.on_dialogue and not options.shop_id then
                prop.dialogue_display = TextDisplay.new(config.dialogue or "", { anchor = "top" })
                prop.dialogue_display.visible = false
            end
        end,

        ---@param prop table NPC prop instance
        ---@param dt number Delta time in seconds
        ---@param player table Player instance for proximity check
        update = function(prop, dt, player)
            local is_active = common.player_touching(prop, player)
            -- Don't show "Talk" prompt during dialogue/shop
            local in_dialogue = dialogue_screen.is_active() or shop_screen.is_active()
            prop.text_display:update(dt, is_active and not in_dialogue and not (prop.dialogue_display and prop.dialogue_display.visible))

            if prop.dialogue_display then
                prop.dialogue_display:update(dt, prop.dialogue_display.visible)
                if not is_active then
                    prop.dialogue_display.visible = false
                end
            end
        end,

        ---@param prop table NPC prop instance
        draw = function(prop)
            common.draw(prop)
            prop.text_display:draw(prop.x, prop.y, draw_width)
            if prop.dialogue_display then
                prop.dialogue_display:draw(prop.x, prop.y - 1, draw_width)
            end
        end,
    }
end

return npc_common
