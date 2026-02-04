--- Trigger System: Manages event-based trigger zones defined in Tiled.
--- Triggers fire registered callbacks when the player enters them.
--- Supports one-shot (repeat=false) or repeating (default) triggers.

local world = require("world")
local registry = require("triggers/registry")

local triggers = {}

local trigger_colliders = {}  -- Active trigger collider owners
local fired_triggers = {}     -- Set of trigger owners that have fired (for repeat=false)

--- Creates trigger colliders from level trigger definitions.
--- Call after loading a level to set up trigger zones.
---@param trigger_defs table[] Array of trigger definitions from tiled_loader
function triggers.create_colliders(trigger_defs)
    for _, def in ipairs(trigger_defs) do
        local owner = {
            x = def.x,
            y = def.y,
            box = { x = 0, y = 0, w = def.width, h = def.height },
            is_trigger = true,
            on_trigger = def.on_trigger,
            ["repeat"] = def["repeat"],
        }
        world.add_trigger_collider(owner)
        table.insert(trigger_colliders, owner)
    end
end

--- Checks trigger collisions and fires registered handlers.
--- Call each frame after player movement with collision results.
---@param cols table Collision results from world.move() with triggers array
---@param player table|nil Player instance to pass to handlers
function triggers.check(cols, player)
    local trigger_list = cols.triggers
    if not trigger_list then return end

    for i = 1, #trigger_list do
        local owner = trigger_list[i].owner
        if owner.is_trigger and owner.on_trigger and not fired_triggers[owner] then
            local handler = registry[owner.on_trigger]
            if handler then
                handler(player)
                if not owner["repeat"] then
                    fired_triggers[owner] = true
                end
            end
        end
    end
end

--- Clears all trigger colliders and fired state.
--- Call before loading a new level to prevent stale triggers.
function triggers.clear()
    for _, owner in ipairs(trigger_colliders) do
        world.remove_trigger_collider(owner)
    end
    trigger_colliders = {}
    fired_triggers = {}
end

return triggers
