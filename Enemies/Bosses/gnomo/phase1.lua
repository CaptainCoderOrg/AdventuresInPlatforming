--- Gnomo Boss Phase 1: Full squad (4 alive)
--- Idle-attack-exit-reappear cycle. Gnomos attack, exit via holes or floor,
--- wait invisibly, then reappear from a new hole.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")
local audio = require("audio")

local phase = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Timing constants
local IDLE_DURATION = 2.0        -- Seconds before attacking
local FALL_DURATION = 0.4        -- Lerp time hole to platform
local WAIT_MIN = 1.0             -- Min wait before reappearing
local WAIT_MAX = 1.5             -- Max wait before reappearing
local HIT_WAIT_MIN = 2.5         -- Min wait after taking damage
local HIT_WAIT_MAX = 3.5         -- Max wait after taking damage
local FLOOR_EXIT_SPEED = 5       -- Tiles/sec run speed
local FLOOR_EXIT_TRANSITION_SPEED = 7.5  -- 1.5x boost during phase transition
local FLOOR_EXIT_LERP_DIST = 1   -- Tiles to lerp past hole while fading
local INITIAL_WAIT_MIN = 1.0     -- Min delay at phase 1 start
local INITIAL_WAIT_MAX = 3.0     -- Max delay at phase 1 start

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

phase.states = {}

--- Initial wait state - random delay before appearing at phase 1 start.
phase.states.initial_wait = {
    name = "initial_wait",
    start = function(enemy)
        enemy.vx = 0
        enemy.vy = 0
        enemy.gravity = 0
        enemy.alpha = 0

        enemy._wait_duration = INITIAL_WAIT_MIN + math.random() * (INITIAL_WAIT_MAX - INITIAL_WAIT_MIN)
        enemy._wait_timer = 0

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end
    end,
    update = function(enemy, dt)
        enemy._wait_timer = enemy._wait_timer + dt

        if enemy._wait_timer >= enemy._wait_duration then
            enemy:set_state(phase.states.appear_state)
        end
    end,
    draw = function(_) end,  -- Invisible
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
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end

        -- Skip idle timer while cinematic is playing
        if not coordinator.is_active() then
            return
        end

        if coordinator.transitioning_to_phase then
            enemy:set_state(phase.states.jump_exit)
            return
        end

        enemy.idle_timer = (enemy.idle_timer or 0) + dt
        if enemy.idle_timer >= IDLE_DURATION then
            enemy:set_state(phase.states.attack)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.attack = {
    name = "attack",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.vx = 0
        enemy._axes_thrown = 0
        enemy._axe_spawned_this_anim = false

        local pattern = common.PLATFORM_ATTACK_PATTERNS[enemy._platform_index] or common.PLATFORM_ATTACK_PATTERNS[1]
        enemy._attack_start_angle = pattern.start
        enemy._attack_direction = pattern.direction
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        -- Frame 5 is the release point in the throw animation
        if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
            enemy._axe_spawned_this_anim = true

            local angle = enemy._attack_start_angle + (enemy._axes_thrown * common.ARC_STEP * enemy._attack_direction)
            common.spawn_directional_axe(enemy, angle)

            enemy._axes_thrown = enemy._axes_thrown + 1
            audio.play_axe_throw_sound()
        end

        if enemy.animation:is_finished() then
            if coordinator.transitioning_to_phase then
                enemy:set_state(phase.states.jump_exit)
                return
            end

            if enemy._axes_thrown < common.AXES_PER_ATTACK then
                enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                enemy._axe_spawned_this_anim = false
            else
                enemy:set_state(phase.states.choose_exit)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.choose_exit = {
    name = "choose_exit",
    start = function(enemy)
        if math.random() < 0.5 then
            enemy:set_state(phase.states.jump_exit)
        else
            enemy:set_state(phase.states.floor_exit)
        end
    end,
    update = function(_, _) end,
    draw = function(_) end,  -- Instant transition, never renders
}

phase.states.jump_exit = common.create_jump_exit_state(function()
    return phase.states.wait_state
end)

phase.states.floor_exit = {
    name = "floor_exit",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.RUN)
        enemy.direction = 1  -- Always run right to exit
        if enemy.animation then
            enemy.animation.flipped = enemy.direction
        end
        -- Use faster speed during phase transition
        local speed = coordinator.transitioning_to_phase and FLOOR_EXIT_TRANSITION_SPEED or FLOOR_EXIT_SPEED
        enemy.vx = speed
        enemy.alpha = 1
        enemy._floor_exit_phase = "running"

        -- Get bottom right hole position
        local hx, hy = common.get_marker_position("gnomo_boss_exit_bottom_right")
        enemy._floor_exit_target_x = hx
        enemy._floor_exit_target_y = hy

        -- Release current platform
        if enemy._platform_index then
            coordinator.release_platform(enemy._platform_index)
            enemy._platform_index = nil
        end
    end,
    update = function(enemy, dt)
        if enemy._floor_exit_phase == "running" then
            enemy_common.apply_gravity(enemy, dt)
            -- Use faster speed during phase transition
            enemy.vx = coordinator.transitioning_to_phase and FLOOR_EXIT_TRANSITION_SPEED or FLOOR_EXIT_SPEED

            -- Check if reached the hole X position
            local target_x = enemy._floor_exit_target_x
            if target_x and enemy.x >= target_x then
                -- Reached hole - start lerp/fade phase
                enemy._floor_exit_phase = "fading"
                enemy._lerp_start_x = enemy.x
                enemy._lerp_start_y = enemy.y
                enemy._lerp_end_x = target_x + FLOOR_EXIT_LERP_DIST
                enemy._lerp_end_y = enemy._floor_exit_target_y or enemy.y
                enemy._lerp_timer = 0
                enemy.vx = 0
                enemy.vy = 0
                enemy.gravity = 0
                common.make_intangible(enemy)
            end
        elseif enemy._floor_exit_phase == "fading" then
            enemy._lerp_timer = enemy._lerp_timer + dt
            local progress = math.min(1, enemy._lerp_timer / common.FADE_DURATION)
            local eased = common.smoothstep(progress)

            -- Lerp past hole position (through wall)
            enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
            enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)

            -- Fade out
            enemy.alpha = 1 - progress

            if progress >= 1 then
                enemy.alpha = 0
                enemy:set_state(phase.states.wait_state)
            end
        end
    end,
    draw = common.draw_with_alpha,
}

