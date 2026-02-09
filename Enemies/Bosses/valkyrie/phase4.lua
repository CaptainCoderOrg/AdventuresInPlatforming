--- Valkyrie Boss Phase 4: 25%-0% health.
--- Combined spikes + spears mode with dual button mechanics.
--- Both hazards activate in sequence, then dive-bomb loop begins.
--- Buttons disable individual hazards; both off → ground mode.
--- After 4 dives with one hazard disabled, boss re-enables it.
local audio = require("audio")
local combat = require("combat")
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local DIVE_JUMP_UP_DURATION = 0.5
local DIVE_OFF_SCREEN_OFFSET = 3
local DIVE_MAKE_CHOICE_DELAY = 0.8
local MAX_GROUND_ATTACKS = 2
local RE_ENABLE_DIVE_THRESHOLD = 4

local phase = {}
phase.states = {}

-- ── Shared states from common ───────────────────────────────────────────────

phase.states.prejump = common.states.prejump
phase.states.jump = common.states.jump
phase.states.prep_attack = common.states.prep_attack
phase.states.dash_attack = common.states.dash_attack
phase.states.recover = common.states.recover
phase.states.dive_bomb = common.states.dive_bomb
phase.states.ground_landing = common.states.ground_landing

-- ── Idle ────────────────────────────────────────────────────────────────────

--- Entry point from apply_phase_states. Cleans up all previous hazards.
phase.states.idle = {
    name = "idle",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.vx = 0

        -- Clean up all previous phase hazards
        coordinator.stop_spike_sequencer()
        coordinator.stop_spear_sequencer()
        coordinator.deactivate_spikes(0, 3)
    end,
    update = function(enemy, _dt)
        enemy:set_state(phase.states.enable_spikes)
    end,
    draw = common.draw_sprite,
}

-- ── Hazard Setup (two-bridge sequence) ──────────────────────────────────────

--- Jump to right bridge to activate spikes.
phase.states.enable_spikes = {
    name = "enable_spikes",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true

        local zone = coordinator.get_bridge_zone("right")
        if zone then
            local box = enemy.box
            local target_bottom = zone.y + (zone.height or 0)
            enemy._jump_target_x = zone.x
            enemy._jump_target_y = target_bottom - (box.y + box.h)
        end

        enemy._next_bridge_state = phase.states.bridge_attack_spikes
    end,
    update = function(enemy, _dt)
        enemy:set_state(common.states.prejump)
    end,
    draw = common.draw_sprite,
}

--- On right bridge: activate spike sequencer and set button callback.
phase.states.bridge_attack_spikes = {
    name = "bridge_attack_spikes",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.direction = 1  -- Face right
        enemy_common.set_animation(enemy, common.ANIMATIONS.ATTACK)
        enemy.animation.flipped = enemy.direction

        coordinator.reset_button("right")
        coordinator.start_spike_sequencer()
        coordinator.activate_blocks()

        -- Button callback: stop spikes (no _exit_dive_loop in phase 4)
        coordinator.set_button_callback("right", function()
            coordinator.stop_spike_sequencer()
            coordinator.deactivate_spikes(0, 3)
        end)
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.enable_spears)
        end
    end,
    draw = common.draw_sprite,
}

--- Jump to left bridge to activate spears.
phase.states.enable_spears = {
    name = "enable_spears",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")

        local zone = coordinator.get_bridge_zone("left")
        if zone then
            local box = enemy.box
            local target_bottom = zone.y + (zone.height or 0)
            enemy._jump_target_x = zone.x
            enemy._jump_target_y = target_bottom - (box.y + box.h)
        end

        enemy._next_bridge_state = phase.states.bridge_attack_spears
    end,
    update = function(enemy, _dt)
        enemy:set_state(common.states.prejump)
    end,
    draw = common.draw_sprite,
}

