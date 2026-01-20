--- Prop system - Unified management for interactive objects
--- Mirrors the Enemy system pattern: register definitions, spawn instances, manage object pool
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local state = require("Prop/state")
local combat = require("combat")

local Prop = {}

-- Reference state module tables directly so hot reload preserves runtime data
Prop.types = state.types
Prop.all = state.all
Prop.groups = state.groups

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
        definition = definition
    }

    state.next_id = state.next_id + 1

    if definition.on_spawn then
        definition.on_spawn(prop, definition, options)
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
end

--- Update all props
---@param dt number Delta time in seconds
---@param player table|nil Player reference for interaction checks
function Prop.update(dt, player)
    for prop in pairs(Prop.all) do
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
            Prop.all[prop] = nil
        else
            local definition = prop.definition

            if prop.state and prop.state.update then
                prop.state.update(prop, dt, player)
            elseif definition.update then
                definition.update(prop, dt, player)
            end

            if prop.animation then
                prop.animation:play(dt)
            end
        end
    end
end

--- Update only prop animations (lightweight update for paused states)
---@param dt number Delta time in seconds
function Prop.update_animations(dt)
    for prop in pairs(Prop.all) do
        if not prop.marked_for_destruction and prop.animation then
            prop.animation:play(dt)
        end
    end
end

--- Draw all props
function Prop.draw()
    for prop in pairs(Prop.all) do
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
    end
end

--- Clear all props (preserves table references for hot reload)
function Prop.clear()
    local world = require("world")
    -- Remove colliders and clear props in a single pass
    for prop in pairs(Prop.all) do
        if prop.collider_shape then
            world.remove_collider(prop)
        end
        combat.remove(prop)
        Prop.all[prop] = nil
    end
    for k in pairs(Prop.groups) do
        Prop.groups[k] = nil
    end
    state.next_id = 1
end

--- Reset all props to their initial states with animation
function Prop.reset_all()
    for prop in pairs(Prop.all) do
        if not prop.marked_for_destruction then
            local def = prop.definition
            if def.reset then
                def.reset(prop)
            end
        end
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
    for prop in pairs(Prop.all) do
        if prop.type_key == type_key and not prop.marked_for_destruction then
            table.insert(result, prop)
        end
    end
    return result
end

return Prop
