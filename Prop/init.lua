--- Prop system - Unified management for interactive objects
--- Mirrors the Enemy system pattern: register definitions, spawn instances, manage object pool
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local state = require("Prop/state")
local combat = require("combat")
local proximity_audio = require("proximity_audio")

local Prop = {}

-- Reference state module tables directly so hot reload preserves runtime data
Prop.types = state.types
Prop.all = state.all
Prop.groups = state.groups

-- Track current frame for mid-frame animation synchronization
local current_frame = 0
local current_dt = 0

--- Register a prop type definition
---@param key string Unique identifier for this prop type
---@param definition table Prop definition table
function Prop.register(key, definition)
    Prop.types[key] = definition
end

--- Spawn a new prop instance from a registered type
---@param type_key string The registered prop type key
---@param x number X position in tiles
---@param y number Y position in tiles
---@param options table|nil Optional spawn parameters (callbacks, groups, etc.)
---@return table|nil prop The created prop instance or nil if type not found
function Prop.spawn(type_key, x, y, options)
    local definition = Prop.types[type_key]
    if not definition then
        print("[Prop] Warning: Unknown prop type '" .. tostring(type_key) .. "'")
        return nil
    end

    options = options or {}

    local prop = {
        id = state.next_id,
        type_key = type_key,
        x = x,
        y = y,
        box = definition.box and {
            x = definition.box.x,
            y = definition.box.y,
            w = definition.box.w,
            h = definition.box.h
        } or { x = 0, y = 0, w = 1, h = 1 },
        debug_color = definition.debug_color or "#FFFFFF",
        marked_for_destruction = false,
        definition = definition,
        flipped = options.flip and -1 or 1,
    }

    -- Reset behavior: instance option > definition default > true
    if options.reset ~= nil then
        prop.should_reset = options.reset
    elseif definition.default_reset ~= nil then
        prop.should_reset = definition.default_reset
    else
        prop.should_reset = true
    end

    state.next_id = state.next_id + 1

    if definition.on_spawn then
        definition.on_spawn(prop, definition, options)
    end

    -- Apply flip to animation created during on_spawn
    if prop.animation then
        prop.animation.flipped = prop.flipped
    end

    if definition.states and definition.initial_state then
        prop.states = definition.states
        prop.state = nil
        Prop.set_state(prop, definition.initial_state)
    end

    if options.group then
        prop.group = options.group
        if not Prop.groups[options.group] then
            Prop.groups[options.group] = {}
        end
        table.insert(Prop.groups[options.group], prop)
    end

    Prop.all[prop] = true

    -- Add to combat hitbox system
    combat.add(prop)

    return prop
end

--- Set prop state (state machine transition)
---@param prop table The prop instance
---@param state_name string Name of the state to transition to
---@param skip_callback boolean|nil If true, callbacks won't fire (used by group_action to prevent recursion)
function Prop.set_state(prop, state_name, skip_callback)
    if not prop.states then return end

    local new_state = prop.states[state_name]
    if not new_state then
        print("[Prop] Warning: Unknown state '" .. tostring(state_name) .. "' for prop " .. prop.type_key)
        return
    end

    prop.state = new_state
    prop.state_name = state_name
    if new_state.start then
        new_state.start(prop, prop.definition, skip_callback)
    end

    -- Apply flip to animation created during state.start
    if prop.animation and prop.flipped then
        prop.animation.flipped = prop.flipped
    end

    -- If this prop was already updated this frame, advance its new animation now.
    -- This keeps props synchronized when group_action triggers state changes mid-frame.
    if prop._last_update_frame == current_frame and prop.animation then
        prop.animation:play(current_dt)
    end
end

-- Module-level table to avoid allocation each frame
local props_to_remove = {}

