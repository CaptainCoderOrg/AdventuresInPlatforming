--- Gnomo Boss Common: Shared utilities and states for gnomo boss phases.
--- Consolidates duplicated functions used across phase modules.
local canvas = require("canvas")
local combat = require("combat")
local enemy_common = require("Enemies/common")
local world = require("world")
local audio = require("audio")
local gnomo_axe = require("Enemies/gnomo_axe_thrower")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")

local common = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

common.IDLE_DURATION = 2.0
common.FALL_DURATION = 0.4
common.LANDING_DELAY = 0.15
common.WAIT_MIN = 1.0
common.WAIT_MAX = 2.0
common.HIT_WAIT_MIN = 2.5
common.HIT_WAIT_MAX = 3.5

common.BOTTOM_ENTER_DURATION = 0.4
common.LEAVE_BOTTOM_DURATION = 0.3
common.BOTTOM_OFFSET_X = 1

-- Rapid attack constants
common.RAPID_AXES_PER_ATTACK = 10
common.RAPID_PAIR_STEP = 18
common.RAPID_PAIR_SPREAD = 36

-- Spawn point IDs for holes (top exits)
common.HOLE_IDS = {
    "gnomo_boss_exit_top_left",
    "gnomo_boss_exit_top_0",
    "gnomo_boss_exit_top_1",
    "gnomo_boss_exit_top_2",
    "gnomo_boss_exit_top_3",
    "gnomo_boss_exit_top_right",
}

-- Spawn point IDs for platforms
common.PLATFORM_IDS = {
    "gnomo_boss_platform_0",
    "gnomo_boss_platform_1",
    "gnomo_boss_platform_2",
    "gnomo_boss_platform_3",
}

-- Jump animation frame ranges (row 2, 9 frames total)
common.FRAME_PREP_START = 0
common.FRAME_PREP_END = 2
common.FRAME_UPWARD_START = 3
common.FRAME_UPWARD_END = 4
common.FRAME_DOWNWARD_START = 5
common.FRAME_DOWNWARD_END = 6
common.FRAME_LANDING_START = 7
common.FRAME_LANDING_END = 8

common.JUMP_EXIT_DURATION = 0.5
common.FADE_DURATION = 0.2
common.FADE_START_THRESHOLD = 1 - (common.FADE_DURATION / common.JUMP_EXIT_DURATION)  -- 0.6

-- Attack pattern constants
-- Platform patterns: {start_angle, direction} where direction is 1 (CCW) or -1 (CW)
common.PLATFORM_ATTACK_PATTERNS = {
    [1] = { start = 45, direction = -1 },   -- platform_0: 45 deg clockwise
    [2] = { start = 180, direction = 1 },   -- platform_1: 180 deg counter-clockwise
    [3] = { start = 0, direction = -1 },    -- platform_2: 0 deg clockwise
    [4] = { start = 135, direction = 1 },   -- platform_3: 135 deg counter-clockwise
}
common.AXE_SPEED = 8           -- Tiles/sec
common.AXES_PER_ATTACK = 6
common.ARC_STEP = 36           -- Degrees between each axe (180 deg / 5 = 36)

-- Maps platform index to associated hole indices
common.PLATFORM_TO_HOLES = {
    [1] = { 1, 2 },  -- platform_0 -> top_left, top_0
    [2] = { 3 },     -- platform_1 -> top_1
    [3] = { 4 },     -- platform_2 -> top_2
    [4] = { 5, 6 },  -- platform_3 -> top_3, top_right
}

--------------------------------------------------------------------------------
-- Lazy-loaded modules
--------------------------------------------------------------------------------

local platforms = nil
local ground_level_spawn = nil

--- Lazily load platforms module.
---@return table platforms module
function common.get_platforms()
    if not platforms then
        platforms = require("platforms")
    end
    return platforms
end

