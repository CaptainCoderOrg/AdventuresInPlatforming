--- Gnomo Boss Phase 4: Last stand
--- All gnomos idle for now - behavior will be added incrementally.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")

local phase = {}

phase.states = {}

phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)
        if enemy.target_player then
            common.set_direction(enemy, enemy_common.direction_to_player(enemy))
        end
    end,
    draw = enemy_common.draw,
}

phase.states.hit = {
    name = "hit",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.HIT)
        enemy.vx = 0
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)
        if enemy.animation:is_finished() then
            enemy:set_state(phase.states.idle)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.death = common.create_death_state()

return phase
