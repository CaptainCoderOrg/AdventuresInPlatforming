--- Gnomo Boss Phase 0: Intro phase after cinematic.
--- All gnomos jump up to holes and disappear, then phase 1 begins.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")

local phase = {}

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

phase.states = {}

--- Idle state - transitions to attack when coordinator is active.
phase.states.idle = {
    name = "idle",
    start = function(enemy, _)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        -- Face player
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end

        -- When coordinator becomes active (cinematic ended), start attack
        if coordinator.is_active() then
            enemy:set_state(phase.states.attack)
        end
    end,
    draw = enemy_common.draw,
}

--- Attack state - throw 6 axes in arc pattern, then jump to exit.
phase.states.attack = common.create_attack_state(function()
    return phase.states.jump_exit
end)

--- Jump up to nearest hole and fade out.
phase.states.jump_exit = common.create_jump_exit_state(function()
    return phase.states.wait_complete
end)

--- Wait for all gnomos to finish phase 0, then coordinator transitions to phase 1.
phase.states.wait_complete = {
    name = "wait_complete",
    start = function(enemy, _)
        enemy.vx = 0
        enemy.vy = 0
        enemy.gravity = 0
        enemy.alpha = 0

        -- Report that this gnomo finished phase 0
        coordinator.report_phase0_complete(enemy)
    end,
    update = function(_, _) end,
    draw = function(_) end,  -- Invisible
}

--- Hit state - shouldn't happen in phase 0, but included for safety.
phase.states.hit = common.create_hit_state(function()
    return phase.states.idle
end)

--- Death state - shouldn't happen in phase 0, but included for safety.
phase.states.death = common.create_death_state()

return phase
