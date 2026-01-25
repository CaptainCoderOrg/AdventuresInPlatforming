--- Appearing bridge prop - One-way platform that fades in/out with sequenced animation
--- Triggered by lever group actions (appear/disappear)
local canvas = require("canvas")
local config = require("config")
local Prop = require("Prop")
local sprites = require("sprites")
local world = require("world")

-- Timing constants
local FADE_DURATION = 0.15  -- Each tile's fade time in seconds
local TILE_DELAY = 0.08     -- Delay between adjacent tiles in seconds

--- Setup tile ordering for the group on first group_action call
--- Sorts tiles by X position and assigns sprite types based on neighbors
---@param prop table Bridge prop instance
local function setup_group(prop)
    local group = Prop.groups[prop.group]
    if not group or group._setup_complete then return end

    -- Sort group by X position (left to right)
    table.sort(group, function(a, b) return a.x < b.x end)

    -- Assign tile properties: index, group size, and sprite type based on neighbors
    local count = #group
    for i, p in ipairs(group) do
        p.tile_index = i - 1  -- 0-based index for delay calculation
        p.group_size = count

        -- Determine sprite type based on adjacent tiles
        local has_left = i > 1 and group[i - 1].x == p.x - 1
        local has_right = i < count and group[i + 1].x == p.x + 1

        if not has_left then
            p.sprite_type = "left"
        elseif not has_right then
            p.sprite_type = "right"
        else
            p.sprite_type = "middle"
        end
    end

    group._setup_complete = true
end

-- Sprite lookup by position type
local SPRITE_MAP = {
    left = sprites.environment.bridge_left,
    right = sprites.environment.bridge_right,
    middle = sprites.environment.bridge_middle
}

--- Get the appropriate sprite for this bridge tile
---@param prop table Bridge prop instance
---@return string sprite The sprite to draw
local function get_sprite(prop)
    return SPRITE_MAP[prop.sprite_type]
end

--- Calculate the fade delay for this tile based on direction and position
---@param prop table Bridge prop instance
---@param reverse boolean True for right-to-left (disappearing)
---@return number delay Delay in seconds before this tile starts fading
local function get_tile_delay(prop, reverse)
    local index = prop.tile_index or 0
    if reverse then
        -- Reverse order: rightmost tile starts first
        index = (prop.group_size or 1) - 1 - index
    end
    return index * TILE_DELAY
end

--- Update fade progress for appearing/disappearing states
---@param prop table Bridge prop instance
---@param dt number Delta time in seconds
---@param fade_in boolean True for fade in (0->1), false for fade out (1->0)
---@param next_state string State to transition to when fade completes
local function update_fade(prop, dt, fade_in, next_state)
    prop.fade_timer = prop.fade_timer + dt
    local effective_time = prop.fade_timer - prop.fade_delay

    if effective_time < 0 then
        prop.fade_progress = fade_in and 0 or 1
    elseif effective_time >= FADE_DURATION then
        prop.fade_progress = fade_in and 1 or 0
        Prop.set_state(prop, next_state)
    else
        local progress = effective_time / FADE_DURATION
        prop.fade_progress = fade_in and progress or (1 - progress)
    end
end

--- Draw the bridge tile with current alpha
---@param prop table Bridge prop instance
local function draw_with_alpha(prop)
    local alpha = prop.fade_progress or 0
    if alpha <= 0 then return end

    local ts = sprites.tile_size
    local px = prop.x * ts
    local py = prop.y * ts

    canvas.set_global_alpha(alpha)
    sprites.draw_bridge(px, py, get_sprite(prop))
    canvas.set_global_alpha(1)

    -- Debug bounding box (cyan for bridge colliders)
    if config.bounding_boxes and prop.collider_shape then
        canvas.set_color("#00FFFF")
        canvas.draw_rect(
            (prop.x + prop.box.x) * ts,
            (prop.y + prop.box.y) * ts,
            prop.box.w * ts,
            prop.box.h * ts
        )
    end
end

local definition = {
    box = { x = 0, y = 0, w = 1, h = 0.2 },  -- Thin collider at top, same as platform bridges
    debug_color = "#00FFFF",  -- Cyan
    initial_state = "hidden",

    ---@param prop table The prop instance being spawned
    ---@param _def table The prop definition (unused)
    ---@param _options table Spawn options (group is handled by Prop.spawn)
    on_spawn = function(prop, _def, _options)
        prop.fade_progress = 0
        prop.fade_timer = 0
        prop.tile_index = 0
        prop.group_size = 1
        prop.sprite_type = "middle"
        prop.is_bridge = true  -- Flag on owner for world.lua bridge detection
    end,

    states = {
        --- Hidden state - no collider, no rendering
        hidden = {
            start = function(prop)
                -- Remove collider if it exists
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                prop.fade_progress = 0
                prop.fade_timer = 0
            end
        },

        --- Appearing state - collider added immediately, alpha fades 0->1 with per-tile delay
        appearing = {
            start = function(prop)
                -- Add collider immediately so player can walk on it
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
                prop.fade_timer = 0
                prop.fade_delay = get_tile_delay(prop, false)
            end,
            update = function(prop, dt)
                update_fade(prop, dt, true, "visible")
            end,
            draw = draw_with_alpha
        },

        --- Visible state - full alpha, collider active
        visible = {
            start = function(prop)
                prop.fade_progress = 1
                -- Ensure collider exists
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,
            draw = draw_with_alpha
        },

        --- Disappearing state - collider removed immediately, alpha fades 1->0 with reversed delay
        disappearing = {
            start = function(prop)
                -- Remove collider immediately so player falls through
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                prop.fade_timer = 0
                prop.fade_delay = get_tile_delay(prop, true)
            end,
            update = function(prop, dt)
                update_fade(prop, dt, false, "hidden")
            end,
            draw = draw_with_alpha
        }
    }
}

--- Trigger appear action (called via Prop.group_action)
--- Transitions from hidden to appearing
---@param prop table Bridge prop instance
function definition.appear(prop)
    setup_group(prop)
    if prop.state_name == "hidden" or prop.state_name == "disappearing" then
        Prop.set_state(prop, "appearing")
    end
end

--- Trigger disappear action (called via Prop.group_action)
--- Transitions from visible to disappearing
---@param prop table Bridge prop instance
function definition.disappear(prop)
    setup_group(prop)
    if prop.state_name == "visible" or prop.state_name == "appearing" then
        Prop.set_state(prop, "disappearing")
    end
end

--- Reset to hidden state (used by Prop.reset_all)
---@param prop table Bridge prop instance
function definition.reset(prop)
    Prop.set_state(prop, "hidden")
end

return definition
