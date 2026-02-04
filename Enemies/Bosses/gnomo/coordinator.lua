--- Gnomo Boss Coordinator: Manages shared state for the 4-gnomo boss encounter.
--- Uses a shared health pool with phase transitions at health thresholds.
--- IMPORTANT: Call coordinator.reset() on level cleanup to clear state.
local coordinator = {
    active = false,
    phase = 0,              -- 0=dormant, 1-4=active phases
    enemies = {},           -- References to all 4 gnomos (keyed by color)
    alive_count = 0,
    total_max_health = 20,  -- Fixed shared health pool
    total_health = 20,      -- Current shared health
    last_hit_gnomo = nil,   -- Most recently hit gnomo (dies at phase transition)
    on_victory = nil,       -- Callback when all dead
    boss_name = "Gnomo Brothers",
    boss_subtitle = "Schemers with Axes",
}

-- Health thresholds for phase transitions (percentage of max health)
-- Phase 1: 100%-75%, Phase 2: 75%-50%, Phase 3: 50%-25%, Phase 4: 25%-0%
local PHASE_THRESHOLDS = { 0.75, 0.50, 0.25, 0 }

-- Phase modules (lazy loaded to avoid circular requires)
local phase_modules = nil

--- Lazy load phase modules
---@return table Phase modules indexed by number
local function get_phase_modules()
    if not phase_modules then
        phase_modules = {
            [1] = require("Enemies/Bosses/gnomo/phase1"),
            [2] = require("Enemies/Bosses/gnomo/phase2"),
            [3] = require("Enemies/Bosses/gnomo/phase3"),
            [4] = require("Enemies/Bosses/gnomo/phase4"),
        }
    end
    return phase_modules
end

--- Register a gnomo with the coordinator.
--- Called by each gnomo boss on spawn.
---@param enemy table The gnomo enemy instance
---@param color string The gnomo's color identifier (green/blue/magenta/red)
function coordinator.register(enemy, color)
    coordinator.enemies[color] = enemy
    coordinator.alive_count = coordinator.alive_count + 1

    -- Link enemy back to coordinator for damage routing
    enemy.coordinator = coordinator
end

--- Start the boss encounter.
--- Transitions from dormant (phase 0) to phase 1.
function coordinator.start()
    if coordinator.active then return end

    coordinator.active = true
    coordinator.phase = 1

    -- Notify all gnomos to use phase 1 states
    local phase_module = coordinator.get_phase_module()
    if phase_module then
        for _, enemy in pairs(coordinator.enemies) do
            if not enemy.marked_for_destruction then
                enemy.states = phase_module.states
                enemy:set_state(phase_module.states.idle)
            end
        end
    end
end

--- Report damage dealt to shared health pool.
--- Checks for phase transitions at health thresholds.
---@param damage number Amount of damage dealt
---@param source_gnomo table|nil The gnomo that was hit (for death targeting)
function coordinator.report_damage(damage, source_gnomo)
    local old_health = coordinator.total_health
    coordinator.total_health = math.max(0, coordinator.total_health - damage)

    -- Track the most recently hit gnomo
    if source_gnomo then
        coordinator.last_hit_gnomo = source_gnomo
    end

    -- Check for phase transitions based on health thresholds
    local old_percent = old_health / coordinator.total_max_health
    local new_percent = coordinator.total_health / coordinator.total_max_health

    for i, threshold in ipairs(PHASE_THRESHOLDS) do
        -- Crossed this threshold?
        if old_percent > threshold and new_percent <= threshold then
            coordinator.trigger_phase_transition(i + 1)
            break  -- Only one transition per damage tick
        end
    end

    -- Victory when health reaches 0
    if coordinator.total_health <= 0 and coordinator.active then
        coordinator.trigger_victory()
    end
end

--- Trigger a phase transition, killing the most recently hit gnomo.
---@param new_phase number The phase to transition to (2, 3, or 4)
function coordinator.trigger_phase_transition(new_phase)
    if new_phase <= coordinator.phase then return end

    -- Kill the most recently hit gnomo (fallback to any alive gnomo)
    local gnomo_to_kill = coordinator.last_hit_gnomo
    if not gnomo_to_kill or gnomo_to_kill.marked_for_destruction then
        -- Fallback: find any alive gnomo
        for _, gnomo in pairs(coordinator.enemies) do
            if not gnomo.marked_for_destruction then
                gnomo_to_kill = gnomo
                break
            end
        end
    end

    if gnomo_to_kill and not gnomo_to_kill.marked_for_destruction then
        gnomo_to_kill:die()
    end

    -- Clear last hit since that gnomo is now dead
    coordinator.last_hit_gnomo = nil

    coordinator.alive_count = math.max(0, coordinator.alive_count - 1)
    coordinator.phase = new_phase

    -- Update surviving gnomos to use new phase states
    local phase_module = coordinator.get_phase_module()
    if phase_module then
        for _, gnomo in pairs(coordinator.enemies) do
            if not gnomo.marked_for_destruction then
                gnomo.states = phase_module.states
                -- Don't interrupt current state - let them finish hit/death animations
                if gnomo.state and gnomo.state.name == "idle" then
                    gnomo:set_state(phase_module.states.idle)
                end
            end
        end
    end
end

--- Trigger victory - kill all remaining gnomos.
function coordinator.trigger_victory()
    coordinator.active = false
    coordinator.phase = 0

    -- Kill any remaining gnomos
    for _, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction then
            gnomo:die()
        end
    end

    if coordinator.on_victory then
        coordinator.on_victory()
    end
end

--- Hook for gnomo death events (called from phase death states).
--- Currently a no-op since phase transitions are damage-driven.
--- Kept as a hook for future extensibility (e.g., achievements, audio cues).
---@param _enemy table The gnomo that died (unused)
function coordinator.report_death(_enemy)
    -- Intentionally empty - deaths are managed by trigger_phase_transition
end

--- Get the current phase number (1-4).
---@return number Current phase (0 if dormant)
function coordinator.get_phase()
    return coordinator.phase
end

--- Get the current phase's state module.
---@return table|nil Phase module with states table
function coordinator.get_phase_module()
    if coordinator.phase < 1 or coordinator.phase > 4 then
        return nil
    end
    return get_phase_modules()[coordinator.phase]
end

--- Get combined health as a percentage (0-1).
--- Used by the boss health bar.
---@return number Health percentage
function coordinator.get_health_percent()
    if coordinator.total_max_health <= 0 then
        return 0
    end
    return coordinator.total_health / coordinator.total_max_health
end

--- Check if the encounter is active.
---@return boolean True if boss fight is in progress
function coordinator.is_active()
    return coordinator.active
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

--- Reset coordinator state for level cleanup.
function coordinator.reset()
    coordinator.active = false
    coordinator.phase = 0
    coordinator.enemies = {}
    coordinator.alive_count = 0
    coordinator.total_max_health = 20  -- Fixed shared health pool
    coordinator.total_health = 20
    coordinator.last_hit_gnomo = nil
    coordinator.on_victory = nil
end

return coordinator
