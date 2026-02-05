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

phase.states.initial_wait = common.create_initial_wait_state(
    PHASE3_START_DELAY, PHASE3_START_DELAY,
    function() return phase.states.decide_role end
)

phase.states.decide_role = common.create_decide_role_state(
    function() return phase.states.bottom_enter_attack end,
    function() return phase.states.appear_state end,
    function() return phase.states.wait_state end,
    MAX_PLATFORM_GNOMOS
)

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

phase.states.attack_player = common.create_attack_player_state(function(enemy)
    if coordinator.transitioning_to_phase then
        if enemy._is_bottom_attacker then
            return phase.states.leave_bottom
        end
        return phase.states.jump_exit
    end

    common.is_player_on_ground(enemy.target_player)
    if coordinator.player_on_ground and enemy._is_bottom_attacker then
        return phase.states.leave_bottom
    end

    if enemy._is_bottom_attacker then
        return phase.states.scatter_throw
    end
    return phase.states.idle
end)

phase.states.idle = common.create_platform_idle_state(
    common.IDLE_DURATION,
    function() return phase.states.rapid_attack end,
    { check_outer_platform = true, exit_state = function() return phase.states.jump_exit end }
)

phase.states.rapid_attack = common.create_rapid_attack_state(
    function() return phase.states.jump_exit end
)

phase.states.leave_bottom = common.create_leave_bottom_state(
    function() return phase.states.bottom_wait end,
    { clear_bottom_attacker = true }
)

phase.states.bottom_wait = common.create_bottom_wait_state(
    function() return phase.states.bottom_enter_attack end,
    { check_bottom_available = true }
)

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