--- Check if player is within gnomo_boss_ground_level rectangle.
--- Updates coordinator's player_on_ground status.
---@param player table Player instance
---@return boolean True if player center is within ground level bounds
function common.is_player_on_ground(player)
    if not player then
        coordinator.update_player_ground_status(true)
        return true
    end

    if not ground_level_spawn then
        ground_level_spawn = common.get_platforms().spawn_points["gnomo_boss_ground_level"]
    end

    if not ground_level_spawn or not ground_level_spawn.width then
        coordinator.update_player_ground_status(true)
        return true
    end

    local px = player.x + player.box.x + player.box.w / 2
    local py = player.y + player.box.y + player.box.h / 2

    local on_ground = px >= ground_level_spawn.x and px < ground_level_spawn.x + ground_level_spawn.width
        and py >= ground_level_spawn.y and py < ground_level_spawn.y + ground_level_spawn.height

    coordinator.update_player_ground_status(on_ground)
    return on_ground
end

--- Find platform furthest from player position.
---@param player table Player instance
---@param available table Array of available platform indices
---@return number Best platform index
function common.find_furthest_platform_from_player(player, available)
    if not player or #available == 0 then
        return available[1] or 1
    end

    local plat = common.get_platforms()
    local player_cx = player.x + player.box.x + player.box.w / 2
    local player_cy = player.y + player.box.y + player.box.h / 2

    local best_index = available[1]
    local best_dist_sq = -1

    for _, platform_index in ipairs(available) do
        local platform_id = common.PLATFORM_IDS[platform_index]
        local point = plat.spawn_points[platform_id]
        if point then
            local dx = point.x - player_cx
            local dy = point.y - player_cy
            local dist_sq = dx * dx + dy * dy
            if dist_sq > best_dist_sq then
                best_dist_sq = dist_sq
                best_index = platform_index
            end
        end
    end

    return best_index
end

--- Spawn axe with velocity toward a target position.
---@param enemy table Gnomo spawning the axe
---@param target_x number Target X position in tiles
---@param target_y number Target Y position in tiles
function common.spawn_axe_at_player(enemy, target_x, target_y)
    -- Offset to sprite center so axe appears from gnomo's hands
    local spawn_x = enemy.x + 0.5
    local spawn_y = enemy.y + 0.5

    local dx = target_x - spawn_x
    local dy = target_y - spawn_y
    local dist = math.sqrt(dx * dx + dy * dy)

    local vx, vy
    if dist > 0.01 then
        vx = (dx / dist) * common.AXE_SPEED
        vy = (dy / dist) * common.AXE_SPEED
    else
        -- Fallback: throw right
        vx = common.AXE_SPEED
        vy = 0
    end

    gnomo_axe.spawn_axe_with_velocity(spawn_x, spawn_y, vx, vy)
end

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

--- No-operation function for empty state callbacks.
function common.noop() end

--- Set enemy direction and sync animation flip state.
---@param enemy table The gnomo enemy
---@param direction number Direction (-1 = left, 1 = right)
function common.set_direction(enemy, direction)
    enemy.direction = direction
    if enemy.animation then
        enemy.animation.flipped = direction
    end
end

--- Check if this enemy is currently at the bottom position.
---@param enemy table The gnomo enemy
---@return boolean
function common.is_at_bottom(enemy)
    return coordinator.bottom_gnomo == enemy.color
end

--- Count how many platforms are currently occupied.
---@return number Count of occupied platforms
function common.count_occupied_platforms()
    local count = 0
    for i = 1, 4 do
        if coordinator.occupied_platforms[i] then
            count = count + 1
        end
    end
    return count
end

--- Get spawn point position by ID.
---@param id string Spawn point ID
---@return number|nil x X position in tiles
---@return number|nil y Y position in tiles
function common.get_marker_position(id)
    local plat = common.get_platforms()
    local point = plat.spawn_points[id]
    if point then
        return point.x, point.y
    end
    return nil, nil
end

--- Find the nearest hole to an enemy based on position.
---@param enemy table The gnomo enemy
---@return number hole_index Index into HOLE_IDS (1-6)
function common.find_nearest_hole(enemy)
    local best_index = 1
    local best_dist_sq = math.huge

    for i = 1, #common.HOLE_IDS do
        local hole_id = common.HOLE_IDS[i]
        local hx, hy = common.get_marker_position(hole_id)
        if hx and hy then
            local dx = hx - enemy.x
            local dy = hy - enemy.y
            local dist_sq = dx * dx + dy * dy
            if dist_sq < best_dist_sq then
                best_dist_sq = dist_sq
                best_index = i
            end
        end
    end

    return best_index
