--- Gnomo Boss Phase 2: Three remain
--- Dynamic behavior based on player ground position.
--- When player on ground: Gnomos use platforms 2-3, throw rapid arcs.
--- When player off ground: One gnomo uses bottom-right, others use all platforms, attack player directly.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")
local audio = require("audio")

local phase = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local INITIAL_WAIT_MIN = 0.5
local INITIAL_WAIT_MAX = 2.0
local BOTTOM_ATTACK_INTERVAL = 1.0
local MAX_PLATFORM_GNOMOS = 2

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

phase.states = {}

phase.states.initial_wait = {
    name = "initial_wait",
    start = function(enemy)
        enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
        enemy._wait_duration = INITIAL_WAIT_MIN + math.random() * (INITIAL_WAIT_MAX - INITIAL_WAIT_MIN)
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
            enemy:set_state(phase.states.bottom_enter)
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

phase.states.bottom_enter = common.create_bottom_enter_state(
    function() return phase.states.bottom_idle end
)

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

phase.states.bottom_idle = {
    name = "bottom_idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
        enemy._bottom_attack_timer = 0
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

        enemy._bottom_attack_timer = enemy._bottom_attack_timer + dt
        if enemy._bottom_attack_timer >= BOTTOM_ATTACK_INTERVAL then
            enemy:set_state(phase.states.attack_player)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.rapid_attack = common.create_rapid_attack_state(
    function() return phase.states.jump_exit end
)

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

            if enemy._is_bottom_attacker then
                enemy:set_state(phase.states.bottom_idle)
            else
                enemy:set_state(phase.states.idle)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.jump_exit = common.create_jump_exit_state(
    function() return phase.states.wait_state end
)

phase.states.leave_bottom = common.create_leave_bottom_state(
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
