--- Valkyrie Boss Coordinator: Manages state for the single-entity valkyrie boss encounter.
--- Implements the interface needed by boss_health_bar (is_active, get_health_percent, etc).
local boss_health_bar = require("ui/boss_health_bar")
local music = require("audio/music")
local Prop = require("Prop")

-- Lazy-loaded to avoid circular dependency (platforms → triggers → registry → valkyrie → coordinator)
local platforms = nil

local MAX_HEALTH = 100
local SOLID_DURATION = 3  -- How long blocks stay solid after activation

-- Must match the "id" properties on boss_block props in viking_lair.tmx
local BLOCK_IDS = {
    "valkyrie_boss_block_0",
    "valkyrie_boss_block_1",
    "valkyrie_boss_block_2",
    "valkyrie_boss_block_3",
}

local SPEAR_GROUP_PREFIX = "valkyrie_spear_"   -- groups 0-7
local SPIKE_GROUP_PREFIX = "valkyrie_spikes_"  -- groups 0-3

local ZONE_IDS = {
    top = "valkyrie_boss_top",
    left = "valkyrie_boss_left",
    right = "valkyrie_boss_right",
    left_side = "valkyrie_boss_left_side",
    right_side = "valkyrie_boss_right_side",
    middle = "valkyrie_boss_middle",
    middle_platform = "valkyrie_boss_middle_platform",
}

local PILLAR_PREFIX = "valkyrie_right_pillar_"  -- 0-4
local BRIDGE_IDS = {
    left = "valkyrie_bridge_left",
    right = "valkyrie_bridge_right",
}

local BUTTON_IDS = {
    left = "left_button",
    right = "right_button",
}

-- Lazy-loaded to avoid circular dependency
local audio = nil
local valk_common = nil

-- Health thresholds for phase transitions (percentage of max health)
-- Phase 1: 100%-75%, Phase 2: 75%-50%, Phase 3: 50%-25%, Phase 4: 25%-0%
local PHASE_THRESHOLDS = { 0.75, 0.50, 0.25 }

-- Phase modules (lazy loaded to avoid circular requires)
local phase_modules = nil

--- Lazy load phase modules
---@return table Phase modules indexed by number
local function get_phase_modules()
    if not phase_modules then
        phase_modules = {
            [0] = require("Enemies/Bosses/valkyrie/phase0"),
            [1] = require("Enemies/Bosses/valkyrie/phase1"),
            [2] = require("Enemies/Bosses/valkyrie/phase2"),
            [3] = require("Enemies/Bosses/valkyrie/phase3"),
            [4] = require("Enemies/Bosses/valkyrie/phase4"),
        }
    end
    return phase_modules
end

local coordinator = {
    active = false,
    phase = 0,
    total_max_health = MAX_HEALTH,
    total_health = MAX_HEALTH,
    enemy = nil,
    player = nil,
    boss_id = "valkyrie_boss",
    boss_name = "The Valkyrie",
    boss_subtitle = "Shieldmaiden of the Crypts",
    victory_pending = false,
    victory_timer = 0,
    blocks_active = false,
    blocks_timer = 0,
}

--- Register the valkyrie enemy with the coordinator.
---@param enemy table The valkyrie enemy instance
function coordinator.register(enemy)
    coordinator.enemy = enemy
    enemy.coordinator = coordinator
end

--- Start the boss encounter.
---@param player table Player reference
function coordinator.start(player)
    if coordinator.active then return end

    coordinator.active = true
    coordinator.phase = 0
    coordinator.player = player

    -- TODO: Replace with valkyrie-specific boss music when available
    audio = audio or require("audio")
    audio.play_music(audio.gnomo_boss)

    -- Apply phase 0 states to the valkyrie
    coordinator.apply_phase_states()
end

--- Transition from phase 0 (intro) to phase 1 (combat begins).
function coordinator.start_phase1()
    if coordinator.phase ~= 0 then return end
    coordinator.set_phase(1)
end

--- Get the current phase module.
---@return table|nil Phase module with states table
function coordinator.get_phase_module()
    local modules = get_phase_modules()
    return modules[coordinator.phase]
end

--- Apply current phase's states to the valkyrie enemy.
function coordinator.apply_phase_states()
    local enemy = coordinator.enemy
    if not enemy or enemy.marked_for_destruction then return end

    local phase_module = coordinator.get_phase_module()
    if not phase_module then return end

    enemy.states = phase_module.states
    enemy:set_state(phase_module.states.idle)
end

--- Set the phase and apply new states.
---@param new_phase number Phase number (0-4)
function coordinator.set_phase(new_phase)
    coordinator.phase = new_phase
    coordinator.apply_phase_states()
end

--- Get the current phase number.
---@return number Current phase (0-4)
function coordinator.get_phase()
    return coordinator.phase
end

