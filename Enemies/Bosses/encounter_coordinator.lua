--- Encounter Coordinator: Central manager for all boss encounter coordinators.
--- Provides a single interface for main.lua to interact with boss encounters.
--- Each boss has its own coordinator that registers with this module.

local encounter_coordinator = {}

-- Registered boss coordinators (boss_id -> coordinator)
local coordinators = {}

--- Register a boss coordinator.
---@param boss_id string Unique identifier for the boss
---@param coordinator table The boss's coordinator module
function encounter_coordinator.register(boss_id, coordinator)
    coordinators[boss_id] = coordinator
end

--- Update all registered coordinators.
---@param dt number Delta time in seconds
function encounter_coordinator.update(dt)
    for _, coordinator in pairs(coordinators) do
        if coordinator.update then
            coordinator.update(dt)
        end
    end
end

--- Check if any boss sequence is complete (for music triggers, etc).
---@return boolean True if any boss encounter has concluded
function encounter_coordinator.is_any_sequence_complete()
    for _, coordinator in pairs(coordinators) do
        if coordinator.is_sequence_complete and coordinator.is_sequence_complete() then
            return true
        end
    end
    return false
end

--- Set references needed by all coordinators.
---@param player table Player instance
---@param camera table Camera instance
function encounter_coordinator.set_refs(player, camera)
    for _, coordinator in pairs(coordinators) do
        if coordinator.set_refs then
            coordinator.set_refs(player, camera)
        end
    end
end

--- Reset all registered coordinators.
function encounter_coordinator.reset()
    for _, coordinator in pairs(coordinators) do
        if coordinator.reset then
            coordinator.reset()
        end
    end
end

--- Get a specific coordinator by boss_id.
---@param boss_id string Boss identifier
---@return table|nil coordinator The coordinator or nil if not found
function encounter_coordinator.get(boss_id)
    return coordinators[boss_id]
end

return encounter_coordinator
