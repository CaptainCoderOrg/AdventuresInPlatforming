--- Gnomo Boss Phase 3: Duo (2 gnomos alive)
--- Bottom gnomo uses scatter_throw pattern when player is airborne.
--- Platform gnomo uses rapid_attack pattern from phase 2.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")
local audio = require("audio")

local phase = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PHASE3_START_DELAY = 1.5
local MAX_PLATFORM_GNOMOS = 1

-- Scatter throw constants (unique to phase 3)
local SCATTER_THROW_SPEED_MULTIPLIER = 1.5
local SCATTER_THROW_START_ANGLE = 180
local SCATTER_THROW_STEP = 18
local SCATTER_THROW_PAIR_SPREAD = 36
local SCATTER_THROW_COUNT = 5
local POST_SCATTER_IDLE_DURATION = 1.5

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

phase.states = {}

phase.states.initial_wait = {
    name = "initial_wait",
    start = function(enemy)
        enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
        enemy._wait_duration = PHASE3_START_DELAY
        enemy._wait_timer = 0

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end

        common.is_player_on_ground(enemy.target_player)
    end,
    update = function(enemy, dt)
        enemy._wait_timer = enemy._wait_timer + dt
        if enemy._wait_timer >= enemy._wait_duration then
            common.is_player_on_ground(enemy.target_player)
            enemy:set_state(phase.states.decide_role)
        end
    end,
    draw = common.noop,
}

phase.states.decide_role = {
    name = "decide_role",
    start = function(enemy)
        common.is_player_on_ground(enemy.target_player)

        local go_to_bottom = not coordinator.player_on_ground
            and coordinator.is_bottom_available()

        if go_to_bottom then
            enemy:set_state(phase.states.bottom_enter_attack)
        elseif common.count_occupied_platforms() < MAX_PLATFORM_GNOMOS then
            enemy:set_state(phase.states.appear_state)
        else
            enemy:set_state(phase.states.wait_state)
        end
    end,
    update = common.noop,
    draw = common.noop,
}

phase.states.appear_state = common.create_appear_state(
    function() return phase.states.idle end,
    function() return phase.states.wait_state end,
    MAX_PLATFORM_GNOMOS
)

-- Phase 3 bottom enter goes directly to scatter_throw (not bottom_idle)
phase.states.bottom_enter_attack = {
    name = "bottom_enter_attack",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        coordinator.claim_bottom_position(enemy.color)
        enemy._is_bottom_attacker = true

        local hx, hy = common.get_marker_position("gnomo_boss_exit_bottom_right")
        if hx and hy then
            enemy._lerp_start_x = hx + common.BOTTOM_OFFSET_X
            enemy._lerp_start_y = hy
            enemy._lerp_end_x = hx
            enemy._lerp_end_y = hy
        else
            enemy._lerp_start_x = enemy.x + common.BOTTOM_OFFSET_X
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = enemy.x
            enemy._lerp_end_y = enemy.y
        end

        enemy.x = enemy._lerp_start_x
        enemy.y = enemy._lerp_start_y
        enemy._lerp_timer = 0
        enemy.alpha = 0
        common.set_direction(enemy, -1)

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt
        local progress = math.min(1, enemy._lerp_timer / common.BOTTOM_ENTER_DURATION)
        local eased = common.smoothstep(progress)

        enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
        enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
        enemy.alpha = progress

        if progress >= 1 then
            enemy.alpha = 1
            common.restore_tangible(enemy)
            enemy.gravity = 1.5
            enemy:set_state(phase.states.scatter_throw)
        end
    end,
    draw = common.draw_with_alpha,
}

