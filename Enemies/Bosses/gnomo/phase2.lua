--- Gnomo Boss Phase 2: Three remain
--- All gnomos idle for now - behavior will be added incrementally.
local common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")

local phase = {}

phase.states = {}

phase.states.idle = {
    name = "idle",
    start = function(enemy, _)
        common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, dt)
        common.apply_gravity(enemy, dt)
        -- Face player
        if enemy.target_player then
            enemy.direction = common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end
    end,
    draw = common.draw,
}

phase.states.hit = {
    name = "hit",
    start = function(enemy, _)
        common.set_animation(enemy, enemy.animations.HIT)
        enemy.vx = 0
    end,
    update = function(enemy, dt)
        common.apply_gravity(enemy, dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.idle)
        end
    end,
    draw = common.draw,
}

phase.states.death = {
    name = "death",
    start = function(enemy, _)
        common.set_animation(enemy, enemy.animations.DEATH)
        enemy.vx = (enemy.hit_direction or -1) * 4
        enemy.vy = 0
        enemy.gravity = 0
        coordinator.report_death(enemy)
    end,
    update = function(enemy, dt)
        enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.animation:is_finished() then
            enemy.marked_for_destruction = true
        end
    end,
    draw = common.draw,
}

return phase
