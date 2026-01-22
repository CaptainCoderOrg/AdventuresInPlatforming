--- Chest prop definition - Interactive treasure chest with shine animation
local sprites = require("sprites")
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")
local controls = require("controls")
local Effects = require("Effects")
local Prop = require("Prop")

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
            gold_amount = prop.gold_amount
        }
    end,

    --- Restore state from saved data
    ---@param prop table The chest prop instance
    ---@param saved_state table Saved state data
    restore_save_state = function(prop, saved_state)
        prop.is_open = saved_state.is_open
        prop.gold_amount = saved_state.gold_amount or 0
        if saved_state.state_name and prop.states then
            Prop.set_state(prop, saved_state.state_name)
        end
    end,

    ---@param prop table The prop instance being spawned
    ---@param def table The chest definition
    ---@param options table Spawn options (contains gold, text)
    on_spawn = function(prop, def, options)
        prop.gold_amount = options and options.gold or 0
        prop.is_open = false
        prop.timer = 0
        prop.shine_timer = 0
        prop.animation = Animation.new(CHEST_IDLE)
        prop.animation:pause()  -- Shine effect starts after idle delay, not immediately

        local text = options and options.text or "Open\n{move_down} + {attack}"
        prop.text_display = TextDisplay.new(text, { anchor = "top" })
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

            --- Handle shine animation cycling and player interaction
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

                -- Check for player interaction
                local touching = common.player_touching(prop, player)
                if touching and player then
                    prop.last_player = player
                    if controls.down_down() and controls.attack_pressed() then
                        Prop.set_state(prop, "opening")
                    end
                end

                prop.text_display:update(dt, touching)
            end,

            draw = function(prop)
                common.draw(prop)
                prop.text_display:draw(prop.x, prop.y)
            end
        },

        opening = {
            --- Begin opening animation and award gold to player
            ---@param prop table The chest prop instance
            ---@param def table The chest definition
            start = function(prop, def)
                prop.animation = Animation.new(CHEST_OPENING)
                prop.is_open = true

                -- Award gold and show effect
                if prop.gold_amount > 0 then
                    if prop.last_player then
                        prop.last_player.gold = prop.last_player.gold + prop.gold_amount
                    end
                    Effects.create_gold_text(prop.x, prop.y, prop.gold_amount)
                    prop.gold_amount = 0  -- Prevent re-awarding
                end
            end,

            --- Wait for opening animation to complete then transition to opened state
            ---@param prop table The chest prop instance
            ---@param dt number Delta time in seconds (handled by Prop.update via animation:play)
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
            ---@param dt number Delta time in seconds
            update = function(prop, dt) end,

            draw = common.draw
        }
    }
}
