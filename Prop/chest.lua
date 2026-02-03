--- Chest prop definition - Interactive treasure chest with shine animation
--- Supports optional key requirements and item rewards
local sprites = require("sprites")
local Animation = require("Animation")
local audio = require("audio")
local Collectible = require("Collectible")
local common = require("Prop/common")
local Effects = require("Effects")
local pickup_dialogue = require("ui/pickup_dialogue")
local Prop = require("Prop")
local TextDisplay = require("TextDisplay")
local unique_item_registry = require("Prop.unique_item_registry")

local CHEST_IDLE = Animation.create_definition(sprites.environment.brown_chest, 5, {
    ms_per_frame = 80,
    width = 16,
    height = 16,
    loop = true
})

local CHEST_OPENING = Animation.create_definition(sprites.environment.brown_chest_opening, 6, {
    ms_per_frame = 80,
    width = 16,
    height = 16,
    loop = false
})

-- Time to wait between shine cycles (seconds)
local SHINE_PAUSE_TIME = 2.0
-- Duration of one full shine animation cycle (5 frames * 80ms = 0.4s)
local SHINE_CYCLE_DURATION = 0.4

return {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#DAA520",  -- Goldenrod
    initial_state = "idle",
    default_reset = false,  -- Chests persist state across saves by default

    --- Get state data for saving (persistent props only)
    ---@param prop table The chest prop instance
    ---@return table state_data Data to save
    get_save_state = function(prop)
        return {
            state_name = prop.state_name,
            is_open = prop.is_open,
            gold_amount = prop.gold_amount,
            item_id = prop.item_id
        }
    end,

    --- Restore state from saved data
    ---@param prop table The chest prop instance
    ---@param saved_state table Saved state data
    restore_save_state = function(prop, saved_state)
        prop.is_open = saved_state.is_open
        prop.gold_amount = saved_state.gold_amount or 0
        prop.item_id = saved_state.item_id
        if saved_state.state_name and prop.states then
            Prop.set_state(prop, saved_state.state_name)
        end
    end,

    ---@param prop table The prop instance being spawned
    ---@param def table The chest definition
    ---@param options table Spawn options (contains gold, text, required_key, item_id)
    on_spawn = function(prop, def, options)
        local opts = options or {}
        prop.gold_amount = opts.gold or 0
        prop.required_key = opts.required_key
        prop.item_id = opts.item_id
        prop.is_open = false
        prop.timer = 0
        prop.shine_timer = 0
        prop.animation = Animation.new(CHEST_IDLE)
        prop.animation:pause()  -- Shine effect starts after idle delay, not immediately

        local default_text = "Open: {move_up}"
        prop.text_display = TextDisplay.new(opts.text or default_text, { anchor = "top" })
    end,

    states = {
        idle = {
            --- Initialize idle state animation
            ---@param prop table The chest prop instance
            ---@param def table The chest definition
            start = function(prop, def)
                if not prop.is_open then
                    prop.timer = 0
                    prop.shine_timer = 0
                    prop.animation = Animation.new(CHEST_IDLE)
                    prop.animation:pause()
                end
            end,

            --- Handle player interaction - open chest if not already opened
            ---@param prop table The chest prop instance
            ---@param player table The player instance
            ---@return boolean True if interaction occurred
            interact = function(prop, player)
                if prop.is_open then return false end

                -- Check key requirement
                if prop.required_key then
                    if not common.player_has_item(player, prop.required_key) then
                        Effects.create_locked_text(player.x + 0.5, player.y - 1, player)
                        audio.play_sfx(audio.locked_door)
                        return true
                    end
                    -- Consume the key (works for both stackable and unique items)
                    common.consume_stackable_item(player, prop.required_key)
                end

                prop.last_player = player
                Prop.set_state(prop, "opening")
                return true
            end,

            --- Handle shine animation cycling
            ---@param prop table The chest prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                if prop.is_open then return end

                -- Handle shine animation cycle
                if not prop.animation.playing then
                    -- Paused - wait for shine interval
                    prop.timer = prop.timer + dt
                    if prop.timer >= SHINE_PAUSE_TIME then
                        prop.animation:resume()
                        prop.shine_timer = 0
                    end
                else
                    -- Playing shine animation - track cycle completion
                    prop.shine_timer = prop.shine_timer + dt
                    if prop.shine_timer >= SHINE_CYCLE_DURATION then
                        prop.animation:pause()
                        prop.animation.frame = 0
                        prop.timer = 0
                    end
                end

                -- Update text display based on player proximity
                local touching = common.player_touching(prop, player)
                prop.text_display:update(dt, touching)
            end,

            draw = function(prop)
                common.draw(prop)
                prop.text_display:draw(prop.x, prop.y)
            end
        },

        opening = {
            --- Begin opening animation, spawn gold particles, and give item
            ---@param prop table The chest prop instance
            ---@param def table The chest definition
            start = function(prop, def)
                prop.animation = Animation.new(CHEST_OPENING)
                prop.is_open = true

                -- Spawn gold particles that will be collected by player
                if prop.gold_amount > 0 then
                    local cx = prop.x + 0.5  -- Center of chest
                    local cy = prop.y + 0.3  -- Slightly above center
                    Collectible.spawn_gold_burst(cx, cy, prop.gold_amount)
                    prop.gold_amount = 0  -- Prevent re-spawning
                end

                -- Give item to player
                if prop.item_id and prop.last_player then
                    local item_def = unique_item_registry[prop.item_id]
                    if item_def and item_def.type == "no_equip" then
                        -- Non-equippable items (keys) go directly to inventory
                        table.insert(prop.last_player.unique_items, prop.item_id)
                    elseif item_def then
                        -- Equippable items show the pickup dialogue
                        pickup_dialogue.show(prop.item_id, prop.last_player)
                    end
                    prop.item_id = nil  -- Prevent re-giving on load
                end
            end,

            --- Wait for opening animation to complete then transition to opened state
            ---@param prop table The chest prop instance
            ---@param dt number Delta time in seconds
            update = function(prop, dt)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "opened")
                end
            end,

            draw = common.draw
        },

        opened = {
            --- Set chest to final opened frame (static display)
            ---@param prop table The chest prop instance
            ---@param def table The chest definition
            start = function(prop, def)
                -- Reuse opening sprite sheet - frame 5 is the fully-open pose
                prop.animation = Animation.new(CHEST_OPENING, { start_frame = 5 })
                prop.animation:pause()
                prop.is_open = true
            end,

            --- Static state, no updates needed
            ---@param prop table The chest prop instance
            ---@param _dt number Delta time in seconds (unused)
            update = function(prop, _dt) end,

            draw = common.draw
        }
    }
}