--- Update all props
---@param dt number Delta time in seconds
---@param player table|nil Player reference for interaction checks
function Prop.update(dt, player)
    -- Track frame number and dt for mid-frame state change synchronization
    current_frame = current_frame + 1
    current_dt = dt

    -- Clear module-level table instead of allocating a new one
    for i = 1, #props_to_remove do props_to_remove[i] = nil end

    local prop = next(Prop.all)
    while prop do
        if prop.marked_for_destruction then
            if prop.group and Prop.groups[prop.group] then
                for i, p in ipairs(Prop.groups[prop.group]) do
                    if p == prop then
                        table.remove(Prop.groups[prop.group], i)
                        break
                    end
                end
            end
            combat.remove(prop)
            props_to_remove[#props_to_remove + 1] = prop
        else
            local definition = prop.definition

            if prop.state and prop.state.update then
                prop.state.update(prop, dt, player)
            elseif definition.update then
                definition.update(prop, dt, player)
            end

            -- Advance animation unless state update already did it manually
            if prop.animation and not prop._skip_animation_this_frame then
                prop.animation:play(dt)
            end
            prop._skip_animation_this_frame = nil

            -- Track update frame so set_state can sync animations for mid-frame transitions
            prop._last_update_frame = current_frame
        end
        prop = next(Prop.all, prop)
    end

    -- Remove props after iteration completes
    for i = 1, #props_to_remove do
        Prop.all[props_to_remove[i]] = nil
    end
end

--- Update only prop animations (lightweight update for paused states)
---@param dt number Delta time in seconds
function Prop.update_animations(dt)
    local prop = next(Prop.all)
    while prop do
        if not prop.marked_for_destruction and prop.animation then
            prop.animation:play(dt)
        end
        prop = next(Prop.all, prop)
    end
end

--- Draw all props
function Prop.draw()
    local prop = next(Prop.all)
    while prop do
        if not prop.marked_for_destruction then
            local definition = prop.definition

            if prop.state and prop.state.draw then
                prop.state.draw(prop)
            elseif definition.draw then
                definition.draw(prop)
            elseif prop.animation then
                local px = prop.x * sprites.tile_size
                local py = prop.y * sprites.tile_size
                prop.animation:draw(px, py)
            end

            -- Debug bounding box
            if config.bounding_boxes and prop.box then
                local bx = (prop.x + prop.box.x) * sprites.tile_size
                local by = (prop.y + prop.box.y) * sprites.tile_size
                local bw = prop.box.w * sprites.tile_size
                local bh = prop.box.h * sprites.tile_size
                canvas.draw_rect(bx, by, bw, bh, prop.debug_color)
            end
        end
        prop = next(Prop.all, prop)
    end
end

--- Clear all props (preserves table references for hot reload)
function Prop.clear()
    local world = require("world")
    -- Remove colliders and clear props in a single pass
    local prop = next(Prop.all)
    while prop do
        if prop.collider_shape then
            world.remove_collider(prop)
        end
        combat.remove(prop)
        Prop.all[prop] = nil
        prop = next(Prop.all)
    end
    local k = next(Prop.groups)
    while k do
        Prop.groups[k] = nil
        k = next(Prop.groups)
    end
    -- Clear proximity audio emitters
    proximity_audio.clear()
    state.next_id = 1
end

--- Reset all props to their initial states with animation
--- Props with should_reset = false are skipped (persistent props)
function Prop.reset_all()
    local prop = next(Prop.all)
    while prop do
        if not prop.marked_for_destruction and prop.should_reset then
            local def = prop.definition
            if def.reset then
                def.reset(prop)
            end
        end
        prop = next(Prop.all, prop)
    end
end

--- Generate a unique key for a prop based on type and position
---@param prop table The prop instance
---@return string key Unique identifier for this prop
local function get_prop_key(prop)
    return prop.type_key .. "_" .. prop.x .. "_" .. prop.y
end

--- Get save states for all persistent props (reset = false)
--- Returns a table keyed by prop identifier with state data
---@return table states Map of prop_key -> state_data
function Prop.get_persistent_states()
    local states = {}
    local prop = next(Prop.all)
    while prop do
        if not prop.marked_for_destruction and not prop.should_reset then
            local key = get_prop_key(prop)
            local def = prop.definition

            -- Use custom get_save_state if defined, otherwise save state_name
            if def.get_save_state then
                states[key] = def.get_save_state(prop)
            elseif prop.state_name then
                states[key] = { state_name = prop.state_name }
            end
        end
        prop = next(Prop.all, prop)
    end
    return states
end

--- Restore persistent prop states from saved data
--- Called after props are spawned during level load
---@param states table Map of prop_key -> state_data from save file
function Prop.restore_persistent_states(states)
    if not states then return end

    local prop = next(Prop.all)
    while prop do
        if not prop.marked_for_destruction and not prop.should_reset then
            local key = get_prop_key(prop)
            local saved_state = states[key]

            if saved_state then
                local def = prop.definition

                -- Use custom restore_save_state if defined
                if def.restore_save_state then
                    def.restore_save_state(prop, saved_state)
                elseif saved_state.state_name and prop.states then
                    -- Default: restore state by name
                    Prop.set_state(prop, saved_state.state_name)
                end
            end
        end
        prop = next(Prop.all, prop)
    end
end

--- Check if a hitbox overlaps with any prop of a given type
--- Uses spatial indexing via combat system for O(1) average lookup
---@param type_key string The prop type to check against
---@param hitbox table Hitbox with x, y, w, h in tile coordinates
---@param filter function|nil Optional filter function(prop) returning true to include
---@return table|nil prop The first matching prop or nil
function Prop.check_hit(type_key, hitbox, filter)
    local hits = combat.query_rect(hitbox.x, hitbox.y, hitbox.w, hitbox.h, function(entity)
        -- Only match props of the specified type
        if entity.type_key ~= type_key then return false end
        if entity.marked_for_destruction then return false end
        -- Apply custom filter if provided
        if filter and not filter(entity) then return false end
        return true
    end)

    -- Return first match (or nil if empty)
    return hits[1]
end

--- Trigger an action on all props in a group
---@param group_name string The group name
---@param action string The action to trigger (state name or method name)
---@param ... any Additional arguments passed to the action
function Prop.group_action(group_name, action, ...)
    local group = Prop.groups[group_name]
    if not group then return end

    for _, prop in ipairs(group) do
        -- Try state transition first
        if prop.states and prop.states[action] then
            Prop.set_state(prop, action, true)  -- skip callbacks to prevent recursion
        -- Try definition method
        elseif prop.definition[action] then
            prop.definition[action](prop, ...)
        end
    end
end

--- Get all props of a specific type
---@param type_key string The prop type
---@return table props Array of props
function Prop.get_all_of_type(type_key)
    local result = {}
    local prop = next(Prop.all)
    while prop do
        if prop.type_key == type_key and not prop.marked_for_destruction then
            result[#result + 1] = prop
        end
        prop = next(Prop.all, prop)
    end
    return result
end

--- Get pressure plate lift amount for an entity.
--- Returns cached value set by pressure plates during their update phase.
--- This avoids spatial queries during draw - pressure plates set this value
--- on entities they detect as occupying them.
---@param entity table Entity with pressure_plate_lift property (set by pressure plates)
---@return number Lift amount in pixels (0 if not on a plate)
function Prop.get_pressure_plate_lift(entity)
    return entity.pressure_plate_lift or 0
end

return Prop