end

--- Find closest platform to a position.
---@param x number X position in tiles
---@param y number Y position in tiles
---@return number platform_index Index (1-4) of closest platform
function common.find_closest_platform(x, y)
    local plat = common.get_platforms()
    local best_index = 1
    local best_dist_sq = math.huge

    for i = 1, #common.PLATFORM_IDS do
        local platform_id = common.PLATFORM_IDS[i]
        local point = plat.spawn_points[platform_id]
        if point then
            local dx = point.x - x
            local dy = point.y - y
            local dist_sq = dx * dx + dy * dy
            if dist_sq < best_dist_sq then
                best_dist_sq = dist_sq
                best_index = i
            end
        end
    end

    return best_index
end

--- Make enemy intangible (removes from combat and collision detection).
---@param enemy table The gnomo enemy
function common.make_intangible(enemy)
    combat.remove(enemy)
    enemy._intangible_shape = enemy.shape
    enemy.shape = nil  -- Clear shape so check_player_overlap won't find it
    world.shape_map[enemy] = nil
end

--- Restore enemy tangibility (re-adds to combat and collision detection).
---@param enemy table The gnomo enemy
function common.restore_tangible(enemy)
    if enemy._intangible_shape then
        world.shape_map[enemy] = enemy._intangible_shape
        enemy.shape = enemy._intangible_shape
        enemy._intangible_shape = nil
        world.sync_position(enemy)
    end
    combat.add(enemy)
end

--- Smoothstep easing function for natural motion.
---@param t number Progress value (0-1)
---@return number Eased value (0-1)
function common.smoothstep(t)
    return t * t * (3 - 2 * t)
end

--- Linearly interpolate between two values.
---@param a number Start value
---@param b number End value
---@param t number Progress (0-1)
---@return number Interpolated value
function common.lerp(a, b, t)
    return a + (b - a) * t
end

--- Set jump animation to specific frame range.
--- Resets to start_frame if current frame is outside the range.
---@param enemy table The gnomo enemy
---@param start_frame number First frame of range
---@param end_frame number Last frame of range
function common.set_jump_frame_range(enemy, start_frame, end_frame)
    if not enemy.animation then return end
    if enemy.animation.frame < start_frame or enemy.animation.frame > end_frame then
        enemy.animation.frame = start_frame
    end
end

--- Draw enemy with alpha transparency.
---@param enemy table The gnomo enemy
function common.draw_with_alpha(enemy)
    local needs_alpha = enemy.alpha and enemy.alpha < 1
    if needs_alpha then
        canvas.set_global_alpha(enemy.alpha)
    end
    enemy_common.draw(enemy)
    if needs_alpha then
        canvas.set_global_alpha(1)
    end
end

--------------------------------------------------------------------------------
-- Shared States
--------------------------------------------------------------------------------

--- Spawn an axe with directional velocity based on angle.
---@param enemy table The gnomo enemy
---@param angle_deg number Angle in degrees (0 = right, 90 = up, 180 = left, 270 = down)
function common.spawn_directional_axe(enemy, angle_deg)
    local angle_rad = math.rad(angle_deg)
    local vx = math.cos(angle_rad) * common.AXE_SPEED
    local vy = -math.sin(angle_rad) * common.AXE_SPEED  -- Negative Y = up in screen coords

    -- Spawn position (center of gnomo)
    local spawn_x = enemy.x + 0.5
    local spawn_y = enemy.y + 0.5

    gnomo_axe.spawn_axe_with_velocity(spawn_x, spawn_y, vx, vy)
end