--- On left bridge: activate spear sequencer and set button callback.
phase.states.bridge_attack_spears = {
    name = "bridge_attack_spears",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.direction = -1  -- Face left
        enemy_common.set_animation(enemy, common.ANIMATIONS.ATTACK)
        enemy.animation.flipped = enemy.direction

        coordinator.reset_button("left")
        coordinator.start_spear_sequencer()
        coordinator.activate_blocks()

        -- Button callback: stop spears (no _exit_dive_loop in phase 4)
        coordinator.set_button_callback("left", function()
            coordinator.stop_spear_sequencer()
        end)

        enemy._dive_count = 0
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.start_dive_loop)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Landing (phase-specific routing) ────────────────────────────────────────

--- Routes via _next_bridge_state for bridge transitions, or to prep_attack for ground mode.
phase.states.landing = {
    name = "landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
        -- AoE knockback when landing on a bridge
        if enemy._next_bridge_state then
            common.bridge_landing_aoe(enemy)
        end
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            local next_state = enemy._next_bridge_state
            if next_state then
                enemy._next_bridge_state = nil
                enemy:set_state(next_state)
            else
                enemy:set_state(enemy.states.prep_attack)
            end
        end
    end,
    draw = common.draw_sprite,
}

-- ── Dive Loop ───────────────────────────────────────────────────────────────

