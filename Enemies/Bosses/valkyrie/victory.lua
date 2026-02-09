--- Valkyrie Boss Victory Sequence: Coordinates the defeat cinematic.
--- Phases: shield flies up to waypoint above pillar 2, pauses during DEFEATED text,
--- descends to pillar 2 as collectible. Arcane shard falls to arena floor.
--- Door opens only after player collects the shield.
local boss_health_bar = require("ui/boss_health_bar")
local coordinator = require("Enemies/Bosses/valkyrie/coordinator")
local Effects = require("Effects")
local music = require("audio/music")
local Prop = require("Prop")
local sprites_items = require("sprites/items")

local victory = {}

-- Phase constants
local PHASE_IDLE = 0
local PHASE_SHIELD_TO_WAYPOINT = 1
local PHASE_SHOW_DEFEATED = 2
local PHASE_SHIELD_FALLING = 3
local PHASE_WAIT_COLLECT = 4
local PHASE_COMPLETE = 5

-- State
local phase = PHASE_IDLE
local death_x = 0
local death_y = 0
local drop_x = 0
local drop_y = 0
local waypoint_x = 0
local waypoint_y = 0
local ground_y = 0
local shield_prop = nil  -- Reference to spawned shield for collection detection

--- Called when the flying shield reaches the waypoint above pillar 2.
--- Triggers the defeated animation while shield hovers at waypoint.
local function on_shield_reached_waypoint()
    boss_health_bar.show_defeated()
    phase = PHASE_SHOW_DEFEATED
end

--- Called when the arcane shard lands on the arena floor.
--- Spawns a collectible stackable_item.
local function on_shard_landed()
    Prop.spawn("stackable_item", death_x, ground_y, { item_id = "arcane_shard" })
end

--- Called when the flying shield lands at pillar 2.
--- Spawns the shield collectible unique_item.
local function on_shield_landed()
    shield_prop = Prop.spawn("unique_item", drop_x, drop_y, { item_id = "shield" })
    phase = PHASE_WAIT_COLLECT
end

--- Start the victory sequence.
--- Called when the boss is defeated, before enemy:die().
---@param enemy table The valkyrie enemy instance (position captured before death)
function victory.start(enemy)
    -- Capture death position
    death_x = enemy.x + 0.5
    death_y = enemy.y

    -- Get pillar 2 zone for shield drop target
    local pillar2 = coordinator.get_pillar_zone(2)
    if pillar2 then
        drop_x = pillar2.x
        drop_y = pillar2.y + pillar2.height - 1
        -- Waypoint: 4 tiles above the drop target
        waypoint_x = drop_x
        waypoint_y = pillar2.y - 4
    else
        drop_x = death_x
        drop_y = death_y
        waypoint_x = death_x
        waypoint_y = death_y - 4
        print("[victory] Warning: valkyrie_right_pillar_2 spawn point not found")
    end

    -- Get ground floor from middle zone
    local middle = coordinator.get_zone("middle")
    if middle then
        ground_y = middle.y + middle.height - 1
    else
        ground_y = death_y + 3
        print("[victory] Warning: valkyrie_boss_middle zone not found")
    end

    -- Fade out boss music
    music.fade_out(1)

    -- Create flying shield: death position -> waypoint above pillar 2
    Effects.create_flying_object(death_x, death_y, waypoint_x, waypoint_y, {
        sprite = sprites_items.shield,
        on_complete = on_shield_reached_waypoint,
    })

    -- Create falling shard: death position -> arena floor
    Effects.create_flying_object(death_x, death_y, death_x, ground_y, {
        sprite = sprites_items.arcane_shard,
        rotations = 0,
        flight_duration = 0.75,
        on_complete = on_shard_landed,
    })

    phase = PHASE_SHIELD_TO_WAYPOINT
end

--- Update the victory sequence.
---@param _dt number Delta time in seconds (unused; timing delegated to Effects/boss_health_bar)
function victory.update(_dt)
    if phase == PHASE_IDLE or phase == PHASE_COMPLETE
        or phase == PHASE_SHIELD_TO_WAYPOINT or phase == PHASE_SHIELD_FALLING then
        return
    end

    if phase == PHASE_SHOW_DEFEATED and boss_health_bar.is_defeated_complete() then
        -- Defeated animation finished, drop shield to pillar 2
        Effects.create_flying_object(waypoint_x, waypoint_y, drop_x, drop_y, {
            sprite = sprites_items.shield,
            on_complete = on_shield_landed,
        })
        phase = PHASE_SHIELD_FALLING
        return
    end

    if phase == PHASE_WAIT_COLLECT and shield_prop and shield_prop.marked_for_destruction then
        -- Player collected the shield
        local player = coordinator.player
        if player and player.defeated_bosses then
            player.defeated_bosses[coordinator.boss_id] = true
        end

        -- Journal: record valkyrie kill (written directly to avoid toast during cinematic)
        if player and player.journal then
            player.journal["killed_valkyrie"] = player.journal["killed_valkyrie"] or "active"
        end

        -- Open the boss door
        local door = Prop.find_by_id("valkrie_boss_door")
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
--- Clears all phase state, positions, and cached references.
function victory.reset()
    phase = PHASE_IDLE
    death_x = 0
    death_y = 0
    drop_x = 0
    drop_y = 0
    waypoint_x = 0
    waypoint_y = 0
    ground_y = 0
    shield_prop = nil
end

return victory