--- Create an attack state that throws 6 axes in an arc pattern.
---@param get_next_state function Returns the next state to transition to
---@return table Attack state definition
function common.create_attack_state(get_next_state)
    return {
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

            if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
                enemy._axe_spawned_this_anim = true

                local angle = enemy._attack_start_angle + (enemy._axes_thrown * common.ARC_STEP * enemy._attack_direction)
                common.spawn_directional_axe(enemy, angle)

                enemy._axes_thrown = enemy._axes_thrown + 1
                audio.play_axe_throw_sound()
            end

            if enemy.animation:is_finished() then
                if enemy._axes_thrown < common.AXES_PER_ATTACK then
                    enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                    enemy._axe_spawned_this_anim = false
                else
                    enemy:set_state(get_next_state())
                end
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create a jump exit state that lerps enemy to nearest hole and fades out.
---@param get_next_state function Returns the next state to transition to
---@return table Jump exit state definition
function common.create_jump_exit_state(get_next_state)
    return {
        name = "jump_exit",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.JUMP)
            enemy.vx = 0
            enemy.vy = 0
            enemy.gravity = 0

            local hole_index = common.find_nearest_hole(enemy)
            enemy._exit_hole_index = hole_index
            local hole_id = common.HOLE_IDS[hole_index]
            local hx, hy = common.get_marker_position(hole_id)

            enemy._lerp_start_x = enemy.x
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = hx or enemy.x
            enemy._lerp_end_y = hy or enemy.y
            enemy._lerp_timer = 0
            enemy.alpha = 1

            if enemy._platform_index then
                coordinator.release_platform(enemy._platform_index)
                enemy._platform_index = nil
            end

            common.make_intangible(enemy)
        end,
        update = function(enemy, dt)
            enemy._lerp_timer = enemy._lerp_timer + dt
            local progress = math.min(1, enemy._lerp_timer / common.JUMP_EXIT_DURATION)
            local eased = common.smoothstep(progress)

            enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
            enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)

            common.set_jump_frame_range(enemy, common.FRAME_UPWARD_START, common.FRAME_UPWARD_END)

            -- Start fade at 60% progress for smooth disappearance into hole
            if progress >= common.FADE_START_THRESHOLD then
                local fade_progress = (progress - common.FADE_START_THRESHOLD) / (1 - common.FADE_START_THRESHOLD)
                enemy.alpha = 1 - fade_progress
            end

            if progress >= 1 then
                enemy.alpha = 0
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.draw_with_alpha,
    }
end

--- Create a hit state with configurable next state.
---@param get_next_state function Returns the next state to transition to
---@return table Hit state definition
function common.create_hit_state(get_next_state)
    return {
        name = "hit",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.HIT)
            enemy.vx = 0
        end,
        update = function(enemy, dt)
            enemy_common.apply_gravity(enemy, dt)
            if enemy.animation:is_finished() then
                enemy:set_state(get_next_state())
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create a death state that releases platform and reports to coordinator.
---@return table Death state definition
function common.create_death_state()
    return {
        name = "death",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.DEATH)
            enemy.vx = (enemy.hit_direction or -1) * 4
            enemy.vy = 0
            enemy.gravity = 0

            -- Release platform on death
            if enemy._platform_index then
                coordinator.release_platform(enemy._platform_index)
                enemy._platform_index = nil
            end

            -- Release bottom position if held
            if common.is_at_bottom(enemy) then
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
end

--- Create an appear state that lerps enemy from hole to platform.
---@param get_next_state function Returns the next state after landing
---@param get_fallback_state function Returns the state when no platforms available
---@param max_platform_gnomos number Maximum number of gnomos allowed on platforms
---@return table Appear state definition
function common.create_appear_state(get_next_state, get_fallback_state, max_platform_gnomos)
    return {
        name = "appear_state",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.JUMP)
            enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

            local available = coordinator.get_phase2_platforms()
            if #available == 0 then
                enemy:set_state(get_fallback_state())
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
                    enemy:set_state(get_next_state())
                end
            end
        end,
        draw = common.draw_with_alpha,
    }
end

