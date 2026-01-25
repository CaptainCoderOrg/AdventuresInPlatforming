--- Lever prop definition - Toggleable switch that fires callbacks on state changes
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")

local LEVER_IDLE = Animation.create_definition(sprites.environment.lever, 1, {
    ms_per_frame = 100,
    width = 16,
    height = 16,
    loop = false
})

local LEVER_TOGGLE = Animation.create_definition(sprites.environment.lever_switch, 5, {
    ms_per_frame = 80,
    width = 16,
    height = 16,
    loop = false
})

--- Draw lever with text display (used in idle states)
---@param prop table Lever prop instance
local function draw_with_text(prop)
    common.draw(prop)
    prop.text_display:draw(prop.x, prop.y)
end

--- Update text display visibility based on player proximity
---@param prop table Lever prop instance
---@param dt number Delta time in seconds
---@param player table The player object
local function update_text_display(prop, dt, player)
    local touching = common.player_touching(prop, player)
    prop.text_display:update(dt, touching)
end

--- Handle lever interaction (toggle from left/right states)
---@param prop table Lever prop instance
---@return boolean True to indicate interaction was handled
local function toggle_interact(prop)
    prop.definition.toggle(prop)
    return true
end

--- Initialize lever position state (left or right)
---@param prop table Lever prop instance
---@param flipped number Direction to face (-1 = left, 1 = right)
---@param callback function|nil Callback to fire on state entry
local function start_position(prop, flipped, callback)
    -- Handle initial state redirect (spawns always start in "left", redirect if needed)
    local requested = prop._requested_initial_state
    if requested and requested ~= prop.state_name then
        prop._requested_initial_state = nil
        Prop.set_state(prop, requested)
        return
    end
    prop._requested_initial_state = nil

    prop.animation = Animation.new(LEVER_IDLE)
    prop.animation:pause()
    prop.flipped = flipped

    -- Fire callback (skip on initial spawn since other props may not exist yet)
    if prop._skip_initial_callback then
        prop._skip_initial_callback = nil
    elseif callback then
        callback()
    end
end

local definition = {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#FF00FF",
    initial_state = "left",

    ---@param prop table The prop instance being spawned
    ---@param _def table The lever definition (unused)
    ---@param options table Spawn options: initial_state, on_left, on_right
    on_spawn = function(prop, _def, options)
        prop.on_left = options.on_left
        prop.on_right = options.on_right
        prop._requested_initial_state = options.initial_state
        prop._skip_initial_callback = true  -- Don't fire callback on spawn

        local text = options.text or "Pull\n{move_up}"
        prop.text_display = TextDisplay.new(text, { anchor = "top" })
    end,

    states = {
        left = {
            start = function(prop) start_position(prop, -1, prop.on_left) end,
            interact = toggle_interact,
            update = update_text_display,
            draw = draw_with_text
        },
        right = {
            start = function(prop) start_position(prop, 1, prop.on_right) end,
            interact = toggle_interact,
            update = update_text_display,
            draw = draw_with_text
        },
        toggling = {
            ---@param prop table Lever prop instance
            start = function(prop)
                prop.flipped = prop.target_state == "right" and 1 or -1
                prop.animation = Animation.new(LEVER_TOGGLE)
                audio.play_sfx(audio.stone_slab_pressed)
            end,
            ---@param prop table Lever prop instance
            update = function(prop)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, prop.target_state)
                end
            end,
            draw = common.draw
        }
    }
}

--- Toggle the lever to the opposite position
---@param prop table Lever prop instance
function definition.toggle(prop)
    if prop.state_name == "toggling" then return end
    prop.target_state = prop.state_name == "left" and "right" or "left"
    Prop.set_state(prop, "toggling")
end

--- Check if lever is in left position
---@param prop table Lever prop instance
---@return boolean
function definition.is_left(prop)
    return prop.state_name == "left"
end

--- Check if lever is in right position
---@param prop table Lever prop instance
---@return boolean
function definition.is_right(prop)
    return prop.state_name == "right"
end

--- Reset lever to initial state (used by Prop.reset_all)
---@param prop table Lever prop instance
function definition.reset(prop)
    Prop.set_state(prop, definition.initial_state)
end

return definition