phase.states.scatter_throw = {
    name = "scatter_throw",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.animation.ms_per_frame = enemy.animations.ATTACK.ms_per_frame / SCATTER_THROW_SPEED_MULTIPLIER
        enemy.vx = 0
        enemy._scatter_count = 0
        enemy._axe_spawned_this_anim = false
        enemy._is_bottom_attacker = true
        common.set_direction(enemy, -1)
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
            enemy._axe_spawned_this_anim = true

            local base_angle = SCATTER_THROW_START_ANGLE - (enemy._scatter_count * SCATTER_THROW_STEP)
            common.spawn_directional_axe(enemy, base_angle)
            common.spawn_directional_axe(enemy, base_angle - SCATTER_THROW_PAIR_SPREAD)

            enemy._scatter_count = enemy._scatter_count + 1
            audio.play_axe_throw_sound()
        end

        if enemy.animation:is_finished() then
            if coordinator.transitioning_to_phase then
                enemy:set_state(phase.states.leave_bottom)
                return
            end

            common.is_player_on_ground(enemy.target_player)
            if coordinator.player_on_ground then
                enemy:set_state(phase.states.leave_bottom)
                return
            end

            if enemy._scatter_count < SCATTER_THROW_COUNT then
                enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                enemy.animation.ms_per_frame = enemy.animations.ATTACK.ms_per_frame / SCATTER_THROW_SPEED_MULTIPLIER
                enemy._axe_spawned_this_anim = false
            else
                enemy:set_state(phase.states.post_scatter_idle)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.post_scatter_idle = {
    name = "post_scatter_idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
        enemy._idle_timer = 0
        enemy._is_bottom_attacker = true
        common.set_direction(enemy, -1)
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        if coordinator.transitioning_to_phase then
            enemy:set_state(phase.states.leave_bottom)
            return
        end

        common.is_player_on_ground(enemy.target_player)
        if coordinator.player_on_ground then
            enemy:set_state(phase.states.leave_bottom)
            return
        end

        enemy._idle_timer = enemy._idle_timer + dt
        if enemy._idle_timer >= POST_SCATTER_IDLE_DURATION then
            enemy:set_state(phase.states.attack_player)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.attack_player = {
    name = "attack_player",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.vx = 0
        enemy._axe_spawned = false
        enemy._is_bottom_attacker = common.is_at_bottom(enemy)

        if enemy.target_player then
            common.set_direction(enemy, enemy_common.direction_to_player(enemy))
        end
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        if not enemy._axe_spawned and enemy.animation.frame >= 5 then
            enemy._axe_spawned = true

            local player = enemy.target_player
            if player then
                local target_x = player.x + player.box.x + player.box.w / 2
                local target_y = player.y + player.box.y + player.box.h / 2
                common.spawn_axe_at_player(enemy, target_x, target_y)
            else
                common.spawn_directional_axe(enemy, enemy.direction > 0 and 0 or 180)
            end

            audio.play_axe_throw_sound()
        end

        if enemy.animation:is_finished() then
            if coordinator.transitioning_to_phase then
                if enemy._is_bottom_attacker then
                    enemy:set_state(phase.states.leave_bottom)
                else
                    enemy:set_state(phase.states.jump_exit)
                end
                return
            end

            common.is_player_on_ground(enemy.target_player)
            if coordinator.player_on_ground and enemy._is_bottom_attacker then
                enemy:set_state(phase.states.leave_bottom)
                return
            end

            if enemy._is_bottom_attacker then
                enemy:set_state(phase.states.scatter_throw)
            else
                enemy:set_state(phase.states.idle)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
        enemy.idle_timer = 0
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        if enemy.target_player then
            common.set_direction(enemy, enemy_common.direction_to_player(enemy))
        end

        if not coordinator.is_active() then
            return
        end

        if coordinator.transitioning_to_phase then
            enemy:set_state(phase.states.jump_exit)
            return
        end

        common.is_player_on_ground(enemy.target_player)

        local on_outer_platform = enemy._platform_index == 1 or enemy._platform_index == 4
        if coordinator.player_on_ground and on_outer_platform then
            enemy:set_state(phase.states.jump_exit)
            return
        end

        enemy.idle_timer = (enemy.idle_timer or 0) + dt
        if enemy.idle_timer >= common.IDLE_DURATION then
            enemy:set_state(phase.states.rapid_attack)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.rapid_attack = common.create_rapid_attack_state(
    function() return phase.states.jump_exit end
)

-- Phase 3 leave_bottom goes to bottom_wait (for instant re-entry)
phase.states.leave_bottom = {
    name = "leave_bottom",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.RUN)
        common.set_direction(enemy, 1)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        enemy._lerp_start_x = enemy.x
        enemy._lerp_start_y = enemy.y
        enemy._lerp_end_x = enemy.x + common.BOTTOM_OFFSET_X
        enemy._lerp_end_y = enemy.y
        enemy._lerp_timer = 0
        enemy.alpha = 1

        coordinator.release_bottom_position()
        common.make_intangible(enemy)
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt
        local progress = math.min(1, enemy._lerp_timer / common.LEAVE_BOTTOM_DURATION)
        local eased = common.smoothstep(progress)

        enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
        enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
        enemy.alpha = 1 - progress

        if progress >= 1 then
            enemy.alpha = 0
            enemy._is_bottom_attacker = false
            enemy:set_state(phase.states.bottom_wait)
        end
    end,
    draw = common.draw_with_alpha,
}

phase.states.bottom_wait = {
    name = "bottom_wait",
    start = function(enemy)
        enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
        enemy.invulnerable = false
        enemy._is_bottom_attacker = false

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end

        if coordinator.transitioning_to_phase then
            coordinator.report_transition_ready(enemy)
        end
    end,
    update = function(enemy, _dt)
        if coordinator.transitioning_to_phase then
            return
        end

        common.is_player_on_ground(enemy.target_player)

        if not coordinator.player_on_ground and coordinator.is_bottom_available() then
            enemy:set_state(phase.states.bottom_enter_attack)
        end
    end,
    draw = common.noop,
}

phase.states.jump_exit = common.create_jump_exit_state(
    function() return phase.states.wait_state end
)

phase.states.wait_state = common.create_wait_state(
    function() return phase.states.decide_role end
)

phase.states.hit = common.create_positional_hit_state(
    function() return phase.states.jump_exit end,
    function() return phase.states.leave_bottom end
)

phase.states.death = common.create_death_state()

return phase
