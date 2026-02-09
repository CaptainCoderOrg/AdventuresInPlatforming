--- Valkyrie Boss Phase 2: 75%-50% health.
--- Spike mode (dive bomb loop with rolling spike waves) and ground mode (jump-attack pattern).
--- Player presses right_button to disable spikes and bring boss to ground.
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local phase = {}
phase.states = {}

-- ── Shared states from common ───────────────────────────────────────────────

phase.states.prejump = common.states.prejump
phase.states.jump = common.states.jump
phase.states.prep_attack = common.states.prep_attack
phase.states.dash_attack = common.states.dash_attack
phase.states.recover = common.states.recover
phase.states.landing = common.states.hazard_landing
phase.states.jump_off_screen = common.states.jump_off_screen
phase.states.dive_bomb = common.states.dive_bomb
phase.states.ground_landing = common.states.ground_landing
phase.states.dive_make_choice = common.states.dive_make_choice
phase.states.make_choice = common.states.dive_make_choice

-- ── Idle ────────────────────────────────────────────────────────────────────

--- Entry point from apply_phase_states. Transitions to turn_on_spikes.
--- On the first phase 2 entry, on_hit overrides this with hit → turn_on_spikes.
phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, _dt)
        enemy:set_state(phase.states.turn_on_spikes)
    end,
    draw = common.draw_sprite,
}

-- ── Spike Mode ──────────────────────────────────────────────────────────────

--- Set invulnerable, target bridge right, flag hazard mode entry.
phase.states.turn_on_spikes = {
    name = "turn_on_spikes",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true

        -- Set jump target to bridge right (hitbox-bottom aligned)
        local zone = coordinator.get_bridge_zone("right")
        if zone then
            local box = enemy.box
            local target_bottom = zone.y + (zone.height or 0)
            enemy._jump_target_x = zone.x
            enemy._jump_target_y = target_bottom - (box.y + box.h)
        end

        enemy._entering_hazard_mode = true
    end,
    update = function(enemy, _dt)
        enemy:set_state(common.states.prejump)
    end,
    draw = common.draw_sprite,
}

--- On the bridge: play attack animation, activate spikes and button callback.
phase.states.bridge_attack = {
    name = "bridge_attack",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy._exit_dive_loop = false  -- Clear stale flag from previous cycle
        enemy.direction = 1  -- Face right
        enemy_common.set_animation(enemy, common.ANIMATIONS.ATTACK)
        enemy.animation.flipped = enemy.direction

        -- Reset button, start spike wave, activate arena walls
        coordinator.reset_button("right")
        coordinator.start_spike_sequencer()
        coordinator.activate_blocks()

        -- Set phase-specific hazard cleanup
        enemy._hazard_cleanup = function()
            coordinator.stop_spike_sequencer()
            coordinator.deactivate_spikes(0, 3)
        end

        -- Button callback: exit dive loop when player presses right button
        coordinator.set_button_callback("right", function()
            enemy._exit_dive_loop = true
            if enemy._hazard_cleanup then enemy._hazard_cleanup() end
        end)
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(common.states.jump_off_screen)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Hit / Death ─────────────────────────────────────────────────────────────

--- Hit during ground mode: always return to spike mode.
phase.states.hit = {
    name = "hit",
    start = function(enemy)
        enemy._in_prep_attack = false
        enemy_common.set_animation(enemy, common.ANIMATIONS.HIT)
        enemy.vx = (enemy.hit_direction or -1) * 2
    end,
    update = function(enemy, dt)
        enemy.vx = enemy_common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.turn_on_spikes)
        end
    end,
    draw = common.draw_sprite,
}

phase.states.death = common.create_death_state()

return phase
