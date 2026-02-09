--- Unique Item prop definition - Permanent collectibles that persist across saves
--- Items are stored on player.unique_items for gameplay checks (e.g., locked doors)
--- Supports animated items (spin/collected sprites) and static items (bob/fade)
local Animation = require("Animation")
local audio = require("audio")
local canvas = require("canvas")
local common = require("Prop/common")
local map_panel = require("ui/map_panel")
local Effects = require("Effects")
local ITEMS = require("Prop/unique_item_registry")
local pickup_dialogue = require("ui/pickup_dialogue")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")

local ANIM_SIZE = 16
local BOB_SPEED = 4       -- Radians per second
local BOB_AMPLITUDE = 0.1 -- Tiles
local FADE_DURATION = 0.4 -- Seconds

--- Draws a static item sprite with bob offset
---@param prop table The unique_item prop instance
---@param alpha number|nil Optional alpha (1.0 if nil)
local function draw_static_item(prop, alpha)
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

--- Draws item sprite (animated or static) with optional alpha
---@param prop table The unique_item prop instance
---@param alpha number|nil Optional alpha for fade effect (1.0 if nil)
local function draw_item(prop, alpha)
    if prop.animation then
        common.draw(prop)
    else
        draw_static_item(prop, alpha)
    end
end

--- Create animation definition with common size settings
---@param sprite string Sprite identifier
---@param frames number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@param loop boolean Whether animation loops
---@return table def Animation definition for Animation.new()
local function create_item_anim(sprite, frames, ms_per_frame, loop)
    return Animation.create_definition(sprite, frames, {
        ms_per_frame = ms_per_frame,
        width = ANIM_SIZE,
        height = ANIM_SIZE,
        loop = loop
    })
end

-- Pre-compute animation definitions for animated items at module load time
for _, item in pairs(ITEMS) do
    if item.animated_sprite then
        item.animated_anim = create_item_anim(item.animated_sprite, item.animated_frames, 160, true)
        if item.collected_sprite then
            item.collected_anim = create_item_anim(item.collected_sprite, item.collected_frames, 160, false)
        end
    end
end

--- Start the collection animation or fade effect for a prop
--- Handles both animated items (collected animation) and static items (fade + particles)
---@param prop table The unique_item prop instance
local function start_collection_effect(prop)
    if prop.item.animated_anim then
        if prop.item.collected_anim then
            prop.animation = Animation.new(prop.item.collected_anim)
        else
            Prop.set_state(prop, "collected")
        end
    else
        prop.fade_elapsed = 0
        Effects.create_collect_particles(prop.x + 0.5, prop.y + 0.5)
    end
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

        -- Animated items have pre-defined animations, static items need manual bob timer for floating effect
        if prop.item.animated_anim then
            prop.animation = Animation.new(prop.item.animated_anim)
        else
            prop.bob_timer = 0
        end
        prop.text_display = TextDisplay.new("Take: {move_up}", { anchor = "top" })
    end,

    states = {
        idle = {
            ---@param _prop table The unique_item prop instance (unused)
            start = function(_prop) end,

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
            ---@param player table|nil The player object (nil during loading)
            update = function(prop, dt, player)
                local touching = player and common.player_touching(prop, player)
                prop.text_display:update(dt, touching)

                -- Update bob timer for static items
                if prop.bob_timer then
                    prop.bob_timer = prop.bob_timer + dt
                end
            end,

            ---@param prop table The unique_item prop instance
            draw = function(prop)
                draw_item(prop)
                prop.text_display:draw(prop.x, prop.y)
            end
        },

        collect = {
            ---@param prop table The unique_item prop instance
            start = function(prop)
                map_panel.remove_collectible(prop.x, prop.y)
                -- Check if this item type is equippable (shows dialogue)
                local item_type = prop.item.type
                local is_equippable = item_type and item_type ~= "no_equip"

                if is_equippable and prop.last_player then
                    -- Equippable item - show pickup dialogue
                    prop.pending_dialogue = true
                    pickup_dialogue.show(prop.item_id, prop.last_player, function()
                        -- Callback when dialogue closes - continue collection animation
                        prop.pending_dialogue = false
                        audio.play_sfx(prop.item.collect_sfx or audio.default_collect_sfx)
                        start_collection_effect(prop)
                    end)
                else
                    -- Non-equippable item - immediate add to inventory
                    if prop.last_player then
                        table.insert(prop.last_player.unique_items, prop.item_id)
                    end
                    audio.play_sfx(prop.item.collect_sfx or audio.default_collect_sfx)
                    start_collection_effect(prop)
                end
            end,

            ---@param prop table The unique_item prop instance
            ---@param dt number Delta time in seconds
            update = function(prop, dt, _player)
                -- Skip update while waiting for dialogue
                if prop.pending_dialogue then return end

                if prop.animation then
                    -- Animated item - wait for animation to finish
                    if prop.animation:is_finished() then
                        Prop.set_state(prop, "collected")
                    end
                else
                    -- Static item - wait for fade to complete
                    prop.fade_elapsed = prop.fade_elapsed + dt
                    if prop.fade_elapsed >= FADE_DURATION then
                        Prop.set_state(prop, "collected")
                    end
                end
            end,

            ---@param prop table The unique_item prop instance
            draw = function(prop)
                if prop.pending_dialogue then
                    draw_item(prop)
                    return
                end
                local alpha = prop.animation and 1 or (1 - prop.fade_elapsed / FADE_DURATION)
                draw_item(prop, alpha)
            end
        },

        collected = {
            --- Mark item for destruction after collection animation
            ---@param prop table The unique_item prop instance
            start = function(prop)
                prop.marked_for_destruction = true
            end,

            ---@param _prop table Unused (entity destroyed immediately)
            ---@param _dt number Unused
            ---@param _player table Unused
            update = function(_prop, _dt, _player) end,

            ---@param _prop table Unused (entity destroyed immediately)
            draw = function(_prop) end
        }
    }
}
