--- Valkyrie Boss Phase 1: Full health (100%-75%).
--- Jump-to-nearest zone → dash attack loop. Escapes on hit during prep.
local audio = require("audio")
local enemy_common = require("Enemies/common")
local common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local MAKE_CHOICE_DELAY = 0.8
local ESCAPE_WAIT_DURATION = 2.0

--- Zones the valkyrie can escape to (furthest from player).
local ESCAPE_ZONES = {
    { get = function(c) return c.get_bridge_zone("left") end },
    { get = function(c) return c.get_bridge_zone("right") end },
    { get = function(c) return c.get_zone("middle_platform") end },
    { get = function(c) return c.get_zone("left") end },
    { get = function(c) return c.get_zone("right") end },
}

local phase = {}
phase.states = {}

--- Idle: entry state, immediately transitions to make_choice.
phase.states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.vx = 0
    end,
    update = function(enemy, _dt)
        enemy:set_state(phase.states.make_choice)
    end,
    draw = common.draw_sprite,
}

--- MakeChoice: wait 0.8s facing player, then jump to nearest zone.
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

-- Shared jump chain: prejump -> jump -> landing
phase.states.prejump = common.states.prejump
phase.states.jump = common.states.jump

--- Landing: routes to prep_attack normally, or escape_wait after an escape jump.
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
            if enemy._escaping then
                enemy._escaping = false
                enemy:set_state(phase.states.escape_wait)
            else
                enemy:set_state(common.states.prep_attack)
            end
        end
    end,
    draw = common.draw_sprite,
}

-- Shared attack chain: prep_attack -> dash_attack -> recover -> make_choice
phase.states.prep_attack = common.states.prep_attack
phase.states.dash_attack = common.states.dash_attack
phase.states.recover = common.states.recover

--- JumpEscape: activates boss blocks, picks zone furthest from player, jumps there.
phase.states.jump_escape = {
    name = "jump_escape",
    start = function(enemy)
        enemy.invulnerable = true
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        coordinator.activate_blocks()

        local player = enemy.target_player
        if player then
            local player_cx = player.x + (player.box.x + player.box.w / 2)
            local player_cy = player.y + (player.box.y + player.box.h / 2)
            local best_zone = nil
            local best_dist = -1

            for i = 1, #ESCAPE_ZONES do
                local zone = ESCAPE_ZONES[i].get(coordinator)
                if zone and zone.width then
                    local zone_cx = zone.x + zone.width / 2
                    local zone_cy = zone.y + (zone.height or 0) / 2
                    local dx = player_cx - zone_cx
                    local dy = player_cy - zone_cy
                    local dist = dx * dx + dy * dy
                    if dist > best_dist then
                        best_dist = dist
                        best_zone = zone
                    end
                end
            end

            if best_zone then
                local box = enemy.box
                local target_bottom = best_zone.y + (best_zone.height or 0)
                enemy._jump_target_x = best_zone.x
                enemy._jump_target_y = target_bottom - (box.y + box.h)
            end
        end

        enemy._escaping = true
    end,
    update = function(enemy, _dt)
        enemy:set_state(common.states.prejump)
    end,
    draw = common.draw_sprite,
}

--- EscapeWait: idle at escape position for 2s, then resume attack pattern.
phase.states.escape_wait = {
    name = "escape_wait",
    start = function(enemy)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        enemy.animation.flipped = enemy.direction
        enemy._escape_wait_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end

        enemy._escape_wait_timer = enemy._escape_wait_timer + dt
        if enemy._escape_wait_timer >= ESCAPE_WAIT_DURATION then
            enemy:set_state(phase.states.make_choice)
        end
    end,
    draw = common.draw_sprite,
}

--- Hit: after hit animation, always escape jump away.
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
            enemy:set_state(phase.states.jump_escape)
        end
    end,
    draw = common.draw_sprite,
}

phase.states.death = common.create_death_state()

return phase
