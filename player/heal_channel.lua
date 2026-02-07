--- Heal channeling system for Minor Healing secondary ability.
--- Continuously converts energy into health while the ability button is held.
local controls = require("controls")
local Effects = require("Effects")
local upgrade_effects = require("upgrade/effects")

local heal_channel = {}

-- 1:1 energy-to-health ratio: full heal costs entire energy bar
local HEAL_RATE = 1
local PARTICLE_INTERVAL = 1 / 60  -- One particle per frame at 60fps
local MAX_PARTICLES_PER_FRAME = 5

--- Resets channeling state on the player (called on any cancel condition).
---@param player table Player instance
local function stop_channeling(player)
    player._heal_channeling = false
    player._heal_particle_timer = 0
end

-- Populated on first update to avoid circular require with player states
local CHANNEL_STATES = {}
local states_initialized = false

---@param states table Player states table
local function init_states(states)
    CHANNEL_STATES[states.idle] = true
    CHANNEL_STATES[states.run] = true
    CHANNEL_STATES[states.air] = true
    states_initialized = true
end

--- Updates heal channeling for one frame.
--- Called from Player:update() after state update and before stamina regen.
---@param player table Player instance
---@param dt number Delta time in seconds
function heal_channel.update(player, dt)
    if not states_initialized then
        init_states(player.states)
    end

    local holding = controls.ability_down()
    local in_allowed_state = CHANNEL_STATES[player.state]
    local is_minor_healing = player.active_secondary == "minor_healing"

    -- Allows text popups to show again on next press
    if not holding then
        player._heal_no_energy_shown = false
        player._heal_full_health_shown = false
    end

    if not holding or not in_allowed_state or not is_minor_healing then
        stop_channeling(player)
        return
    end

    local current_health = player.max_health - player.damage
    local current_energy = player.max_energy - player.energy_used

    if current_health >= player.max_health then
        -- Only show "Full Health" on fresh press, not when channeling healed to full
        if not player._heal_channeling and not player._heal_full_health_shown then
            player._heal_full_health_shown = true
            Effects.create_text(player.x, player.y, "Full Health")
        end
        stop_channeling(player)
        return
    end

    if current_energy <= 0 then
        stop_channeling(player)
        if not player._heal_no_energy_shown then
            player._heal_no_energy_shown = true
            Effects.create_energy_text(player.x, player.y, 0)
        end
        return
    end

    player._heal_channeling = true
    local heal_rate = upgrade_effects.get_heal_rate(player)
    local energy_ratio = upgrade_effects.get_energy_ratio(player)
    local heal_amount = heal_rate * dt
    local missing_health = player.max_health - current_health
    local max_from_energy = current_energy / energy_ratio
    heal_amount = math.min(heal_amount, max_from_energy, missing_health)

    player.energy_used = player.energy_used + (heal_amount * energy_ratio)
    player.damage = math.max(0, player.damage - heal_amount)
    Effects.create_heal_text(player.x, player.y, heal_amount, player)

    player._heal_particle_timer = player._heal_particle_timer + dt
    local spawned = 0
    while player._heal_particle_timer >= PARTICLE_INTERVAL and spawned < MAX_PARTICLES_PER_FRAME do
        player._heal_particle_timer = player._heal_particle_timer - PARTICLE_INTERVAL
        Effects.create_heal_particle(player.x + 0.5, player.y + 0.5)
        spawned = spawned + 1
    end
    -- Discard excess accumulated time (prevents burst after lag spikes)
    if player._heal_particle_timer >= PARTICLE_INTERVAL then
        player._heal_particle_timer = 0
    end
end

return heal_channel