--- Activate arena blocks (solid walls with fade-in).
function coordinator.activate_blocks()
    for i = 1, #BLOCK_IDS do
        local block = Prop.find_by_id(BLOCK_IDS[i])
        if block and not block.marked_for_destruction and block.definition.activate then
            block.definition.activate(block)
        end
    end
    coordinator.blocks_active = true
    coordinator.blocks_timer = 0
end

--- Deactivate arena blocks (passable with fade-out).
local function deactivate_blocks()
    for i = 1, #BLOCK_IDS do
        local block = Prop.find_by_id(BLOCK_IDS[i])
        if block and not block.marked_for_destruction and block.definition.deactivate then
            block.definition.deactivate(block)
        end
    end
    coordinator.blocks_active = false
    coordinator.blocks_timer = 0
end

--- Report damage dealt to the valkyrie.
---@param damage number Amount of damage dealt
function coordinator.report_damage(damage)
    local old_health = coordinator.total_health
    coordinator.total_health = math.max(0, coordinator.total_health - damage)

    -- Re/activate arena walls each hit (resets the 3s solid timer)
    if coordinator.active then
        coordinator.activate_blocks()
    end

    -- Check for phase transitions based on health thresholds
    local old_percent = old_health / coordinator.total_max_health
    local new_percent = coordinator.total_health / coordinator.total_max_health

    for i = 1, #PHASE_THRESHOLDS do
        local threshold = PHASE_THRESHOLDS[i]
        local target_phase = i + 1  -- threshold[1]=0.75 -> phase 2, etc.
        if old_percent > threshold and new_percent <= threshold then
            coordinator.set_phase(target_phase)
            break  -- Only one transition per damage tick
        end
    end

    if coordinator.total_health <= 0 and coordinator.active then
        coordinator.trigger_victory()
    end
end

--- Get combined health as a percentage (0-1).
---@return number Health percentage
function coordinator.get_health_percent()
    if coordinator.total_max_health <= 0 then return 0 end
    return coordinator.total_health / coordinator.total_max_health
end

--- Get the boss name for display.
---@return string Boss name
function coordinator.get_boss_name()
    return coordinator.boss_name
end

--- Get the boss subtitle for display.
---@return string Boss subtitle
function coordinator.get_boss_subtitle()
    return coordinator.boss_subtitle
end

--- Check if the encounter is active.
---@return boolean True if boss fight is in progress
function coordinator.is_active()
    return coordinator.active
end

--- Trigger victory - kill the valkyrie and start defeated sequence.
function coordinator.trigger_victory()
    coordinator.active = false

    -- Deactivate blocks so player isn't trapped
    deactivate_blocks()

    -- Deactivate all arena hazards
    coordinator.disable_spears(0, 7)
    coordinator.deactivate_spikes(0, 3)

    -- Kill the enemy
    if coordinator.enemy and not coordinator.enemy.marked_for_destruction then
        coordinator.enemy:die()
    end

    -- Fade out boss music
    music.fade_out(1)

    -- Show defeated animation
    boss_health_bar.show_defeated()

    -- Start victory timer to wait for defeated animation
    coordinator.victory_pending = true
    coordinator.victory_timer = 0
end

--- Update victory sequence, block timers, and ghost trails.
---@param dt number Delta time in seconds
function coordinator.update(dt)
    valk_common = valk_common or require("Enemies/Bosses/valkyrie/common")
    valk_common.update_ghost_trails(dt)

    -- Tick block solid timer
    if coordinator.blocks_active then
        coordinator.blocks_timer = coordinator.blocks_timer + dt
        if coordinator.blocks_timer >= SOLID_DURATION then
            deactivate_blocks()
        end
    end

    if not coordinator.victory_pending then return end

    coordinator.victory_timer = coordinator.victory_timer + dt

    if boss_health_bar.is_defeated_complete() then
        -- Mark boss as defeated
        local player = coordinator.player
        if player and player.defeated_bosses then
            player.defeated_bosses[coordinator.boss_id] = true
        end

        -- Open the boss door
        local door = Prop.find_by_id("valkrie_boss_door")
        if door and not door.marked_for_destruction then
            Prop.set_state(door, "opening")
        end

        coordinator.victory_pending = false
    end
end

--- Check if the victory sequence is complete.
---@return boolean True if defeated animation finished
function coordinator.is_sequence_complete()
    if coordinator.victory_pending then return false end
    return (coordinator.player
        and coordinator.player.defeated_bosses
        and coordinator.player.defeated_bosses[coordinator.boss_id]) == true
end

--- Set references needed by sub-modules.
---@param player table Player instance
---@param _camera table Camera instance (unused for valkyrie)
function coordinator.set_refs(player, _camera)
    coordinator.player = player
end

-- ── Spear API ────────────────────────────────────────────────────────────────

