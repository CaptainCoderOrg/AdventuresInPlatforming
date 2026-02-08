--- Valkyrie Boss Phase 0: Intro phase.
--- After cinematic title/subtitle, valkyrie jumps to right pillar 4, then transitions to phase 1.
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local phase = {}
phase.states = {}

--- Idle: faces player during title/subtitle display, then sets jump target and enters prejump.
phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy._phase0_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end

        -- Brief pause before jumping (lets title/subtitle show)
        enemy._phase0_timer = enemy._phase0_timer + dt
        if enemy._phase0_timer >= 1.0 then
            common.set_jump_target_pillar(enemy, 4)
            enemy:set_state(common.states.prejump)
        end
    end,
    draw = common.draw_sprite,
}

-- Shared jump chain: prejump -> jump -> landing -> make_choice
phase.states.prejump = common.states.prejump
phase.states.jump = common.states.jump
phase.states.landing = common.states.landing

--- MakeChoice: after landing, transition to phase 1.
phase.states.make_choice = {
    name = "make_choice",
    start = function(enemy)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end
    end,
    update = function(_enemy, _dt)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        coordinator.start_phase1()
    end,
    draw = common.draw_sprite,
}

phase.states.hit = common.create_hit_state(function()
    return phase.states.idle
end)

phase.states.death = common.create_death_state()

return phase
