--- Gnomo Boss Phase 2: Three remain
--- Dynamic behavior based on player ground position.
--- When player on ground: Gnomos use platforms 2-3, throw rapid arcs.
--- When player off ground: One gnomo uses bottom-right, others use all platforms, attack player directly.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")

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

phase.states.initial_wait = common.create_initial_wait_state(
    INITIAL_WAIT_MIN, INITIAL_WAIT_MAX,
    function() return phase.states.decide_role end
)

phase.states.decide_role = common.create_decide_role_state(
    function() return phase.states.bottom_enter end,
    function() return phase.states.appear_state end,
    function() return phase.states.wait_state end,
    MAX_PLATFORM_GNOMOS
)

phase.states.appear_state = common.create_appear_state(
    function() return phase.states.idle end,
    function() return phase.states.wait_state end,
    MAX_PLATFORM_GNOMOS
)

phase.states.bottom_enter = common.create_bottom_enter_state(
    function() return phase.states.bottom_idle end
)

phase.states.idle = common.create_platform_idle_state(
    common.IDLE_DURATION,
    function() return phase.states.rapid_attack end,
    { check_outer_platform = true, exit_state = function() return phase.states.jump_exit end }
)

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

phase.states.attack_player = common.create_attack_player_state(function(enemy)
    if coordinator.transitioning_to_phase then
        if enemy._is_bottom_attacker then
            return phase.states.leave_bottom
        end
        return phase.states.jump_exit
    end
    if enemy._is_bottom_attacker then
        return phase.states.bottom_idle
    end
    return phase.states.idle
end)

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
