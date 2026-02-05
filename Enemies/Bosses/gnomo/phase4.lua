--- Gnomo Boss Phase 4: Last stand (1 gnomo alive)
--- Attacks from platform when player on ground, from bottom when player airborne.
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local common = require("Enemies/Bosses/gnomo/common")
local audio = require("audio")

local phase = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PHASE4_START_DELAY = 1.5
local ATTACK_SPEED_MULTIPLIER = 1.5
local PLATFORM_IDLE_DURATION = 1.5
local BOTTOM_WAIT_MIN = 0.5
local BOTTOM_WAIT_MAX = 1.0
local PLATFORM_WAIT_DURATION = 1.0

-- Phase 4 only uses outer platforms (1 and 2)
local PHASE4_PLATFORM_INDICES = { 1, 2 }

-- Reusable table for get_phase4_platforms (avoids per-call allocation)
local phase4_available_platforms = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Get available outer platforms (1 and 2 only) for phase 4.
--- Note: Returns a reusable table - do not cache the result.
---@return table Array of available platform indices (subset of 1, 2)
local function get_phase4_platforms()
    local count = 0
    for i = 1, #PHASE4_PLATFORM_INDICES do
        local idx = PHASE4_PLATFORM_INDICES[i]
        if not coordinator.occupied_platforms[idx] then
            count = count + 1
            phase4_available_platforms[count] = idx
        end
    end
    -- Clear stale entries
    for i = count + 1, #phase4_available_platforms do
        phase4_available_platforms[i] = nil
    end
    return phase4_available_platforms
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

phase.states = {}

phase.states.initial_wait = common.create_initial_wait_state(
    PHASE4_START_DELAY, PHASE4_START_DELAY,
    function() return phase.states.decide_role end
)

phase.states.decide_role = common.create_decide_role_state(
    function() return phase.states.bottom_enter end,
    function() return phase.states.appear_state end,
    function() return phase.states.appear_state end,  -- Always go to platform in phase 4
    nil  -- No platform limit in phase 4
)

-- Custom appear state for phase 4 (only platforms 1 and 2)
phase.states.appear_state = {
    name = "appear_state",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.JUMP)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        local available = get_phase4_platforms()
        if #available == 0 then
            -- Fallback: wait and try again
            enemy:set_state(phase.states.wait_state)
            return
        end

        -- Pick furthest platform from player
        local platform_index = common.find_furthest_platform_from_player(enemy.target_player, available)

        coordinator.claim_platform(platform_index, enemy.color)
        enemy._platform_index = platform_index
        enemy._platform_attack_count = 0

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
            local progress = math.min(1, enemy._lerp_timer / common.FALL_DURATION)
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

            if enemy._lerp_timer >= common.LANDING_DELAY then
                common.restore_tangible(enemy)
                enemy.gravity = 1.5
                enemy:set_state(phase.states.attack_player)
            end
        end
    end,
    draw = common.draw_with_alpha,
}

-- Attack player with axe aimed at their position
phase.states.attack_player = {
    name = "attack_player",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.vx = 0
        enemy._axe_spawned = false

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

            enemy._platform_attack_count = (enemy._platform_attack_count or 0) + 1
            audio.play_axe_throw_sound()
        end

        if enemy.animation:is_finished() then
            -- First attack: go to idle, then attack again
            -- Second attack: exit platform
            if enemy._platform_attack_count >= 2 then
                enemy:set_state(phase.states.jump_exit)
            else
                enemy:set_state(phase.states.platform_idle)
            end
        end
    end,
    draw = enemy_common.draw,
}

-- Idle on platform between attacks
phase.states.platform_idle = {
    name = "platform_idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx = 0
        enemy._idle_timer = 0
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        if enemy.target_player then
            common.set_direction(enemy, enemy_common.direction_to_player(enemy))
        end

        enemy._idle_timer = enemy._idle_timer + dt
        if enemy._idle_timer >= PLATFORM_IDLE_DURATION then
            enemy:set_state(phase.states.attack_player)
        end
    end,
    draw = enemy_common.draw,
}

phase.states.jump_exit = common.create_jump_exit_state(
    function() return phase.states.wait_state end
)

