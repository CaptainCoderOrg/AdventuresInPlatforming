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

-- Timing constants (shared across phases)
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

    local spawn_point = common.get_platforms().spawn_points["gnomo_boss_ground_level"]
    if not spawn_point or not spawn_point.width then
        coordinator.update_player_ground_status(true)
        return true
    end

    local px = player.x + player.box.x + player.box.w / 2
    local py = player.y + player.box.y + player.box.h / 2

    local on_ground = px >= spawn_point.x and px < spawn_point.x + spawn_point.width
        and py >= spawn_point.y and py < spawn_point.y + spawn_point.height

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
    -- Spawn position (center of gnomo)
    local spawn_x = enemy.x + 0.5
    local spawn_y = enemy.y + 0.5

    -- Calculate direction to target
    local dx = target_x - spawn_x
    local dy = target_y - spawn_y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Normalize and scale by axe speed
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

    for i, hole_id in ipairs(common.HOLE_IDS) do
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

    for i, platform_id in ipairs(common.PLATFORM_IDS) do
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
        start = function(enemy, _)
            enemy_common.set_animation(enemy, enemy.animations.ATTACK)
            enemy.vx = 0
            enemy._axes_thrown = 0
            enemy._axe_spawned_this_anim = false

            -- Get attack pattern for this platform
            local pattern = common.PLATFORM_ATTACK_PATTERNS[enemy._platform_index] or common.PLATFORM_ATTACK_PATTERNS[1]
            enemy._attack_start_angle = pattern.start
            enemy._attack_direction = pattern.direction
        end,
        update = function(enemy, dt)
            enemy_common.apply_gravity(enemy, dt)

            -- Spawn axe on frame 5 (same as gnomo_axe_thrower)
            if not enemy._axe_spawned_this_anim and enemy.animation.frame >= 5 then
                enemy._axe_spawned_this_anim = true

                -- Calculate angle for this axe
                local angle = enemy._attack_start_angle + (enemy._axes_thrown * common.ARC_STEP * enemy._attack_direction)

                -- Spawn directional axe
                common.spawn_directional_axe(enemy, angle)

                enemy._axes_thrown = enemy._axes_thrown + 1
                audio.play_axe_throw_sound()
            end

            if enemy.animation:is_finished() then
                if enemy._axes_thrown < common.AXES_PER_ATTACK then
                    -- Reset animation for next axe
                    enemy_common.set_animation(enemy, enemy.animations.ATTACK)
                    enemy._axe_spawned_this_anim = false
                else
                    -- All axes thrown, go to next state
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
        start = function(enemy, _)
            enemy_common.set_animation(enemy, enemy.animations.JUMP)
            enemy.vx = 0
            enemy.vy = 0
            enemy.gravity = 0

            -- Find nearest hole
            local hole_index = common.find_nearest_hole(enemy)
            enemy._exit_hole_index = hole_index
            local hole_id = common.HOLE_IDS[hole_index]
            local hx, hy = common.get_marker_position(hole_id)

            -- Store start and end positions
            enemy._lerp_start_x = enemy.x
            enemy._lerp_start_y = enemy.y
            enemy._lerp_end_x = hx or enemy.x
            enemy._lerp_end_y = hy or enemy.y
            enemy._lerp_timer = 0
            enemy.alpha = 1

            -- Release current platform
            if enemy._platform_index then
                coordinator.release_platform(enemy._platform_index)
                enemy._platform_index = nil
            end

            -- Make intangible immediately
            common.make_intangible(enemy)
        end,
        update = function(enemy, dt)
            enemy._lerp_timer = enemy._lerp_timer + dt
            local progress = math.min(1, enemy._lerp_timer / common.JUMP_EXIT_DURATION)
            local eased = common.smoothstep(progress)

            -- Update position
            enemy.x = common.lerp(enemy._lerp_start_x, enemy._lerp_end_x, eased)
            enemy.y = common.lerp(enemy._lerp_start_y, enemy._lerp_end_y, eased)

            -- Set upward jump frames
            common.set_jump_frame_range(enemy, common.FRAME_UPWARD_START, common.FRAME_UPWARD_END)

            -- Fade out in last portion
            if progress >= common.FADE_START_THRESHOLD then
                local fade_progress = (progress - common.FADE_START_THRESHOLD) / (1 - common.FADE_START_THRESHOLD)
                enemy.alpha = 1 - fade_progress
            end

            -- Done - transition to next state
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
        start = function(enemy, _)
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
        start = function(enemy, _)
            enemy_common.set_animation(enemy, enemy.animations.DEATH)
            enemy.vx = (enemy.hit_direction or -1) * 4
            enemy.vy = 0
            enemy.gravity = 0

            -- Release platform on death
            if enemy._platform_index then
                coordinator.release_platform(enemy._platform_index)
                enemy._platform_index = nil
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

return common
