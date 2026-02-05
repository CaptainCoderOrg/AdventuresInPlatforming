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

local IDLE_DURATION = 2.0
local FALL_DURATION = 0.4
local WAIT_MIN = 1.0
local WAIT_MAX = 2.0
local HIT_WAIT_MIN = 2.5
local HIT_WAIT_MAX = 3.5
local INITIAL_WAIT_MIN = 0.5
local INITIAL_WAIT_MAX = 2.0

local BOTTOM_ENTER_DURATION = 0.4
local BOTTOM_ATTACK_INTERVAL = 1.0
local LEAVE_BOTTOM_DURATION = 0.3
local BOTTOM_OFFSET_X = 1

local RAPID_AXES_PER_ATTACK = 10
local RAPID_PAIR_STEP = 18
local RAPID_PAIR_SPREAD = 36

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function noop() end

--- Set enemy direction and sync animation flip state.
---@param enemy table The gnomo enemy
---@param direction number Direction (-1 = left, 1 = right)
local function set_direction(enemy, direction)
    enemy.direction = direction
    if enemy.animation then
        enemy.animation.flipped = direction
    end
end

--- Check if this enemy is currently at the bottom position.
---@param enemy table The gnomo enemy
---@return boolean
local function is_at_bottom(enemy)
    return coordinator.bottom_gnomo == enemy.color
end

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
    draw = noop,
}

--- Count how many platforms are currently occupied.
---@return number Count of occupied platforms
local function count_occupied_platforms()
    local count = 0
    for i = 1, 4 do
        if coordinator.occupied_platforms[i] then
            count = count + 1
        end
    end
    return count
end

local MAX_PLATFORM_GNOMOS = 2

phase.states.decide_role = {
    name = "decide_role",
    start = function(enemy)
        common.is_player_on_ground(enemy.target_player)

        -- When player is off ground, always prefer bottom position
        local go_to_bottom = not coordinator.player_on_ground
            and coordinator.is_bottom_available()

        if go_to_bottom then
            enemy:set_state(phase.states.bottom_enter)
        elseif count_occupied_platforms() < MAX_PLATFORM_GNOMOS then
            enemy:set_state(phase.states.appear_state)
        else
            -- Too many gnomos on platforms, wait and try again
            enemy:set_state(phase.states.wait_state)
        end
    end,
    update = noop,
    draw = noop,
}