-- Fixed duration wait after platform attack cycle
phase.states.wait_state = {
    name = "wait_state",
    start = function(enemy)
        enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
        enemy.invulnerable = false
        enemy._wait_duration = PLATFORM_WAIT_DURATION
        enemy._wait_timer = 0

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end
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

-- Enter from bottom right position
phase.states.bottom_enter = {
    name = "bottom_enter",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.IDLE)
        enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

        coordinator.claim_bottom_position(enemy.color)
        enemy._is_bottom_attacker = true

        local hx, hy = common.get_marker_position("gnomo_boss_exit_bottom_right")
        if hx and hy then
            enemy._lerp_start_x = hx + common.BOTTOM_OFFSET_X
            enemy._lerp_start_y = hy
            enemy._lerp_end_x = hx
            enemy._lerp_end_y = hy
        else
            enemy._lerp_start_x = enemy.x + common.BOTTOM_OFFSET_X
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = enemy.x
            enemy._lerp_end_y = enemy.y
        end

        enemy.x = enemy._lerp_start_x
        enemy.y = enemy._lerp_start_y
        enemy._lerp_timer = 0
        enemy.alpha = 0
        common.set_direction(enemy, -1)

        if not enemy._intangible_shape then
            common.make_intangible(enemy)
        end
    end,
    update = function(enemy, dt)
        enemy._lerp_timer = enemy._lerp_timer + dt
        local progress = math.min(1, enemy._lerp_timer / common.BOTTOM_ENTER_DURATION)
        local eased = common.smoothstep(progress)

        enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
        enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
        enemy.alpha = progress

        if progress >= 1 then
            enemy.alpha = 1
            common.restore_tangible(enemy)
            enemy.gravity = 1.5
            enemy:set_state(phase.states.attack_player_repeatedly)
        end
    end,
    draw = common.draw_with_alpha,
}

-- Continuous rapid axe throwing at 1.5x speed until player lands
phase.states.attack_player_repeatedly = {
    name = "attack_player_repeatedly",
    start = function(enemy)
        enemy_common.set_animation(enemy, enemy.animations.ATTACK)
        enemy.animation.ms_per_frame = enemy.animations.ATTACK.ms_per_frame / ATTACK_SPEED_MULTIPLIER
        enemy.vx = 0
        enemy._axe_spawned_this_anim = false
        enemy._is_bottom_attacker = true
        common.set_direction(enemy, -1)
    end,
    update = function(enemy, dt)
        enemy_common.apply_gravity(enemy, dt)

        -- Check player ground status EVERY FRAME and exit immediately if landed
        common.is_player_on_ground(enemy.target_player)
        if coordinator.player_on_ground then
            enemy:set_state(phase.states.leave_bottom)
            return
        end

        -- Spawn axe at frame 5
        if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
            enemy._axe_spawned_this_anim = true

            local player = enemy.target_player
            if player then
                local target_x = player.x + player.box.x + player.box.w / 2
                local target_y = player.y + player.box.y + player.box.h / 2
                common.spawn_axe_at_player(enemy, target_x, target_y)
            else
                common.spawn_directional_axe(enemy, 180)
            end

            audio.play_axe_throw_sound()
        end

        -- Loop animation for continuous throwing
        if enemy.animation:is_finished() then
            enemy_common.set_animation(enemy, enemy.animations.ATTACK)
            enemy.animation.ms_per_frame = enemy.animations.ATTACK.ms_per_frame / ATTACK_SPEED_MULTIPLIER
            enemy._axe_spawned_this_anim = false
        end
    end,
    draw = enemy_common.draw,
}

phase.states.leave_bottom = common.create_leave_bottom_state(
    function() return phase.states.bottom_wait end,
    { clear_bottom_attacker = true }
)

phase.states.bottom_wait = common.create_bottom_wait_state(
    function() return phase.states.decide_role end,
    { wait_min = BOTTOM_WAIT_MIN, wait_max = BOTTOM_WAIT_MAX }
)

phase.states.hit = common.create_positional_hit_state(
    function() return phase.states.jump_exit end,
    function() return phase.states.leave_bottom end
)

phase.states.death = common.create_death_state()

return phase
