--- Gnomo Boss Coordinator: Manages shared state for the 4-gnomo boss encounter.
--- Uses a shared health pool with phase transitions at health thresholds.
--- IMPORTANT: Call coordinator.reset() on level cleanup to clear state.
local coordinator = {
    active = false,
    phase = 0,              -- 0=dormant, 1-4=active phases
    enemies = {},           -- References to all 4 gnomos (keyed by color)
    alive_count = 0,
    total_max_health = 16,  -- Fixed shared health pool
    total_health = 16,      -- Current shared health
    last_hit_gnomo = nil,   -- Most recently hit gnomo (dies at phase transition)
    on_victory = nil,       -- Callback when all dead
    player = nil,           -- Player reference for defeated_bosses tracking
    boss_id = "gnomo_brothers",  -- ID for defeated_bosses tracking
    boss_name = "Gnomo Brothers",
    boss_subtitle = "Axe Wielding Schemers",
    occupied_platforms = {}, -- { [platform_index] = gnomo_color }
    phase0_complete_count = 0, -- Track gnomos that finished phase 0
    -- Phase transition state
    transitioning_to_phase = nil,  -- Pending phase number (2, 3, 4)
    transition_ready_count = 0,    -- Gnomos that reached wait_state during transition
    -- Phase 2 ground tracking
    player_on_ground = true,       -- Whether player is within ground level bounds
    bottom_gnomo = nil,            -- Color of gnomo using bottom-right position
    last_bottom_gnomo = nil,       -- Color of gnomo that was last in bottom position
}

-- Health thresholds for phase transitions (percentage of max health)
-- Phase 1: 100%-75%, Phase 2: 75%-50%, Phase 3: 50%-25%, Phase 4: 25%-0%
-- Note: 0% is handled by trigger_victory(), not as a phase transition
local PHASE_THRESHOLDS = { 0.75, 0.50, 0.25 }

-- Phase modules (lazy loaded to avoid circular requires)
local phase_modules = nil

-- Audio (lazy loaded)
local audio = nil

-- Reusable table for get_unoccupied_platforms (avoids allocation per call)
local available_platforms = {}

