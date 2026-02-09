--- Valkyrie Boss Phase 2: 75%-50% health.
--- Spike mode (dive bomb loop with rolling spike waves) and ground mode (jump-attack pattern).
--- Player presses right_button to disable spikes and bring boss to ground.
local audio = require("audio")
local combat = require("combat")
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local MAKE_CHOICE_DELAY = 0.8
local JUMP_UP_DURATION = 0.5
local DIVE_WAIT = 1.0
local DIVE_DURATION = 0.75
local DIVE_CONTACT_DAMAGE = 3
local DIVE_TRAIL_INTERVAL = 0.05
local OFF_SCREEN_OFFSET = 3  -- tiles above camera:get_y()

local phase = {}
phase.states = {}

-- ── Shared states from common ───────────────────────────────────────────────

phase.states.prejump = common.states.prejump
phase.states.jump = common.states.jump
phase.states.prep_attack = common.states.prep_attack
phase.states.dash_attack = common.states.dash_attack
phase.states.recover = common.states.recover

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

--- Set invulnerable, target bridge right, flag spike mode entry.
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

        enemy._entering_spike_mode = true
    end,
    update = function(enemy, _dt)
        enemy:set_state(common.states.prejump)
    end,
    draw = common.draw_sprite,
}

--- Custom landing: routes to bridge_attack in spike mode, prep_attack in ground mode.
phase.states.landing = {
    name = "landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            if enemy._entering_spike_mode then
                enemy._entering_spike_mode = false
                enemy:set_state(phase.states.bridge_attack)
            else
                enemy:set_state(common.states.prep_attack)
            end
        end
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

        -- Button callback: exit dive loop when player presses right button
        coordinator.set_button_callback("right", function()
            enemy._exit_dive_loop = true
            coordinator.stop_spike_sequencer()
            coordinator.deactivate_spikes(0, 3)
        end)
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.jump_off_screen)
        end
    end,
    draw = common.draw_sprite,
}

--- Ascend off screen. If button was pressed, skip to ground mode.
phase.states.jump_off_screen = {
    name = "jump_off_screen",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")

        -- Early exit: button was pressed during bridge_attack
        if enemy._exit_dive_loop then
            enemy._exit_dive_loop = false
            coordinator.stop_spike_sequencer()
            coordinator.deactivate_spikes(0, 3)
            enemy.invulnerable = false
            enemy:set_state(phase.states.make_choice)
            return
        end

        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        -- Refresh boss blocks
        coordinator.activate_blocks()

        -- Target: above camera top
        enemy._ascend_start_y = enemy.y
        enemy._ascend_target_y = coordinator.camera:get_y() - OFF_SCREEN_OFFSET
        enemy._ascend_timer = 0

        -- Hold JUMP frame 1 (airborne pose)
        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation.frame = 1
        enemy.animation:pause()
    end,
    update = function(enemy, dt)
        enemy._ascend_timer = enemy._ascend_timer + dt
        local progress = math.min(1, enemy._ascend_timer / JUMP_UP_DURATION)

        enemy.y = enemy._ascend_start_y + (enemy._ascend_target_y - enemy._ascend_start_y) * progress
        combat.update(enemy)

        if progress >= 1 then
            enemy:set_state(phase.states.dive_bomb)
        end
    end,
    draw = common.draw_sprite,
}

