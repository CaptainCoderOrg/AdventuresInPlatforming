--- Valkyrie Boss Coordinator: Manages state for the single-entity valkyrie boss encounter.
--- Implements the interface needed by boss_health_bar (is_active, get_health_percent, etc).
local Prop = require("Prop")

-- Lazy-loaded to avoid circular dependency (platforms → triggers → registry → valkyrie → coordinator)
local platforms = nil

local MAX_HEALTH = 75
local SOLID_DURATION = 3  -- How long blocks stay solid after activation

-- Must match the "id" properties on boss_block props in viking_lair.tmx
local BLOCK_IDS = {
    "valkyrie_boss_block_0",
    "valkyrie_boss_block_1",
    "valkyrie_boss_block_2",
    "valkyrie_boss_block_3",
    "valkyrie_boss_block_center",
}

local SPEAR_GROUP_PREFIX = "valkyrie_spear_"   -- groups 0-7
local SPIKE_GROUP_PREFIX = "valkyrie_spikes_"  -- groups 0-3

-- Pre-computed group name strings (avoid per-call concatenation)
local SPEAR_GROUP_NAMES = {}
for i = 0, 7 do SPEAR_GROUP_NAMES[i] = SPEAR_GROUP_PREFIX .. i end
local SPIKE_GROUP_NAMES = {}
for i = 0, 3 do SPIKE_GROUP_NAMES[i] = SPIKE_GROUP_PREFIX .. i end

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
local victory = nil

-- Cached prop references (populated on first use, cleared on reset)
local cached_blocks = nil
local cached_buttons = nil

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
    camera = nil,
    boss_id = "valkyrie_boss",
    boss_name = "The Valkyrie",
    boss_subtitle = "Shieldmaiden of the Crypts",
    blocks_active = false,
    blocks_timer = 0,
}

-- ── Spike Sequencer ────────────────────────────────────────────────────────
-- Rolling wave: 2 groups active at a time, cycling through groups 0-3.

local spike_seq = { active = false, timer = 0, current_step = 0 }
local SPIKE_SEQ_INTERVAL = 1.0
local SPIKE_SEQ_CYCLE_START = 2
local SPIKE_SEQ_CYCLE_END = 5

-- ── Spear Sequencer ────────────────────────────────────────────────────────
-- Fires spear groups in an outside-in pattern: 0,7,1,6,2,5,3,4.

local spear_seq = { active = false, timer = 0, current_step = 0 }
local SPEAR_SEQ_INTERVAL = 0.5
local SPEAR_SEQ_PATTERN = {0, 7, 1, 6, 2, 5, 3, 4}

local SPIKE_SEQ_STEPS = {
    [0] = { extend = {0} },
    [1] = { extend = {1} },
    [2] = { extend = {2}, retract = {0} },
    [3] = { extend = {3}, retract = {1} },
    [4] = { extend = {0}, retract = {2} },
    [5] = { extend = {1}, retract = {3} },
}

--- Execute a single spike sequencer step (extend/retract groups).
---@param step_data table Step with extend and/or retract arrays of group indices
local function execute_spike_step(step_data)
    if not step_data then return end
    if step_data.extend then
        for _, idx in ipairs(step_data.extend) do
            Prop.group_action(SPIKE_GROUP_NAMES[idx], "extending")
        end
    end
    if step_data.retract then
        for _, idx in ipairs(step_data.retract) do
            Prop.group_action(SPIKE_GROUP_NAMES[idx], "retracting")
        end
    end
end

--- Execute a single spear sequencer step (force-fire one group).
--- Uses single_fire to bypass the enabled check so traps don't auto-fire.
---@param step_index number 1-based index into SPEAR_SEQ_PATTERN
local function execute_spear_step(step_index)
    local group = SPEAR_SEQ_PATTERN[step_index]
    if group ~= nil then
        Prop.group_action(SPEAR_GROUP_NAMES[group], "single_fire")
    end
end

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

--- Get cached block prop references (populated on first call).
---@return table Array of block prop references
local function get_blocks()
    if not cached_blocks then
        cached_blocks = {}
        for i = 1, #BLOCK_IDS do
            cached_blocks[i] = Prop.find_by_id(BLOCK_IDS[i])
        end
    end
    return cached_blocks
end

--- Get a cached button prop reference by side.
---@param side string "left" or "right"
---@return table|nil button The button prop
local function get_button(side)
    local id = BUTTON_IDS[side]
    if not id then return nil end
    if not cached_buttons then
        cached_buttons = {}
    end
    if cached_buttons[side] == nil then
        cached_buttons[side] = Prop.find_by_id(id) or false
    end
    return cached_buttons[side] or nil
end

--- Activate arena blocks (solid walls with fade-in).
function coordinator.activate_blocks()
    local blocks = get_blocks()
    for i = 1, #BLOCK_IDS do
        local block = blocks[i]
        if block and not block.marked_for_destruction and block.definition.activate then
            block.definition.activate(block)
        end
    end
    coordinator.blocks_active = true
    coordinator.blocks_timer = 0
end

--- Deactivate arena blocks (passable with fade-out).
local function deactivate_blocks()
    local blocks = get_blocks()
    for i = 1, #BLOCK_IDS do
        local block = blocks[i]
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