phase.states.appear_state = {
    name = "appear_state",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.JUMP)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        local available = coordinator.get_phase2_platforms()
        if #available == 0 then
            enemy:set_state(phase.states.wait_state)
            return
        end

        local platform_index
        if coordinator.player_on_ground then
            platform_index = available[math.random(#available)]
        else
            platform_index = common.find_furthest_platform_from_player(enemy.target_player, available)
        end

        coordinator.claim_platform(platform_index, enemy.color)
        enemy._platform_index = platform_index

        local platform_id = common.PLATFORM_IDS[platform_index]
        local px, py = common.get_marker_position(platform_id)
        enemy._lerp_end_x = px or enemy.x
        enemy._lerp_end_y = py or enemy.y

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
            local fade_progress = math.min(1, enemy._lerp_timer / common.FADE_DURATION)
            enemy.alpha = fade_progress
            common.set_jump_frame_range(enemy, common.FRAME_DOWNWARD_START, common.FRAME_DOWNWARD_END)

            if fade_progress >= 1 then
                enemy.alpha = 1
                enemy._appear_phase = "fall"
                enemy._lerp_timer = 0
            end
        elseif enemy._appear_phase == "fall" then
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
            common.set_jump_frame_range(enemy, common.FRAME_LANDING_START, common.FRAME_LANDING_END)

            if enemy._lerp_timer >= 0.15 then
                common.restore_tangible(enemy)
                enemy.gravity = 1.5
                enemy:set_state(phase.states.idle)
            end
        end
    end,
    draw = common.draw_with_alpha,
}

phase.states.bottom_enter = {
    name = "bottom_enter",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        coordinator.claim_bottom_position(enemy.color)

        local hx, hy = common.get_marker_position("gnomo_boss_exit_bottom_right")
        if hx and hy then
            enemy._lerp_start_x = hx + BOTTOM_OFFSET_X
            enemy._lerp_start_y = hy
            enemy._lerp_end_x = hx
            enemy._lerp_end_y = hy
        else
            enemy._lerp_start_x = enemy.x + BOTTOM_OFFSET_X
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = enemy.x
            enemy._lerp_end_y = enemy.y
        end

        enemy.x = enemy._lerp_start_x
        enemy.y = enemy._lerp_start_y
        enemy._lerp_timer = 0
        enemy.alpha = 0
        set_direction(enemy, -1)

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt
        local progress = math.min(1, enemy._lerp_timer / BOTTOM_ENTER_DURATION)
        local eased = common.smoothstep(progress)

        enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
        enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
        enemy.alpha = progress

        if progress >= 1 then
            enemy.alpha = 1
            common.restore_tangible(enemy)
            enemy.gravity = 1.5
            enemy:set_state(phase.states.bottom_idle)
        end
    end,
    draw = common.draw_with_alpha,
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
            set_direction(enemy, enemy_common.direction_to_player(enemy))
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
        if enemy.idle_timer >= IDLE_DURATION then
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
        set_direction(enemy, -1)
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

phase.states.rapid_attack = {
    name = "rapid_attack",
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

        if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
            enemy._axe_spawned_this_anim = true

            local pair_index = math.floor(enemy._axes_thrown / 2)
            local base_angle = enemy._attack_start_angle + (pair_index * RAPID_PAIR_STEP * enemy._attack_direction)

            common.spawn_directional_axe(enemy, base_angle)
            common.spawn_directional_axe(enemy, base_angle + RAPID_PAIR_SPREAD * enemy._attack_direction)

            enemy._axes_thrown = enemy._axes_thrown + 2
            audio.play_axe_throw_sound()
        end

        if enemy.animation:is_finished() then
            if coordinator.transitioning_to_phase then
                enemy:set_state(phase.states.jump_exit)
                return
            end

            if enemy._axes_thrown < RAPID_AXES_PER_ATTACK then
                enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                enemy._axe_spawned_this_anim = false
            else
                enemy:set_state(phase.states.jump_exit)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.attack_player = {
    name = "attack_player",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.vx = 0
        enemy._axe_spawned = false
        enemy._is_bottom_attacker = is_at_bottom(enemy)

        if enemy.target_player then
            set_direction(enemy, enemy_common.direction_to_player(enemy))
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

phase.states.jump_exit = common.create_jump_exit_state(function()
    return phase.states.wait_state
end)

phase.states.leave_bottom = {
    name = "leave_bottom",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.RUN)
        set_direction(enemy, 1)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        enemy._lerp_start_x = enemy.x
        enemy._lerp_start_y = enemy.y
        enemy._lerp_end_x = enemy.x + BOTTOM_OFFSET_X
        enemy._lerp_end_y = enemy.y
        enemy._lerp_timer = 0
        enemy.alpha = 1

        coordinator.release_bottom_position()
        common.make_intangible(enemy)
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt
        local progress = math.min(1, enemy._lerp_timer / LEAVE_BOTTOM_DURATION)
        local eased = common.smoothstep(progress)

        enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
        enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
        enemy.alpha = 1 - progress

        if progress >= 1 then
            enemy.alpha = 0
            enemy:set_state(phase.states.wait_state)
        end
    end,
    draw = common.draw_with_alpha,
}

phase.states.wait_state = {
    name = "wait_state",
    start = function(enemy)
        enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
        enemy.invulnerable = false

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

        if coordinator.transitioning_to_phase then
            coordinator.report_transition_ready(enemy)
        end
    end,
    update = function(enemy, dt)
        if coordinator.transitioning_to_phase then
            return
        end

        enemy._wait_timer = enemy._wait_timer + dt
        if enemy._wait_timer >= enemy._wait_duration then
            enemy:set_state(phase.states.decide_role)
        end
    end,
    draw = noop,
}

phase.states.hit = {
    name = "hit",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.HIT)
        enemy.vx = 0
        enemy._is_bottom_attacker = is_at_bottom(enemy)
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)
        if enemy.animation:is_finished() then
            enemy.invulnerable = true
            enemy._exited_from_hit = true
            if enemy._is_bottom_attacker then
                enemy:set_state(phase.states.leave_bottom)
            else
                enemy:set_state(phase.states.jump_exit)
            end
        end
    end,
    draw = enemy_common.draw,
}

phase.states.death = {
    name = "death",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.DEATH)
        enemy.vx = (enemy.hit_direction or -1) * 4
        enemy.vy, enemy.gravity = 0, 0

        if enemy._platform_index then
            coordinator.release_platform(enemy._platform_index)
            enemy._platform_index = nil
        end

        if is_at_bottom(enemy) then
            coordinator.release_bottom_position()
        end

        coordinator.report_death(enemy)
    end,
    update = function(enemy, dt)
        enemy.vx = enemy_common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.animation:is_finished() then
            enemy.marked_for_destruction = true
        end
    end,
    draw = enemy_common.draw,
}

return phase