--- Create a rapid attack state that throws pairs of axes in an arc pattern.
---@param get_exit_state function Returns the state to transition to after attack
---@return table Rapid attack state definition
function common.create_rapid_attack_state(get_exit_state)
    return {
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
                local base_angle = enemy._attack_start_angle + (pair_index * common.RAPID_PAIR_STEP * enemy._attack_direction)

                common.spawn_directional_axe(enemy, base_angle)
                common.spawn_directional_axe(enemy, base_angle + common.RAPID_PAIR_SPREAD * enemy._attack_direction)

                enemy._axes_thrown = enemy._axes_thrown + 2
                audio.play_axe_throw_sound()
            end

            if enemy.animation:is_finished() then
                if coordinator.transitioning_to_phase then
                    enemy:set_state(get_exit_state())
                    return
                end

                if enemy._axes_thrown < common.RAPID_AXES_PER_ATTACK then
                    enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                    enemy._axe_spawned_this_anim = false
                else
                    enemy:set_state(get_exit_state())
                end
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create a wait state for invisible waiting between attacks.
---@param get_next_state function Returns the state to transition to after waiting
---@return table Wait state definition
function common.create_wait_state(get_next_state)
    return {
        name = "wait_state",
        start = function(enemy)
            enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
            enemy.invulnerable = false

            local wait_min, wait_max
            if enemy._exited_from_hit then
                wait_min, wait_max = common.HIT_WAIT_MIN, common.HIT_WAIT_MAX
                enemy._exited_from_hit = false
            else
                wait_min, wait_max = common.WAIT_MIN, common.WAIT_MAX
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
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.noop,
    }
end

--- Create a leave bottom state for exiting the bottom-right position.
---@param get_next_state function Returns the state to transition to after leaving
---@param options table|nil Optional settings: { clear_bottom_attacker = true }
---@return table Leave bottom state definition
function common.create_leave_bottom_state(get_next_state, options)
    options = options or {}
    return {
        name = "leave_bottom",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.RUN)
            common.set_direction(enemy, 1)
            enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

            enemy._lerp_start_x = enemy.x
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = enemy.x + common.BOTTOM_OFFSET_X
            enemy._lerp_end_y = enemy.y
            enemy._lerp_timer = 0
            enemy.alpha = 1

            coordinator.release_bottom_position()
            common.make_intangible(enemy)
        end,
        update = function(enemy, dt)
            enemy._lerp_timer = enemy._lerp_timer + dt
            local progress = math.min(1, enemy._lerp_timer / common.LEAVE_BOTTOM_DURATION)
            local eased = common.smoothstep(progress)

            enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
            enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)
            enemy.alpha = 1 - progress

            if progress >= 1 then
                enemy.alpha = 0
                if options.clear_bottom_attacker then
                    enemy._is_bottom_attacker = false
                end
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.draw_with_alpha,
    }
end

--- Create a bottom enter state for entering the bottom-right position.
---@param get_next_state function Returns the state to transition to after entering
---@return table Bottom enter state definition
function common.create_bottom_enter_state(get_next_state)
    return {
        name = "bottom_enter",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.IDLE)
            enemy.vx, enemy.vy, enemy.gravity = 0, 0, 0

            coordinator.claim_bottom_position(enemy.color)

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
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.draw_with_alpha,
    }
end

--- Create a hit state that exits to different states based on position.
---@param get_platform_exit_state function Returns state for platform gnomo after hit
---@param get_bottom_exit_state function Returns state for bottom gnomo after hit
---@return table Hit state definition
function common.create_positional_hit_state(get_platform_exit_state, get_bottom_exit_state)
    return {
        name = "hit",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.HIT)
            enemy.vx = 0
            enemy._is_bottom_attacker = common.is_at_bottom(enemy)
        end,
        update = function(enemy, dt)
            enemy_common.apply_gravity(enemy, dt)
            if enemy.animation:is_finished() then
                enemy.invulnerable = true
                enemy._exited_from_hit = true
                if enemy._is_bottom_attacker then
                    enemy:set_state(get_bottom_exit_state())
                else
                    enemy:set_state(get_platform_exit_state())
                end
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create an initial wait state with configurable timing.
---@param wait_min number Minimum wait duration
---@param wait_max number Maximum wait duration (use same as min for fixed duration)
---@param get_next_state function Returns the state to transition to after waiting
---@return table Initial wait state definition
function common.create_initial_wait_state(wait_min, wait_max, get_next_state)
    return {
        name = "initial_wait",
        start = function(enemy)
            enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
            enemy._wait_duration = wait_min + math.random() * (wait_max - wait_min)
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
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.noop,
    }
end