--- Dive bomb: wait off-screen, then plunge at player position.
phase.states.dive_bomb = {
    name = "dive_bomb",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        enemy._dive_waiting = true
        enemy._dive_timer = 0
        enemy._dive_trail_timer = 0
    end,
    update = function(enemy, dt)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy._dive_timer = enemy._dive_timer + dt

        if enemy._dive_waiting then
            -- Wait phase: invisible off-screen
            if enemy._dive_timer >= DIVE_WAIT then
                enemy._dive_waiting = false
                enemy._dive_timer = 0

                -- Move valkyrie to player's X (invisible off-screen, position is arbitrary)
                -- Floor Y = bottom of valkyrie_boss_middle zone
                local player = enemy.target_player
                local box = enemy.box

                if player then
                    local player_cx = player.x + (player.box.x + player.box.w / 2)
                    local offset = (math.random() < 0.5) and -3 or 3
                    local target_x = player_cx - (box.x + box.w / 2) + offset

                    -- Clamp within camera horizontal bounds
                    local cam = coordinator.camera
                    if cam then
                        local sprites = require("sprites")
                        local cam_left = cam:get_x()
                        local cam_right = cam_left + cam:get_viewport_width() / sprites.tile_size
                        local enemy_left = target_x + box.x
                        local enemy_right = target_x + box.x + box.w
                        if enemy_left < cam_left then
                            target_x = target_x + (cam_left - enemy_left)
                        elseif enemy_right > cam_right then
                            target_x = target_x - (enemy_right - cam_right)
                        end
                    end

                    enemy.x = target_x
                end

                local middle_zone = coordinator.get_zone("middle")
                local floor_y = middle_zone and (middle_zone.y + (middle_zone.height or 0)) or enemy.y
                enemy._dive_target_y = floor_y - (box.y + box.h)

                -- Target is player's X; start is offset for angled descent
                if player then
                    local player_cx = player.x + (player.box.x + player.box.w / 2)
                    enemy._dive_target_x = player_cx - (box.x + box.w / 2)
                else
                    enemy._dive_target_x = enemy.x
                end
                enemy._dive_start_x = enemy.x
                enemy._dive_start_y = enemy.y

                -- Refresh boss blocks
                coordinator.activate_blocks()

                -- Switch to FALL animation, face toward target
                enemy_common.set_animation(enemy, common.ANIMATIONS.FALL)
                local dir = enemy._dive_target_x > enemy.x and 1 or -1
                enemy.direction = dir
                enemy.animation.flipped = dir
            end
        else
            -- Descent phase: linear tween to target
            local progress = math.min(1, enemy._dive_timer / DIVE_DURATION)

            enemy.x = enemy._dive_start_x + (enemy._dive_target_x - enemy._dive_start_x) * progress
            enemy.y = enemy._dive_start_y + (enemy._dive_target_y - enemy._dive_start_y) * progress

            combat.update(enemy)

            -- Ghost trail
            enemy._dive_trail_timer = enemy._dive_trail_timer + dt
            if enemy._dive_trail_timer >= DIVE_TRAIL_INTERVAL then
                enemy._dive_trail_timer = enemy._dive_trail_timer - DIVE_TRAIL_INTERVAL
                common.spawn_ghost_trail(enemy)
            end

            -- Contact damage
            local player = enemy.target_player
            if player and not player:is_invincible() and player:health() > 0 then
                if combat.collides(enemy, player) then
                    player:take_damage(DIVE_CONTACT_DAMAGE, enemy.x)
                end
            end

            if progress >= 1 then
                if enemy._exit_dive_loop then
                    enemy._exit_dive_loop = false
                    enemy:set_state(phase.states.ground_landing)
                else
                    audio.play_landing_sound()
                    enemy:set_state(phase.states.jump_off_screen)
                end
            end
        end
    end,
    draw = function(enemy)
        -- Invisible during wait phase
        if enemy._dive_waiting then return end
        common.draw_sprite(enemy)
    end,
}

-- ── Ground Mode ─────────────────────────────────────────────────────────────

--- Landing after dive bomb exit: transition to ground attack pattern.
phase.states.ground_landing = {
    name = "ground_landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.make_choice)
        end
    end,
    draw = common.draw_sprite,
}

--- Face player, wait, then jump to nearest zone for attack.
phase.states.make_choice = {
    name = "make_choice",
    start = function(enemy)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.animation.flipped = enemy.direction
        enemy._choice_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end

        enemy._choice_timer = enemy._choice_timer + dt
        if enemy._choice_timer >= MAKE_CHOICE_DELAY then
            common.set_jump_target_nearest_player(enemy)
            enemy:set_state(common.states.prejump)
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
