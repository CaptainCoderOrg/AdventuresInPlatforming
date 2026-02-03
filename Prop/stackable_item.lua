--- Stackable Item prop definition - Consumable collectibles (keys, etc.)
--- Items are stored in player.stackable_items as counts
--- Always spawns (can be collected multiple times across playthroughs)
local audio = require("audio")
local canvas = require("canvas")
local common = require("Prop/common")
local Effects = require("Effects")
local ITEMS = require("Prop/stackable_item_registry")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")

local BOB_SPEED = 4       -- Radians per second
local BOB_AMPLITUDE = 0.1 -- Tiles
local FADE_DURATION = 0.4 -- Seconds

--- Draws item sprite with bob offset and optional alpha
---@param prop table The stackable_item prop instance
---@param alpha number|nil Optional alpha for fade effect (1.0 if nil)
local function draw_item(prop, alpha)
    local bob_offset = math.sin(prop.bob_timer * BOB_SPEED) * BOB_AMPLITUDE
    local px = sprites.px(prop.x)
    local py = sprites.px(prop.y + bob_offset)
    if alpha and alpha < 1 then
        canvas.set_global_alpha(alpha)
    end
    canvas.draw_image(prop.item.static_sprite, px, py,
        sprites.tile_size, sprites.tile_size)
    if alpha and alpha < 1 then
        canvas.set_global_alpha(1)
    end
end

return {
    box = { x = -0.5, y = 0, w = 2, h = 1 },
    debug_color = "#C0C0C0",  -- Silver (to distinguish from gold unique items)
    initial_state = "idle",
    default_reset = false,  -- Persist collected state across saves

    --- Get state data for saving (persistent props only)
    ---@param prop table The stackable_item prop instance
    ---@return table state_data Data to save
    get_save_state = function(prop)
        return { collected = prop.collected }
    end,

    --- Restore state from saved data
    ---@param prop table The stackable_item prop instance
    ---@param saved_state table Saved state data
    restore_save_state = function(prop, saved_state)
        if saved_state.collected then
            prop.collected = true
            Prop.set_state(prop, "collected")
        end
    end,

    ---@param prop table The prop instance being spawned
    ---@param _def table The stackable_item definition (unused)
    ---@param options table Spawn options (contains item_id, count)
    on_spawn = function(prop, _def, options)
        prop.item_id = options and options.item_id or "dungeon_key"
        prop.item = ITEMS[prop.item_id] or ITEMS.dungeon_key
        prop.count = options and options.count or 1

        -- Static items need manual bob timer for floating effect
        prop.bob_timer = 0
        prop.text_display = TextDisplay.new("Take: {move_up}", { anchor = "top" })
    end,

    states = {
        idle = {
            ---@param _prop table The stackable_item prop instance (unused)
            start = function(_prop) end,

            --- Handle player interaction - collect the item
            ---@param prop table The stackable_item prop instance
            ---@param player table The player instance
            ---@return boolean True if interaction occurred
            interact = function(prop, player)
                prop.last_player = player
                Prop.set_state(prop, "collect")
                return true
            end,

            ---@param prop table The stackable_item prop instance
            ---@param dt number Delta time in seconds
            ---@param player table|nil The player object (nil during loading)
            update = function(prop, dt, player)
                local touching = player and common.player_touching(prop, player)
                prop.text_display:update(dt, touching)

                -- Update bob timer
                prop.bob_timer = prop.bob_timer + dt
            end,

            ---@param prop table The stackable_item prop instance
            draw = function(prop)
                draw_item(prop)
                prop.text_display:draw(prop.x, prop.y)
            end
        },

        collect = {
            ---@param prop table The stackable_item prop instance
            start = function(prop)
                -- Mark as collected for persistence
                prop.collected = true

                -- Add to player's stackable items
                if prop.last_player then
                    common.add_stackable_item(prop.last_player, prop.item_id, prop.count)
                end

                -- Play collection sound
                audio.play_sfx(prop.item.collect_sfx or audio.default_collect_sfx)

                -- Start fade effect with particles
                prop.fade_elapsed = 0
                Effects.create_collect_particles(prop.x + 0.5, prop.y + 0.5)
            end,

            ---@param prop table The stackable_item prop instance
            ---@param dt number Delta time in seconds
            update = function(prop, dt, _player)
                -- Wait for fade to complete
                prop.fade_elapsed = prop.fade_elapsed + dt
                if prop.fade_elapsed >= FADE_DURATION then
                    Prop.set_state(prop, "collected")
                end
            end,

            ---@param prop table The stackable_item prop instance
            draw = function(prop)
                local alpha = 1 - prop.fade_elapsed / FADE_DURATION
                draw_item(prop, alpha)
            end
        },

        collected = {
            --- Item stays in world but invisible (so state persists for saving)
            ---@param _prop table The stackable_item prop instance
            start = function(_prop) end,

            ---@param _prop table Unused (invisible)
            ---@param _dt number Unused
            ---@param _player table Unused
            update = function(_prop, _dt, _player) end,

            ---@param _prop table Unused (invisible)
            draw = function(_prop) end
        }
    }
}