--- Create a decide_role state that chooses between bottom and platform positions.
---@param get_bottom_state function Returns state when going to bottom position
---@param get_platform_state function Returns state when going to platform
---@param get_fallback_state function Returns state when no position available
---@param max_platform_gnomos number Maximum gnomos allowed on platforms (nil = no limit check)
---@return table Decide role state definition
function common.create_decide_role_state(get_bottom_state, get_platform_state, get_fallback_state, max_platform_gnomos)
    return {
        name = "decide_role",
        start = function(enemy)
            common.is_player_on_ground(enemy.target_player)

            local go_to_bottom = not coordinator.player_on_ground
                and coordinator.is_bottom_available()

            if go_to_bottom then
                enemy:set_state(get_bottom_state())
            elseif not max_platform_gnomos or common.count_occupied_platforms() < max_platform_gnomos then
                enemy:set_state(get_platform_state())
            else
                enemy:set_state(get_fallback_state())
            end
        end,
        update = common.noop,
        draw = common.noop,
    }
end

--- Create an attack_player state that throws a single axe at the player.
---@param get_next_state function(enemy) Returns the next state based on enemy context
---@return table Attack player state definition
function common.create_attack_player_state(get_next_state)
    return {
        name = "attack_player",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.ATTACK)
            enemy.vx = 0
            enemy._axe_spawned = false
            enemy._is_bottom_attacker = common.is_at_bottom(enemy)

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

                audio.play_axe_throw_sound()
            end

            if enemy.animation:is_finished() then
                enemy:set_state(get_next_state(enemy))
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create a platform idle state that faces the player and transitions after a duration.
---@param idle_duration number Time to idle before transitioning
---@param get_next_state function Returns the state to transition to
---@param options table|nil Optional settings: { check_outer_platform = true, rapid_attack_next = state }
---@return table Platform idle state definition
function common.create_platform_idle_state(idle_duration, get_next_state, options)
    options = options or {}
    return {
        name = "idle",
        start = function(enemy)
            enemy_common.set_animation(enemy, enemy.animations.IDLE)
            enemy.vx = 0
            enemy.idle_timer = 0
        end,
        update = function(enemy, dt)
            enemy_common.apply_gravity(enemy, dt)

            if enemy.target_player then
                common.set_direction(enemy, enemy_common.direction_to_player(enemy))
            end

            if not coordinator.is_active() then
                return
            end

            if coordinator.transitioning_to_phase then
                enemy:set_state(options.exit_state and options.exit_state() or get_next_state())
                return
            end

            common.is_player_on_ground(enemy.target_player)

            if options.check_outer_platform then
                local on_outer_platform = enemy._platform_index == 1 or enemy._platform_index == 4
                if coordinator.player_on_ground and on_outer_platform then
                    enemy:set_state(options.exit_state and options.exit_state() or get_next_state())
                    return
                end
            end

            enemy.idle_timer = (enemy.idle_timer or 0) + dt
            if enemy.idle_timer >= idle_duration then
                enemy:set_state(get_next_state())
            end
        end,
        draw = enemy_common.draw,
    }
end

--- Create a bottom_wait state for waiting after leaving the bottom position.
---@param get_next_state function Returns the state to transition to
---@param options table|nil Optional settings: { wait_min, wait_max, check_bottom_available }
---@return table Bottom wait state definition
function common.create_bottom_wait_state(get_next_state, options)
    options = options or {}
    local wait_min = options.wait_min
    local wait_max = options.wait_max
    local check_bottom = options.check_bottom_available

    return {
        name = "bottom_wait",
        start = function(enemy)
            enemy.vx, enemy.vy, enemy.gravity, enemy.alpha = 0, 0, 0, 0
            enemy.invulnerable = false
            enemy._is_bottom_attacker = false

            if wait_min and wait_max then
                enemy._wait_duration = wait_min + math.random() * (wait_max - wait_min)
                enemy._wait_timer = 0
            end

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

            if wait_min and wait_max then
                enemy._wait_timer = enemy._wait_timer + dt
                if enemy._wait_timer >= enemy._wait_duration then
                    common.is_player_on_ground(enemy.target_player)
                    enemy:set_state(get_next_state())
                end
            elseif check_bottom then
                common.is_player_on_ground(enemy.target_player)
                if not coordinator.player_on_ground and coordinator.is_bottom_available() then
                    enemy:set_state(get_next_state())
                end
            end
        end,
        draw = common.noop,
    }
end

--- Reset cached data for level cleanup.
function common.reset()
    ground_level_spawn = nil
end

return common
