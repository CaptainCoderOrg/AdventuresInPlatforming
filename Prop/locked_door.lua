--- Locked door prop definition - Blocks passage until unlocked
--- Can be unlocked by: required_key (player has item), or group_action("unlock")
local Animation = require("Animation")
local audio = require("audio")
local common = require("Prop/common")
local Effects = require("Effects")
local Prop = require("Prop")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local world = require("world")

--- Create door animation definition with standard size settings
---@param sprite string Sprite identifier
---@param frames number Number of frames
---@param ms_per_frame number Milliseconds per frame
---@return table Animation definition
local function create_door_anim(sprite, frames, ms_per_frame)
    return Animation.create_definition(sprite, frames, {
        ms_per_frame = ms_per_frame,
        width = 16,
        height = 32,
        loop = false
    })
end

local DOOR_LOCKED = create_door_anim(sprites.environment.locked_door_idle, 6, 160)
local DOOR_LOCKED_JIGGLE = create_door_anim(sprites.environment.locked_door_jiggle, 5, 80)
local DOOR_UNLOCK = create_door_anim(sprites.environment.locked_door_open, 13, 80)

local combat = require("combat")

-- Module-level filter to avoid closure allocation per query
local _filter_player = nil
local function player_filter(entity)
    return entity == _filter_player
end

--- Check if player overlaps a box relative to prop position
---@param prop table The door prop instance
---@param player table The player instance
---@param box table Box with x, y, w, h in tiles
---@return boolean True if player overlaps the box
local function player_overlaps_box(prop, player, box)
    if not player then return false end
    _filter_player = player
    local results = combat.query_rect(
        prop.x + box.x,
        prop.y + box.y,
        box.w,
        box.h,
        player_filter
    )
    return results[1] ~= nil
end

return {
    box = { x = -1, y = 0, w = 3, h = 2 },  -- Wide for interaction detection
    collider_box = { x = 0, y = 0, w = 1, h = 2 },  -- Narrow for world collision
    debug_color = "#8B4513",
    initial_state = "locked",
    default_reset = false,  -- Persist door state across saves

    --- Get state data for saving (persistent props only)
    ---@param prop table The door prop instance
    ---@return table state_data Data to save
    get_save_state = function(prop)
        return { state_name = prop.state_name }
    end,

    --- Restore state from saved data
    ---@param prop table The door prop instance
    ---@param saved_state table Saved state data
    restore_save_state = function(prop, saved_state)
        if saved_state.state_name then
            Prop.set_state(prop, saved_state.state_name)
        end
    end,

    ---@param prop table The prop instance being spawned
    ---@param _def table The door definition (unused)
    ---@param options table Spawn options (contains required_key)
    on_spawn = function(prop, _def, options)
        prop.required_key = options and options.required_key
        if prop.required_key then
            prop.text_display = TextDisplay.new("Open: {move_up}", { anchor = "top" })
        end
    end,

    states = {
        locked = {
            ---@param prop table The door prop instance
            start = function(prop)
                prop._timer = 0
                prop.was_touching = false
                -- Preserve bump_cooldown across state transitions (jiggle -> locked)
                prop.bump_cooldown = prop.bump_cooldown or 0
                prop.animation = Animation.new(DOOR_LOCKED)
                if not prop.collider_shape then
                    -- Use narrow collider_box for world collision (not the wide interaction box)
                    local cbox = prop.definition.collider_box
                    prop.collider_shape = world.add_collider_box(prop, cbox)
                end
            end,

            --- Handle player interaction - unlock if player has key, else show feedback
            ---@param prop table The door prop instance
            ---@param player table The player instance
            ---@param from_bump boolean|nil True if triggered by bumping into door
            ---@return boolean True if interaction occurred
            interact = function(prop, player, from_bump)
                if not prop.required_key then return false end
                if common.player_has_item(player, prop.required_key) then
                    -- Show key name above player
                    local item_def = common.get_item_def(prop.required_key)
                    if item_def and item_def.name then
                        Effects.create_text(player.x, player.y, item_def.name)
                    end
                    -- Consume the key
                    common.consume_stackable_item(player, prop.required_key)
                    Prop.set_state(prop, "unlock")
                else
                    Effects.create_locked_text(player.x + 0.5, player.y - 1, player)
                    Prop.set_state(prop, "jiggle")
                    -- Debounce bump interactions to prevent spam
                    if from_bump then
                        prop.bump_cooldown = 1
                    end
                end
                return true
            end,

            ---@param prop table The door prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                local in_range = player_overlaps_box(prop, player, prop.box)
                local touching_collider = player_overlaps_box(prop, player, prop.definition.collider_box)

                if prop.bump_cooldown > 0 then
                    prop.bump_cooldown = prop.bump_cooldown - dt
                end

                -- Auto-interact when player bumps into the door collider
                if touching_collider and not prop.was_touching and prop.required_key then
                    local has_key = common.player_has_item(player, prop.required_key)
                    -- Always unlock if player has key, but debounce jiggle if they don't
                    if has_key or prop.bump_cooldown <= 0 then
                        prop.states.locked.interact(prop, player, true)  -- true = from_bump
                    end
                end
                prop.was_touching = touching_collider

                if prop.text_display then
                    prop.text_display:update(dt, in_range)
                end

                -- Restart idle animation every second to add visual life
                if prop.animation:is_finished() then
                    prop._timer = prop._timer + dt
                    if prop._timer > 1 then
                        prop._timer = 0
                        prop.animation:reset()
                    end
                end
            end,

            ---@param prop table The door prop instance
            draw = function(prop)
                common.draw(prop)
                if prop.text_display then
                    prop.text_display:draw(prop.x, prop.y)
                end
            end
        },

        jiggle = {
            --- Initialize jiggle feedback animation when player lacks required key
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_LOCKED_JIGGLE)
                audio.play_sfx(audio.locked_door)
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "locked")
                end
            end,

            draw = common.draw
        },

        unlock = {
            --- Begin unlock animation and play unlock sound
            ---@param prop table The door prop instance
            start = function(prop)
                prop.animation = Animation.new(DOOR_UNLOCK)
                audio.play_sfx(audio.unlock_door)
            end,

            ---@param prop table The door prop instance
            ---@param _dt number Delta time (unused)
            ---@param _player table Player reference (unused)
            update = function(prop, _dt, _player)
                if prop.animation:is_finished() then
                    Prop.set_state(prop, "unlocked")
                end
            end,

            draw = common.draw
        },

        unlocked = {
            --- Remove door collision when unlocked
            ---@param prop table The door prop instance
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,

            ---@param _prop table Unused (door is open)
            ---@param _dt number Unused
            ---@param _player table Unused
            update = function(_prop, _dt, _player) end,

            ---@param _prop table Unused (door is invisible when unlocked)
            draw = function(_prop) end
        }
    }
}