--- Fire spears in a range (inclusive). Each index is its own group.
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.fire_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_PREFIX .. i, "fire")
    end
end

--- Enable spears in a range (allows auto-fire and manual fire).
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.enable_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_PREFIX .. i, "enable")
    end
end

--- Disable spears in a range (prevents firing).
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.disable_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_PREFIX .. i, "disable")
    end
end

-- ── Spike API ────────────────────────────────────────────────────────────────

--- Activate spike group into alternating mode.
---@param from number Start index (0-3)
---@param to number End index (0-3)
---@param config table|nil Optional {extend_time, retract_time} override
function coordinator.activate_spikes(from, to, config)
    for i = from, to do
        Prop.group_action(SPIKE_GROUP_PREFIX .. i, "set_alternating", config)
    end
end

--- Deactivate spike group (retract and stop cycling).
---@param from number Start index (0-3)
---@param to number End index (0-3)
function coordinator.deactivate_spikes(from, to)
    for i = from, to do
        Prop.group_action(SPIKE_GROUP_PREFIX .. i, "retract")
    end
end

-- ── Zone API ─────────────────────────────────────────────────────────────────

--- Check if player is inside a named zone.
--- Zones are plain rectangles in Tiled with id properties, stored in platforms.spawn_points.
---@param zone_key string Zone key: "top", "left", or "right"
---@return boolean True if player center is within the zone
function coordinator.is_player_in_zone(zone_key)
    platforms = platforms or require("platforms")
    local player = coordinator.player
    if not player then return false end

    local zone_id = ZONE_IDS[zone_key]
    if not zone_id then return false end

    local zone = platforms.spawn_points[zone_id]
    if not zone or not zone.width then return false end

    local px = player.x + (player.box.x + player.box.w / 2)
    local py = player.y + (player.box.y + player.box.h / 2)
    return px >= zone.x and px < zone.x + zone.width
       and py >= zone.y and py < zone.y + zone.height
end

--- Get a zone rectangle by key. Returns the spawn_point entry with x, y, width, height.
---@param zone_key string Zone key: "top", "left", "right", or a pillar/bridge key
---@return table|nil zone The zone rectangle, or nil if not found
function coordinator.get_zone(zone_key)
    platforms = platforms or require("platforms")
    local zone_id = ZONE_IDS[zone_key]
    if not zone_id then return nil end
    return platforms.spawn_points[zone_id]
end

--- Get a right-pillar zone rectangle by index (0-4).
---@param index number Pillar index (0-4)
---@return table|nil zone The zone rectangle
function coordinator.get_pillar_zone(index)
    platforms = platforms or require("platforms")
    return platforms.spawn_points[PILLAR_PREFIX .. index]
end

--- Get a bridge zone rectangle by side.
---@param side string "left" or "right"
---@return table|nil zone The zone rectangle
function coordinator.get_bridge_zone(side)
    platforms = platforms or require("platforms")
    local id = BRIDGE_IDS[side]
    if not id then return nil end
    return platforms.spawn_points[id]
end

-- ── Button API ───────────────────────────────────────────────────────────────

--- Set the on_press callback for a button.
---@param side string "left" or "right"
---@param callback function|nil Callback to fire when pressed (nil to clear)
function coordinator.set_button_callback(side, callback)
    local id = BUTTON_IDS[side]
    if not id then return end
    local button = Prop.find_by_id(id)
    if button then
        button.on_press = callback
    end
end

--- Reset a button to unpressed state (plays reverse animation).
---@param side string "left" or "right"
function coordinator.reset_button(side)
    local id = BUTTON_IDS[side]
    if not id then return end
    local button = Prop.find_by_id(id)
    if button and button.definition.reset then
        button.definition.reset(button)
    end
end

--- Check if a button is currently pressed.
---@param side string "left" or "right"
---@return boolean
function coordinator.is_button_pressed(side)
    local id = BUTTON_IDS[side]
    if not id then return false end
    local button = Prop.find_by_id(id)
    return button and button.is_pressed or false
end

--- Reset coordinator state for level cleanup.
function coordinator.reset()
    coordinator.active = false
    coordinator.phase = 0
    coordinator.total_max_health = MAX_HEALTH
    coordinator.total_health = MAX_HEALTH
    coordinator.enemy = nil
    coordinator.player = nil
    coordinator.victory_pending = false
    coordinator.victory_timer = 0
    coordinator.blocks_active = false
    coordinator.blocks_timer = 0

    -- Deactivate all arena hazards
    coordinator.disable_spears(0, 7)
    coordinator.deactivate_spikes(0, 3)

    valk_common = valk_common or require("Enemies/Bosses/valkyrie/common")
    valk_common.clear_ghost_trails()

    local cinematic = require("Enemies/Bosses/valkyrie/cinematic")
    cinematic.reset()
end

return coordinator