--- Trigger victory - kill the valkyrie and start cinematic victory sequence.
function coordinator.trigger_victory()
    coordinator.active = false

    -- Deactivate blocks so player isn't trapped
    deactivate_blocks()

    -- Deactivate all arena hazards
    coordinator.stop_spike_sequencer()
    coordinator.stop_spear_sequencer()
    coordinator.disable_spears(0, 7)
    coordinator.deactivate_spikes(0, 3)

    -- Start victory sequence (captures enemy position before death)
    victory = victory or require("Enemies/Bosses/valkyrie/victory")
    victory.start(coordinator.enemy)

    -- Kill the enemy
    if coordinator.enemy and not coordinator.enemy.marked_for_destruction then
        coordinator.enemy:die()
    end
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

    -- Tick spike sequencer
    if spike_seq.active then
        spike_seq.timer = spike_seq.timer + dt
        while spike_seq.timer >= SPIKE_SEQ_INTERVAL and spike_seq.active do
            spike_seq.timer = spike_seq.timer - SPIKE_SEQ_INTERVAL
            spike_seq.current_step = spike_seq.current_step + 1

            local effective = spike_seq.current_step
            if effective > SPIKE_SEQ_CYCLE_END then
                local cycle_len = SPIKE_SEQ_CYCLE_END - SPIKE_SEQ_CYCLE_START + 1
                effective = SPIKE_SEQ_CYCLE_START + (effective - SPIKE_SEQ_CYCLE_START) % cycle_len
            end

            execute_spike_step(SPIKE_SEQ_STEPS[effective])
        end
    end

    -- Tick spear sequencer
    if spear_seq.active then
        spear_seq.timer = spear_seq.timer + dt
        while spear_seq.timer >= SPEAR_SEQ_INTERVAL and spear_seq.active do
            spear_seq.timer = spear_seq.timer - SPEAR_SEQ_INTERVAL
            spear_seq.current_step = spear_seq.current_step + 1
            if spear_seq.current_step > #SPEAR_SEQ_PATTERN then
                spear_seq.current_step = 1
            end
            execute_spear_step(spear_seq.current_step)
        end
    end

    -- Update victory sequence (shield drop, shard, door)
    victory = victory or require("Enemies/Bosses/valkyrie/victory")
    victory.update(dt)
end

--- Check if the victory sequence is complete.
---@return boolean True if shield collected and door opened
function coordinator.is_sequence_complete()
    victory = victory or require("Enemies/Bosses/valkyrie/victory")
    return victory.is_complete()
end

--- Set references needed by sub-modules.
---@param player table Player instance
---@param camera table Camera instance
function coordinator.set_refs(player, camera)
    coordinator.player = player
    coordinator.camera = camera
end

-- ── Spear API ────────────────────────────────────────────────────────────────

--- Fire spears in a range (inclusive). Each index is its own group.
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.fire_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_NAMES[i], "fire")
    end
end

--- Enable spears in a range (allows auto-fire and manual fire).
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.enable_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_NAMES[i], "enable")
    end
end

--- Disable spears in a range (prevents firing).
---@param from number Start index (0-7)
---@param to number End index (0-7)
function coordinator.disable_spears(from, to)
    for i = from, to do
        Prop.group_action(SPEAR_GROUP_NAMES[i], "disable")
    end
end

-- ── Spike API ────────────────────────────────────────────────────────────────

--- Activate spike group into alternating mode.
---@param from number Start index (0-3)
---@param to number End index (0-3)
---@param config table|nil Optional {extend_time, retract_time} override
function coordinator.activate_spikes(from, to, config)
    for i = from, to do
        Prop.group_action(SPIKE_GROUP_NAMES[i], "set_alternating", config)
    end
end

--- Deactivate spike group (retract and stop cycling).
---@param from number Start index (0-3)
---@param to number End index (0-3)
function coordinator.deactivate_spikes(from, to)
    for i = from, to do
        Prop.group_action(SPIKE_GROUP_NAMES[i], "retract")
    end
end

-- ── Spike Sequencer API ─────────────────────────────────────────────────────

--- Start the rolling spike wave sequencer. Executes step 0 immediately.
function coordinator.start_spike_sequencer()
    spike_seq.active = true
    spike_seq.timer = 0
    spike_seq.current_step = 0
    execute_spike_step(SPIKE_SEQ_STEPS[0])
end

--- Stop the spike sequencer.
function coordinator.stop_spike_sequencer()
    spike_seq.active = false
    spike_seq.timer = 0
    spike_seq.current_step = 0
end

-- ── Spear Sequencer API ───────────────────────────────────────────────────

--- Start the spear sequencer. Fires first group immediately.
function coordinator.start_spear_sequencer()
    spear_seq.active = true
    spear_seq.timer = 0
    spear_seq.current_step = 1
    execute_spear_step(1)
end

--- Stop the spear sequencer.
function coordinator.stop_spear_sequencer()
    spear_seq.active = false
    spear_seq.timer = 0
    spear_seq.current_step = 0
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
    local button = get_button(side)
    if button then
        button.on_press = callback
    end
end

--- Reset a button to unpressed state (plays reverse animation).
---@param side string "left" or "right"
function coordinator.reset_button(side)
    local button = get_button(side)
    if button and button.definition.reset then
        button.definition.reset(button)
    end
end

--- Check if a button is currently pressed.
---@param side string "left" or "right"
---@return boolean
function coordinator.is_button_pressed(side)
    local button = get_button(side)
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
    coordinator.camera = nil
    coordinator.blocks_active = false
    coordinator.blocks_timer = 0
    cached_blocks = nil
    cached_buttons = nil

    -- Deactivate all arena hazards
    coordinator.stop_spike_sequencer()
    coordinator.stop_spear_sequencer()
    coordinator.disable_spears(0, 7)
    coordinator.deactivate_spikes(0, 3)

    valk_common = valk_common or require("Enemies/Bosses/valkyrie/common")
    valk_common.clear_ghost_trails()

    local cinematic = require("Enemies/Bosses/valkyrie/cinematic")
    cinematic.reset()

    victory = victory or require("Enemies/Bosses/valkyrie/victory")
    victory.reset()
end

return coordinator