phase.states.wait_state = {
    name = "wait_state",
    start = function(enemy)
        enemy.vx = 0
        enemy.vy = 0
        enemy.gravity = 0
        enemy.alpha = 0
        enemy.invulnerable = false  -- Reset so they can take damage when reappearing

        -- Longer wait duration if exited after being hit
        local wait_min, wait_max
        if enemy._exited_from_hit then
            wait_min, wait_max = HIT_WAIT_MIN, HIT_WAIT_MAX
            enemy._exited_from_hit = false
        else
            wait_min, wait_max = WAIT_MIN, WAIT_MAX
        end
        enemy._wait_duration = wait_min + math.random() * (wait_max - wait_min)
        enemy._wait_timer = 0

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end

        -- Report ready during phase transition
        if coordinator.transitioning_to_phase then
            coordinator.report_transition_ready(enemy)
        end
    end,
    update = function(enemy, dt)
        -- During transition, stay in wait_state until phase switch completes
        if coordinator.transitioning_to_phase then
            return
        end

        enemy._wait_timer = enemy._wait_timer + dt

        if enemy._wait_timer >= enemy._wait_duration then
            enemy:set_state(phase.states.appear_state)
        end
    end,
    draw = function(_) end,  -- Invisible, don't draw
}

phase.states.appear_state = {
    name = "appear_state",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.JUMP)
        enemy.vx = 0
        enemy.vy = 0
        enemy.gravity = 0

        -- Select unoccupied platform
        local available = coordinator.get_unoccupied_platforms()
        local platform_index
        if #available > 0 then
            platform_index = available[math.random(#available)]
        else
            -- Fallback: pick random platform
            platform_index = math.random(1, #common.PLATFORM_IDS)
        end

        -- Claim the platform
        coordinator.claim_platform(platform_index, enemy.color)
        enemy._platform_index = platform_index

        -- Get platform position (destination)
        local platform_id = common.PLATFORM_IDS[platform_index]
        local px, py = common.get_marker_position(platform_id)
        enemy._lerp_end_x = px or enemy.x
        enemy._lerp_end_y = py or enemy.y

        -- Get hole position (start)
        local holes = common.PLATFORM_TO_HOLES[platform_index]
        local hole_index = holes[math.random(#holes)]
        local hole_id = common.HOLE_IDS[hole_index]
        local hx, hy = common.get_marker_position(hole_id)
        enemy._lerp_start_x = hx or enemy._lerp_end_x
        enemy._lerp_start_y = hy or enemy._lerp_end_y

        enemy.x = enemy._lerp_start_x
        enemy.y = enemy._lerp_start_y

        enemy._lerp_timer = 0
        enemy.alpha = 0
        enemy._appear_phase = "fade_in"
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt

        if enemy._appear_phase == "fade_in" then
            -- Fade in at hole position
            local fade_progress = math.min(1, enemy._lerp_timer / common.FADE_DURATION)
            enemy.alpha = fade_progress

            -- Set downward animation frames
            common.set_jump_frame_range(enemy, common.FRAME_DOWNWARD_START, common.FRAME_DOWNWARD_END)

            if fade_progress >= 1 then
                enemy.alpha = 1
                enemy._appear_phase = "fall"
                enemy._lerp_timer = 0
            end
        elseif enemy._appear_phase == "fall" then
            -- Fall from hole to platform
            local progress = math.min(1, enemy._lerp_timer / FALL_DURATION)
            local eased = common.smoothstep(progress)

            enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
            enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)

            common.set_jump_frame_range(enemy, common.FRAME_DOWNWARD_START, common.FRAME_DOWNWARD_END)

            if progress >= 1 then
                enemy._appear_phase = "land"
                enemy._lerp_timer = 0
            end
        elseif enemy._appear_phase == "land" then
            -- Play landing frames briefly
            common.set_jump_frame_range(enemy, common.FRAME_LANDING_START, common.FRAME_LANDING_END)

            if enemy._lerp_timer >= common.LANDING_DELAY then
                common.restore_tangible(enemy)
                enemy.gravity = 1.5
                enemy:set_state(phase.states.idle)
            end
        end
    end,
    draw = common.draw_with_alpha,
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
            enemy.invulnerable = true
            enemy._exited_from_hit = true
            enemy:set_state(phase.states.choose_exit)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.death = common.create_death_state()

return phase