--- Ascend off screen to begin dive loop. Used for first entry and after re-enable.
phase.states.start_dive_loop = {
    name = "start_dive_loop",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        coordinator.activate_blocks()

        enemy._ascend_start_y = enemy.y
        enemy._ascend_target_y = coordinator.camera:get_y() - DIVE_OFF_SCREEN_OFFSET
        enemy._ascend_timer = 0

        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation.frame = 1
        enemy.animation:pause()
    end,
    update = function(enemy, dt)
        enemy._ascend_timer = enemy._ascend_timer + dt
        local progress = math.min(1, enemy._ascend_timer / DIVE_JUMP_UP_DURATION)

        enemy.y = enemy._ascend_start_y + (enemy._ascend_target_y - enemy._ascend_start_y) * progress
        combat.update(enemy)

        if progress >= 1 then
            enemy:set_state(enemy.states.dive_bomb)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Jump Off Screen (decision point) ────────────────────────────────────────

--- After each dive bomb: increment count and decide next action based on button states.
phase.states.jump_off_screen = {
    name = "jump_off_screen",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")

        local right_pressed = coordinator.is_button_pressed("right")
        local left_pressed = coordinator.is_button_pressed("left")

        -- Only count dives toward re-enable threshold when a button is pressed
        if right_pressed or left_pressed then
            enemy._dive_count = (enemy._dive_count or 0) + 1
        end

        -- Both pressed: exit to ground mode
        if right_pressed and left_pressed then
            enemy._dive_count = 0
            enemy.invulnerable = false
            enemy:set_state(enemy.states.ground_landing)
            return
        end

        -- One pressed + enough dives: re-enable that hazard
        if enemy._dive_count >= RE_ENABLE_DIVE_THRESHOLD then
            if right_pressed then
                enemy._dive_count = 0
                local zone = coordinator.get_bridge_zone("right")
                if zone then
                    local box = enemy.box
                    local target_bottom = zone.y + (zone.height or 0)
                    enemy._jump_target_x = zone.x
                    enemy._jump_target_y = target_bottom - (box.y + box.h)
                end
                enemy._next_bridge_state = phase.states.bridge_re_enable_spikes
                enemy:set_state(common.states.prejump)
                return
            elseif left_pressed then
                enemy._dive_count = 0
                local zone = coordinator.get_bridge_zone("left")
                if zone then
                    local box = enemy.box
                    local target_bottom = zone.y + (zone.height or 0)
                    enemy._jump_target_x = zone.x
                    enemy._jump_target_y = target_bottom - (box.y + box.h)
                end
                enemy._next_bridge_state = phase.states.bridge_re_enable_spears
                enemy:set_state(common.states.prejump)
                return
            end
        end

        -- Continue dive loop: ascend off screen
        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        coordinator.activate_blocks()

        enemy._ascend_start_y = enemy.y
        enemy._ascend_target_y = coordinator.camera:get_y() - DIVE_OFF_SCREEN_OFFSET
        enemy._ascend_timer = 0

        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation.frame = 1
        enemy.animation:pause()
    end,
    update = function(enemy, dt)
        enemy._ascend_timer = enemy._ascend_timer + dt
        local progress = math.min(1, enemy._ascend_timer / DIVE_JUMP_UP_DURATION)

        enemy.y = enemy._ascend_start_y + (enemy._ascend_target_y - enemy._ascend_start_y) * progress
        combat.update(enemy)

        if progress >= 1 then
            enemy:set_state(enemy.states.dive_bomb)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Re-enable Hazards ───────────────────────────────────────────────────────

--- Re-enable spikes on right bridge after player disabled them too long.
phase.states.bridge_re_enable_spikes = {
    name = "bridge_re_enable_spikes",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.direction = 1  -- Face right
        enemy_common.set_animation(enemy, common.ANIMATIONS.ATTACK)
        enemy.animation.flipped = enemy.direction

        coordinator.start_spike_sequencer()
        coordinator.reset_button("right")
        coordinator.activate_blocks()

        coordinator.set_button_callback("right", function()
            coordinator.stop_spike_sequencer()
            coordinator.deactivate_spikes(0, 3)
        end)

        enemy._dive_count = 0
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.start_dive_loop)
        end
    end,
    draw = common.draw_sprite,
}

--- Re-enable spears on left bridge after player disabled them too long.
phase.states.bridge_re_enable_spears = {
    name = "bridge_re_enable_spears",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.direction = -1  -- Face left
        enemy_common.set_animation(enemy, common.ANIMATIONS.ATTACK)
        enemy.animation.flipped = enemy.direction

        coordinator.start_spear_sequencer()
        coordinator.reset_button("left")
        coordinator.activate_blocks()

        coordinator.set_button_callback("left", function()
            coordinator.stop_spear_sequencer()
        end)

        enemy._dive_count = 0
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.start_dive_loop)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Ground Mode ─────────────────────────────────────────────────────────────

--- Entry into ground mode. Resets attack counter, faces player, waits before jumping.
phase.states.dive_make_choice = {
    name = "dive_make_choice",
    start = function(enemy)
        enemy._ground_attack_count = 0

        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        if enemy.animation then
            enemy.animation.flipped = enemy.direction
        end
        enemy._choice_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end

        enemy._choice_timer = enemy._choice_timer + dt
        if enemy._choice_timer >= DIVE_MAKE_CHOICE_DELAY then
            common.set_jump_target_nearest_player(enemy)
            enemy:set_state(common.states.prejump)
        end
    end,
    draw = common.draw_sprite,
}

--- Ground-mode cycle point. Counts attacks, exits after MAX_GROUND_ATTACKS.
phase.states.make_choice = {
    name = "make_choice",
    start = function(enemy)
        enemy._ground_attack_count = (enemy._ground_attack_count or 0) + 1

        if enemy._ground_attack_count >= MAX_GROUND_ATTACKS then
            enemy:set_state(phase.states.enable_spikes)
            return
        end

        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        if enemy.animation then
            enemy.animation.flipped = enemy.direction
        end
        enemy._choice_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end

        enemy._choice_timer = enemy._choice_timer + dt
        if enemy._choice_timer >= DIVE_MAKE_CHOICE_DELAY then
            common.set_jump_target_nearest_player(enemy)
            enemy:set_state(common.states.prejump)
        end
    end,
    draw = common.draw_sprite,
}

-- ── Hit / Death ─────────────────────────────────────────────────────────────

--- Hit during ground mode: always return to hazard setup.
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
            enemy:set_state(phase.states.enable_spikes)
        end
    end,
    draw = common.draw_sprite,
}

phase.states.death = common.create_death_state()

return phase