--- Lazy load phase modules
---@return table Phase modules indexed by number
local function get_phase_modules()
    if not phase_modules then
        phase_modules = {
            [0] = require("Enemies/Bosses/gnomo/phase0"),
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
--- Transitions from dormant to phase 0 (intro), then to phase 1.
---@param player table|nil Player reference for defeated_bosses tracking
function coordinator.start(player)
    if coordinator.active then return end

    coordinator.active = true
    coordinator.phase = 0
    coordinator.phase0_complete_count = 0
    coordinator.player = player

    -- Start boss music (fades in as title/subtitle appear)
    audio = audio or require("audio")
    audio.play_music(audio.gnomo_boss)

    -- Notify all gnomos to use phase 0 states (jump to holes)
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

    for i = 1, 3 do
        local threshold = PHASE_THRESHOLDS[i]
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
--- Sets transitioning_to_phase flag; actual phase switch happens in complete_phase_transition()
--- when all surviving gnomos have exited to wait_state.
--- Special case: During phase 0, skip directly to phase 2.
---@param new_phase number The phase to transition to (2, 3, or 4)
function coordinator.trigger_phase_transition(new_phase)
    if new_phase <= coordinator.phase and coordinator.phase ~= 0 then return end
    if coordinator.transitioning_to_phase then return end  -- Already transitioning

    -- During phase 0, always skip to phase 2
    if coordinator.phase == 0 then
        new_phase = math.max(new_phase, 2)
    end

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

    -- During phase 0, transition immediately (gnomos aren't in states that check for transitions)
    if coordinator.phase == 0 then
        coordinator.transitioning_to_phase = new_phase
        coordinator.complete_phase_transition()
        return
    end

    -- Set transition pending - surviving gnomos will exit and report ready
    coordinator.transitioning_to_phase = new_phase
    coordinator.transition_ready_count = 0

    -- Count gnomos already in wait_state as ready (they won't call report_transition_ready again)
    -- Skip gnomos in death state - they're not transitioning, they're dying
    for _, gnomo in pairs(coordinator.enemies) do
        local is_dying = gnomo.state and gnomo.state.name == "death"
        if not gnomo.marked_for_destruction and not is_dying and gnomo.state and gnomo.state.name == "wait_state" then
            coordinator.transition_ready_count = coordinator.transition_ready_count + 1
        end
    end

    -- If all surviving gnomos are already waiting, complete immediately
    if coordinator.transition_ready_count >= coordinator.alive_count then
        coordinator.complete_phase_transition()
    end
end

--- Report that a gnomo has reached wait_state during a phase transition.
--- When all surviving gnomos report ready, completes the phase transition.
---@param _enemy table The gnomo that finished exiting (unused)
function coordinator.report_transition_ready(_enemy)
    if not coordinator.transitioning_to_phase then return end

    coordinator.transition_ready_count = coordinator.transition_ready_count + 1

    -- Check if all surviving gnomos are ready
    if coordinator.transition_ready_count >= coordinator.alive_count then
        coordinator.complete_phase_transition()
    end
end

--- Complete a pending phase transition after all gnomos have exited.
--- Switches to the new phase and updates gnomo state machines.
function coordinator.complete_phase_transition()
    if not coordinator.transitioning_to_phase then return end

    local new_phase = coordinator.transitioning_to_phase
    coordinator.phase = new_phase
    coordinator.transitioning_to_phase = nil
    coordinator.transition_ready_count = 0

    -- Clear all platform occupation
    coordinator.occupied_platforms = {}

    -- Reset bottom gnomo tracking for phase 2
    coordinator.bottom_gnomo = nil
    coordinator.last_bottom_gnomo = nil

    -- Initialize player ground status before gnomos make decisions
    local common = require("Enemies/Bosses/gnomo/common")
    common.is_player_on_ground(coordinator.player)

    -- Update surviving gnomos to use new phase states
    local phase_module = coordinator.get_phase_module()
    if phase_module then
        for _, gnomo in pairs(coordinator.enemies) do
            -- Skip dead gnomos (marked for destruction OR in death state)
            local is_dying = gnomo.state and gnomo.state.name == "death"
            if not gnomo.marked_for_destruction and not is_dying then
                -- Clean up gnomo state for fresh phase start
                gnomo._platform_index = nil
                gnomo._exit_hole_index = nil
                gnomo._exited_from_hit = false
                gnomo._post_attack_idle = false
                gnomo._is_bottom_attacker = false
                gnomo.alpha = 0
                gnomo.invulnerable = false
                gnomo.vx = 0
                gnomo.vy = 0
                gnomo.gravity = 0

                -- Ensure gnomo is intangible
                if not gnomo._intangible_shape then
                    common.make_intangible(gnomo)
                end

                -- Switch to new phase states
                gnomo.states = phase_module.states
                -- Start in initial_wait for staggered appearance
                if phase_module.states.initial_wait then
                    gnomo:set_state(phase_module.states.initial_wait)
                else
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

    -- Find a gnomo to use as axe spawn point (before killing them)
    local last_gnomo = nil
    for _, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction then
            last_gnomo = gnomo
        end
    end

    -- Kill any remaining gnomos
    for _, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction then
            gnomo:die()
        end
    end

    -- Start victory sequence with last gnomo position
    if coordinator.on_victory then
        coordinator.on_victory(last_gnomo)
    end
end

--- Hook for gnomo death events (called from phase death states).
--- Currently a no-op since phase transitions are damage-driven.
--- Kept as a hook for future extensibility (e.g., achievements, audio cues).
---@param _enemy table The gnomo that died (unused)
function coordinator.report_death(_enemy)
    -- Intentionally empty - deaths are managed by trigger_phase_transition
end

--- Report that a gnomo has completed phase 0 (jumped to hole).
--- When all gnomos finish, transitions to phase 1.
---@param _enemy table The gnomo that finished (unused)
function coordinator.report_phase0_complete(_enemy)
    if coordinator.phase ~= 0 then return end

    coordinator.phase0_complete_count = coordinator.phase0_complete_count + 1

    -- When all alive gnomos have finished phase 0, transition to phase 1
    if coordinator.phase0_complete_count >= coordinator.alive_count then
        coordinator.transition_to_phase1()
    end
end

--- Transition from phase 0 to phase 1.
--- All gnomos will appear from holes after a random delay.
function coordinator.transition_to_phase1()
    coordinator.phase = 1

    local phase_module = coordinator.get_phase_module()
    if phase_module then
        for _, enemy in pairs(coordinator.enemies) do
            if not enemy.marked_for_destruction then
                enemy.states = phase_module.states
                -- Start in initial_wait for staggered appearance
                enemy:set_state(phase_module.states.initial_wait)
            end
        end
    end
end

--- Get the current phase number (1-4).
---@return number Current phase (0 if dormant)
function coordinator.get_phase()
    return coordinator.phase
end

--- Get the current phase's state module.
---@return table|nil Phase module with states table
function coordinator.get_phase_module()
    if coordinator.phase < 0 or coordinator.phase > 4 then
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

--------------------------------------------------------------------------------
-- Platform tracking
--------------------------------------------------------------------------------

--- Claim a platform as occupied by a gnomo.
---@param platform_index number Platform index (1-4)
---@param color string Gnomo color identifier
function coordinator.claim_platform(platform_index, color)
    coordinator.occupied_platforms[platform_index] = color
end

--- Release a platform so another gnomo can use it.
---@param platform_index number Platform index (1-4)
function coordinator.release_platform(platform_index)
    coordinator.occupied_platforms[platform_index] = nil
end

--- Get list of unoccupied platform indices.
--- Note: Returns a reusable table - do not cache the result.
---@return table Array of available platform indices
function coordinator.get_unoccupied_platforms()
    local count = 0
    for i = 1, 4 do
        if not coordinator.occupied_platforms[i] then
            count = count + 1
            available_platforms[count] = i
        end
    end
    -- Clear any stale entries from previous calls
    for i = count + 1, #available_platforms do
        available_platforms[i] = nil
    end
    return available_platforms
end

--------------------------------------------------------------------------------
-- Ground tracking (Phase 2)
--------------------------------------------------------------------------------

--- Update player ground status for Phase 2 behavior.
--- Called from common.is_player_on_ground() which checks spawn point bounds.
---@param on_ground boolean Whether player is within ground level bounds
function coordinator.update_player_ground_status(on_ground)
    coordinator.player_on_ground = on_ground
end

--- Claim the bottom-right position for a gnomo.
---@param color string Gnomo color identifier
function coordinator.claim_bottom_position(color)
    coordinator.bottom_gnomo = color
end

--- Release the bottom-right position.
function coordinator.release_bottom_position()
    if coordinator.bottom_gnomo then
        coordinator.last_bottom_gnomo = coordinator.bottom_gnomo
        coordinator.bottom_gnomo = nil
    end
end

--- Check if the bottom-right position is available.
---@return boolean True if no gnomo is in bottom position
function coordinator.is_bottom_available()
    return coordinator.bottom_gnomo == nil
end

--- Get available platforms for Phase 2 based on player position.
--- When player on ground: Only platforms 2, 3 available.
--- When player off ground: All 4 platforms available.
--- Note: Returns a reusable table - do not cache the result.
---@return table Array of available platform indices
function coordinator.get_phase2_platforms()
    local count = 0
    local start_idx = coordinator.player_on_ground and 2 or 1
    local end_idx = coordinator.player_on_ground and 3 or 4

    for i = start_idx, end_idx do
        if not coordinator.occupied_platforms[i] then
            count = count + 1
            available_platforms[count] = i
        end
    end
    -- Clear any stale entries from previous calls
    for i = count + 1, #available_platforms do
        available_platforms[i] = nil
    end
    return available_platforms
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
--- Note: on_victory callback is preserved (set once at startup, reused across resets)
function coordinator.reset()
    coordinator.active = false
    coordinator.phase = 0
    coordinator.enemies = {}
    coordinator.alive_count = 0
    coordinator.total_max_health = 16  -- Fixed shared health pool
    coordinator.total_health = 16
    coordinator.last_hit_gnomo = nil
    coordinator.player = nil
    coordinator.occupied_platforms = {}
    coordinator.phase0_complete_count = 0
    -- Phase transition state
    coordinator.transitioning_to_phase = nil
    coordinator.transition_ready_count = 0
    -- Phase 2 ground tracking
    coordinator.player_on_ground = true
    coordinator.bottom_gnomo = nil
    coordinator.last_bottom_gnomo = nil
    -- on_victory is intentionally NOT reset - it's set once at startup

    -- Reset cinematic state (lazy load to avoid circular dependency)
    local cinematic = require("Enemies/Bosses/gnomo/cinematic")
    cinematic.reset()

    -- Reset victory sequence state
    local victory = require("Enemies/Bosses/gnomo/victory")
    victory.reset()

    -- Reset common module cache
    local common = require("Enemies/Bosses/gnomo/common")
    common.reset()
end

return coordinator
