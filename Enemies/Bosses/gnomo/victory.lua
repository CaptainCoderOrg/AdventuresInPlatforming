--- Gnomo Boss Victory Sequence: Coordinates the defeat cinematic.
--- Phases: axe flies up, pauses, descends to drop location, spawns collectible,
--- shows defeated text, waits for axe collection, then opens the boss door.
local boss_health_bar = require("ui/boss_health_bar")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local Effects = require("Effects")
local music = require("audio/music")
local platforms = require("platforms")
local Prop = require("Prop")

local victory = {}

-- Phase constants
local PHASE_IDLE = 0
local PHASE_AXE_TO_WAYPOINT = 1
local PHASE_SHOW_DEFEATED = 2
local PHASE_AXE_FALLING = 3
local PHASE_WAIT_COLLECT = 4
local PHASE_COMPLETE = 5

-- State
local phase = PHASE_IDLE
local timer = 0
local drop_x = 0
local drop_y = 0
local waypoint_x = 0
local waypoint_y = 0
local axe_prop = nil            -- Reference to spawned axe for collection detection

--- Start the victory sequence.
--- Called when the boss is defeated with position of last gnomo.
---@param last_gnomo table|nil The gnomo that died last (for axe spawn position)
function victory.start(last_gnomo)
    -- Get final drop position
    local drop_point = platforms.spawn_points["gnomo_boss_axe_drop"]
    if drop_point then
        drop_x = drop_point.x
        drop_y = drop_point.y
    else
        drop_x = last_gnomo and (last_gnomo.x + 0.5) or 0
        drop_y = last_gnomo and last_gnomo.y or 0
        print("[victory] Warning: gnomo_boss_axe_drop spawn point not found")
    end

    -- Get waypoint position (where axe waits during defeated text)
    local waypoint = platforms.spawn_points["gnomo_boss_axe_target"]
    if waypoint then
        waypoint_x = waypoint.x
        waypoint_y = waypoint.y
    else
        -- Fallback: fly to center above drop point
        waypoint_x = drop_x
        waypoint_y = drop_y - 5
        print("[victory] Warning: gnomo_boss_axe_target spawn point not found")
    end

    -- Get start position from last gnomo or use drop location as fallback
    local start_x, start_y
    if last_gnomo then
        start_x = last_gnomo.x + 0.5
        start_y = last_gnomo.y
    else
        start_x = drop_x
        start_y = drop_y
    end

    -- Fade out boss music
    music.fade_out(1)

    -- Create flying axe effect: start -> waypoint (defeated text shows while axe waits there)
    Effects.create_flying_axe(start_x, start_y, waypoint_x, waypoint_y, victory.on_axe_reached_waypoint)

    phase = PHASE_AXE_TO_WAYPOINT
    timer = 0
end

--- Called when the flying axe reaches the waypoint.
--- Triggers the defeated animation while axe waits at waypoint.
function victory.on_axe_reached_waypoint()
    boss_health_bar.show_defeated()
    phase = PHASE_SHOW_DEFEATED
    timer = 0
end

--- Called when the flying axe lands at the final drop location.
--- Spawns the throwing_axe collectible item.
function victory.on_axe_landed()
    -- Spawn the throwing_axe unique item at drop location
    axe_prop = Prop.spawn("unique_item", drop_x, drop_y, { item_id = "throwing_axe" })

    phase = PHASE_WAIT_COLLECT
    timer = 0
end

--- Update the victory sequence.
---@param dt number Delta time in seconds
function victory.update(dt)
    if phase == PHASE_IDLE or phase == PHASE_COMPLETE or phase == PHASE_AXE_TO_WAYPOINT or phase == PHASE_AXE_FALLING then
        return
    end

    timer = timer + dt

    if phase == PHASE_SHOW_DEFEATED and boss_health_bar.is_defeated_complete() then
        -- Defeated animation finished, now drop the axe to final position
        Effects.create_flying_axe(waypoint_x, waypoint_y, drop_x, drop_y, victory.on_axe_landed)
        phase = PHASE_AXE_FALLING
        return
    end

    if phase == PHASE_WAIT_COLLECT and axe_prop and axe_prop.marked_for_destruction then
        -- Mark boss as defeated (saved at next campfire rest)
        local player = coordinator.player
        if player and player.defeated_bosses then
            player.defeated_bosses[coordinator.boss_id] = true
        end

        -- Journal: record gnomo kill (written directly to avoid toast during cinematic)
        if player and player.journal then
            player.journal["killed_gnomos"] = player.journal["killed_gnomos"] or "active"
        end

        local door = Prop.find_by_id("gnomo_boss_door")
        if door and not door.marked_for_destruction then
            Prop.set_state(door, "opening")
        end
        phase = PHASE_COMPLETE
    end
end

--- Check if the victory sequence is active.
---@return boolean True if sequence is in progress
function victory.is_active()
    return phase ~= PHASE_IDLE and phase ~= PHASE_COMPLETE
end

--- Check if the victory sequence is complete.
---@return boolean True if sequence finished
function victory.is_complete()
    return phase == PHASE_COMPLETE
end

--- Reset victory sequence state (call on level cleanup).
--- Clears all phase timers, positions, and cached references.
function victory.reset()
    phase = PHASE_IDLE
    timer = 0
    drop_x = 0
    drop_y = 0
    waypoint_x = 0
    waypoint_y = 0
    axe_prop = nil
end

return victory
