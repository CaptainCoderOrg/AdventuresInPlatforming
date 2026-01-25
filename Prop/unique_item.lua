--- Unique Item prop definition - Permanent collectibles that persist across saves
--- Items are stored on player.unique_items for gameplay checks (e.g., locked doors)
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")

local ANIM_SIZE = 16

--- Item registry - defines all unique items and their sprites
local ITEMS = {
    gold_key = {
        name = "Gold Key",
        spin_sprite = sprites.environment.gold_key_spin,
        collected_sprite = sprites.environment.gold_key_collected,
        spin_frames = 8,
        collected_frames = 5,
        collect_sfx = audio.pick_up_key,
    }
}

--- Create animation definition with common size settings
---@param sprite string Sprite identifier
---@param frames number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@param loop boolean Whether animation loops
---@return table Animation definition
local function create_item_anim(sprite, frames, ms_per_frame, loop)
    return Animation.create_definition(sprite, frames, {
        ms_per_frame = ms_per_frame,
        width = ANIM_SIZE,
        height = ANIM_SIZE,
        loop = loop
    })
end

-- Pre-compute animation definitions at module load time
for _, item in pairs(ITEMS) do
    item.spin_anim = create_item_anim(item.spin_sprite, item.spin_frames, 160, true)
    item.collected_anim = create_item_anim(item.collected_sprite, item.collected_frames, 160, false)
end

--- Check if this item should spawn (not already in player's inventory)
---@param options table Spawn options containing item_id
---@param player table Player instance
---@return boolean True if item should spawn
local function should_spawn(options, player)
    if not options or not options.item_id then return true end
    return not common.player_has_item(player, options.item_id)
end

return {
    box = { x = -0.5, y = 0, w = 2, h = 1 },
    debug_color = "#FFD700",  -- Gold
    initial_state = "idle",

    --- Determines if this item should spawn (not collected yet)
    should_spawn = should_spawn,

    ---@param prop table The prop instance being spawned
    ---@param _def table The unique_item definition (unused)
    ---@param options table Spawn options (contains item_id)
    on_spawn = function(prop, _def, options)
        prop.item_id = options and options.item_id or "gold_key"
        prop.item = ITEMS[prop.item_id] or ITEMS.gold_key

        prop.animation = Animation.new(prop.item.spin_anim)
        prop.text_display = TextDisplay.new("Collect\n{move_up}", { anchor = "top" })
    end,

    states = {
        idle = {
            --- Handle player interaction - collect the item
            ---@param prop table The unique_item prop instance
            ---@param player table The player instance
            ---@return boolean True if interaction occurred
            interact = function(prop, player)
                prop.last_player = player
                Prop.set_state(prop, "collect")
                return true
            end,

            ---@param prop table The unique_item prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                local touching = player and common.player_touching(prop, player)
                prop.text_display:update(dt, touching)
            end,

            ---@param prop table The unique_item prop instance
            draw = function(prop)
                common.draw(prop)
                prop.text_display:draw(prop.x, prop.y)
            end
        },

        collect = {
            ---@param prop table The unique_item prop instance
            start = function(prop)
                prop.animation = Animation.new(prop.item.collected_anim)

                -- Add to player's unique_items (item_id is always set in on_spawn)
                if prop.last_player then
                    table.insert(prop.last_player.unique_items, prop.item_id)
                end
                audio.play_sfx(prop.item.collect_sfx or audio.default_collect_sfx)
            end,

            ---@param prop table The unique_item prop instance
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "collected")
                end
            end,

            draw = common.draw
        },

        collected = {
            ---@param prop table The unique_item prop instance
            start = function(prop)
                prop.marked_for_destruction = true
            end
        }
    }
}
