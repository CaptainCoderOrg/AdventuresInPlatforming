--- Valkyrie Boss Phase 3: 50%-25% health.
--- Introduces arena hazards. TODO: Implement attack behavior.
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

local phase = {}
phase.states = {}

phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, _dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end
    end,
    draw = common.draw_sprite,
}

phase.states.hit = common.create_hit_state(function()
    return phase.states.idle
end)

phase.states.death = common.create_death_state()

return phase
