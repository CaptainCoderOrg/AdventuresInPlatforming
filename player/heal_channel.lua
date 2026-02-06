--- Heal channeling system for Minor Healing secondary ability.
--- Continuously converts energy into health while the ability button is held.
local controls = require("controls")
local Effects = require("Effects")

local heal_channel = {}

-- 1:1 energy-to-health ratio: full heal costs entire energy bar
local HEAL_RATE = 1
local PARTICLE_INTERVAL = 1 / 60

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

    -- Allows "No Energy" text to show again on next press
    if not holding then
        player._heal_no_energy_shown = false
    end

    if not holding or not in_allowed_state or not is_minor_healing then
        player._heal_channeling = false
        player._heal_particle_timer = 0
        return
    end

    local current_health = player.max_health - player.damage
    local current_energy = player.max_energy - player.energy_used

    if current_health >= player.max_health then
        player._heal_channeling = false
        player._heal_particle_timer = 0
        return
    end

    if current_energy <= 0 then
        player._heal_channeling = false
        player._heal_particle_timer = 0
        if not player._heal_no_energy_shown then
            player._heal_no_energy_shown = true
            Effects.create_energy_text(player.x, player.y, 0)
        end
        return
    end

    player._heal_channeling = true
    local heal_amount = HEAL_RATE * dt
    local missing_health = player.max_health - current_health
    heal_amount = math.min(heal_amount, current_energy, missing_health)

    player.energy_used = player.energy_used + heal_amount
    player.damage = math.max(0, player.damage - heal_amount)
    Effects.create_heal_text(player.x, player.y, heal_amount, player)

    player._heal_particle_timer = player._heal_particle_timer + dt
    local spawned = 0
    while player._heal_particle_timer >= PARTICLE_INTERVAL and spawned < 5 do
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
