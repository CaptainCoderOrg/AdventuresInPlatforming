--- Valkyrie Boss Common: Shared animations, draw, and state factories.
local Animation = require("Animation")
local audio = require("audio")
local canvas = require("canvas")
local combat = require("combat")
local config = require("config")
local enemy_common = require("Enemies/common")
local Prop = require("Prop")
local sprites = require("sprites")

-- Lazy-loaded to avoid circular dependency
local coordinator = nil

local common = {}

local FRAME_W = 40
local FRAME_H = 29

-- Cached sprite dimensions (avoid per-frame multiplication)
local SPRITE_WIDTH = FRAME_W * config.ui.SCALE
local SPRITE_HEIGHT = FRAME_H * config.ui.SCALE
local BASE_WIDTH = 16 * config.ui.SCALE
local EXTRA_HEIGHT = (FRAME_H - 16) * config.ui.SCALE
local Y_NUDGE = 13 * config.ui.SCALE
local X_NUDGE_RIGHT = 10 * config.ui.SCALE

-- Jump constants
local JUMP_ARC_HEIGHT = 4       -- Tiles above the line between start/end
local JUMP_DURATION = 0.8       -- Seconds for arc tween
local PREJUMP_MS = 180          -- ms per frame during prejump
local JUMP_CONTACT_DAMAGE = 3   -- Damage dealt on contact during jump

-- Attack constants
local DASH_DURATION = 0.3       -- Seconds for dash attack
local DASH_DISTANCE = 4         -- Tiles toward player
local DASH_CONTACT_DAMAGE = 3   -- Damage dealt on contact during dash
local PREP_DURATION = 0.5       -- Seconds for prep hold
local RECOVER_DURATION = 0.08   -- Seconds for recover hold
local GHOST_TRAIL_LIFETIME = 0.25
local GHOST_TRAIL_INTERVAL = 0.05

-- Animation definitions (single sheet, rows by animation)
local sheet = sprites.enemies.shieldmaiden.sheet
common.ANIMATIONS = {
    ATTACK = Animation.create_definition(sheet, 5, { ms_per_frame = 60, loop = false, width = FRAME_W, height = FRAME_H, row = 0 }),
    BLOCK = Animation.create_definition(sheet, 3, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 1 }),
    IDLE = Animation.create_definition(sheet, 4, { ms_per_frame = 150, width = FRAME_W, height = FRAME_H, row = 2 }),
    JUMP = Animation.create_definition(sheet, 2, { ms_per_frame = 80, loop = false, width = FRAME_W, height = FRAME_H, row = 3 }),
    FALL = Animation.create_definition(sheet, 3, { ms_per_frame = 100, width = FRAME_W, height = FRAME_H, row = 4 }),
    LAND = Animation.create_definition(sheet, 1, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 5 }),
    RUN = Animation.create_definition(sheet, 6, { ms_per_frame = 100, width = FRAME_W, height = FRAME_H, row = 6 }),
    HIT = Animation.create_definition(sheet, 3, { ms_per_frame = 120, loop = false, width = FRAME_W, height = FRAME_H, row = 7 }),
    DEATH = Animation.create_definition(sheet, 11, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 8 }),
    DASH_ATTACK = Animation.create_definition(sheet, 3, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 0, frame_offset = 0 }),
    RECOVER = Animation.create_definition(sheet, 1, { ms_per_frame = 80, loop = false, width = FRAME_W, height = FRAME_H, row = 0, frame_offset = 3 }),
}

--------------------------------------------------------------------------------
-- Ghost trail system
--------------------------------------------------------------------------------

local ghost_trails = {}

-- Ghost trail table pool (avoids per-spawn allocation)
local ghost_pool = {}
local ghost_pool_count = 0

local function acquire_ghost()
    if ghost_pool_count > 0 then
        local ghost = ghost_pool[ghost_pool_count]
        ghost_pool[ghost_pool_count] = nil
        ghost_pool_count = ghost_pool_count - 1
        return ghost
    end
    return {}
end

local function release_ghost(ghost)
    ghost_pool_count = ghost_pool_count + 1
    ghost_pool[ghost_pool_count] = ghost
end

--- Snapshot current position/direction/frame into the ghost trail array.
---@param enemy table The enemy instance
function common.spawn_ghost_trail(enemy)
    if not enemy.animation then return end
    local ghost = acquire_ghost()
    ghost.x = enemy.x
    ghost.y = enemy.y
    ghost.direction = enemy.direction
    ghost.definition = enemy.animation.definition
    ghost.frame = enemy.animation.frame
    ghost.elapsed = 0
    ghost.lifetime = GHOST_TRAIL_LIFETIME
    ghost_trails[#ghost_trails + 1] = ghost
end

--- Age ghost trail entries and remove expired ones.
---@param dt number Delta time in seconds
function common.update_ghost_trails(dt)
    local n = #ghost_trails
    local write = 0
    for i = 1, n do
        local ghost = ghost_trails[i]
        ghost.elapsed = ghost.elapsed + dt
        if ghost.elapsed < ghost.lifetime then
            write = write + 1
            ghost_trails[write] = ghost
        else
            release_ghost(ghost)
        end
    end
    for i = write + 1, n do
        ghost_trails[i] = nil
    end
end

--- Draw all active ghost trails with fading alpha.
function common.draw_ghost_trails()
    for i = 1, #ghost_trails do
        local ghost = ghost_trails[i]
        local alpha = 1 - (ghost.elapsed / ghost.lifetime)
        if alpha > 0 then
            local x = sprites.px(ghost.x)
            local y = sprites.px(ghost.y)

            canvas.save()
            canvas.set_global_alpha(alpha * 0.5)

            if ghost.direction == 1 then
                canvas.translate(x + SPRITE_WIDTH - BASE_WIDTH + X_NUDGE_RIGHT, y - EXTRA_HEIGHT + Y_NUDGE)
                canvas.scale(-1, 1)
            else
                canvas.translate(x - BASE_WIDTH, y - EXTRA_HEIGHT + Y_NUDGE)
            end

            local def = ghost.definition
            local sheet_frame = ghost.frame + (def.frame_offset or 0)
            local source_y = (def.row or 0) * def.height
            canvas.draw_image(def.name, 0, 0,
                SPRITE_WIDTH, SPRITE_HEIGHT,
                sheet_frame * def.width, source_y,
                def.width, def.height)

            canvas.restore()
        end
    end
end

--- Clear all ghost trails (returns tables to pool).
function common.clear_ghost_trails()
    for i = #ghost_trails, 1, -1 do
        release_ghost(ghost_trails[i])
        ghost_trails[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Bridge landing AoE
--------------------------------------------------------------------------------

local BRIDGE_AOE_SIZE = 3
local BRIDGE_AOE_DAMAGE = 3

--- Deal AoE damage to player when landing on a bridge.
--- Uses a 3-tile AABB centered on the valkyrie.
---@param enemy table The enemy instance
function common.bridge_landing_aoe(enemy)
    local player = enemy.target_player
    if not player or player:is_invincible() or player:health() <= 0 then return end

    local enemy_cx = enemy.x + enemy.box.x + enemy.box.w / 2
    local enemy_cy = enemy.y + enemy.box.y + enemy.box.h / 2
    local player_cx = player.x + player.box.x + player.box.w / 2
    local player_cy = player.y + player.box.y + player.box.h / 2

    local half = BRIDGE_AOE_SIZE / 2
    if math.abs(player_cx - enemy_cx) < half and math.abs(player_cy - enemy_cy) < half then
        player:take_damage(BRIDGE_AOE_DAMAGE, enemy.x, enemy)
    end
end

--- Draw valkyrie sprite (40x29 sprite with character anchored at bottom).
--- Uses canvas transforms to flip visually while hitbox stays fixed.
---@param enemy table The enemy instance
function common.draw_sprite(enemy)
    common.draw_ghost_trails()
    if not enemy.animation then return end

    local definition = enemy.animation.definition
    local frame = enemy.animation.frame
    local x = sprites.px(enemy.x)
    local lift = Prop.get_pressure_plate_lift(enemy)
    local y = sprites.stable_y(enemy, enemy.y, -lift)

    canvas.save()

    if enemy.direction == 1 then
        canvas.translate(x + SPRITE_WIDTH - BASE_WIDTH + X_NUDGE_RIGHT, y - EXTRA_HEIGHT + Y_NUDGE)
        canvas.scale(-1, 1)
    else
        canvas.translate(x - BASE_WIDTH, y - EXTRA_HEIGHT + Y_NUDGE)
    end

    local sheet_frame = frame + (definition.frame_offset or 0)
    local source_y = (definition.row or 0) * definition.height
    canvas.draw_image(definition.name, 0, 0,
        SPRITE_WIDTH, SPRITE_HEIGHT,
        sheet_frame * definition.width, source_y,
        definition.width, definition.height)
    canvas.restore()
end

--- Set the jump target for the valkyrie. Call before entering PreJump.
--- Positions so the hitbox bottom aligns with the bottom of the target zone.
---@param enemy table The enemy instance
---@param zone_key string Zone key for coordinator.get_zone()
function common.set_jump_target(enemy, zone_key)
    coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
    local zone = coordinator.get_zone(zone_key)
    if not zone then return end

    local box = enemy.box
    local target_bottom = zone.y + (zone.height or 0)
    enemy._jump_target_x = zone.x
    enemy._jump_target_y = target_bottom - (box.y + box.h)
end

--- Set the jump target from a pillar zone index.
---@param enemy table The enemy instance
---@param index number Pillar index (0-4)
function common.set_jump_target_pillar(enemy, index)
    coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
    local zone = coordinator.get_pillar_zone(index)
    if not zone then return end

    local box = enemy.box
    local target_bottom = zone.y + (zone.height or 0)
    enemy._jump_target_x = zone.x
    enemy._jump_target_y = target_bottom - (box.y + box.h)
end

--- Jump candidates for nearest-zone targeting.
local JUMP_CANDIDATES = {
    { get = function(c) return c.get_pillar_zone(0) end },
    { get = function(c) return c.get_pillar_zone(1) end },
    { get = function(c) return c.get_pillar_zone(2) end },
    { get = function(c) return c.get_pillar_zone(3) end },
    { get = function(c) return c.get_pillar_zone(4) end },
    { get = function(c) return c.get_bridge_zone("left") end },
    { get = function(c) return c.get_bridge_zone("right") end },
    { get = function(c) return c.get_zone("left") end },
    { get = function(c) return c.get_zone("right") end },
    { get = function(c) return c.get_zone("middle_platform") end },
}

--- Set the jump target to the zone nearest the player.
--- Picks from pillars, bridges, and named zones, aligning hitbox bottom.
---@param enemy table The enemy instance
function common.set_jump_target_nearest_player(enemy)
    coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
    local player = enemy.target_player
    if not player then return end

    local player_cx = player.x + (player.box.x + player.box.w / 2)
    local player_cy = player.y + (player.box.y + player.box.h / 2)

    local best_zone = nil
    local best_dist = math.huge

    for i = 1, #JUMP_CANDIDATES do
        local zone = JUMP_CANDIDATES[i].get(coordinator)
        if zone and zone.width then
            local zone_cx = zone.x + zone.width / 2
            local zone_cy = zone.y + (zone.height or 0) / 2
            local dx = player_cx - zone_cx
            local dy = player_cy - zone_cy
            local dist = dx * dx + dy * dy
            if dist < best_dist then
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

--------------------------------------------------------------------------------
-- Jump state factories
--------------------------------------------------------------------------------

--- Create a PreJump state. Plays JUMP animation at slow speed, invulnerable.
---@param get_jump_state function Returns the Jump state to transition to
---@return table state PreJump state definition
function common.create_prejump_state(get_jump_state)
    return {
        name = "prejump",
        start = function(enemy)
            enemy.invulnerable = true
            enemy.vx = 0
            enemy.gravity = 0
            enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
            enemy.animation.ms_per_frame = PREJUMP_MS

            -- Face toward target
            if enemy._jump_target_x then
                local dir = enemy._jump_target_x > enemy.x and 1 or -1
                enemy.direction = dir
                enemy.animation.flipped = dir
            end
        end,
        update = function(enemy, _dt)
            if enemy.animation:is_finished() then
                enemy:set_state(get_jump_state())
            end
        end,
        draw = common.draw_sprite,
    }
end

--- Create a Jump state. Arc tweens to target, invulnerable, deals contact damage.
--- Shows JUMP frame 1 while ascending, FALL animation while descending.
---@param get_landing_state function Returns the Landing state to transition to
---@return table state Jump state definition
function common.create_jump_state(get_landing_state)
    return {
        name = "jump",
        start = function(enemy)
            enemy.invulnerable = true
            enemy.vx = 0
            enemy.vy = 0
            enemy.gravity = 0

            enemy._jump_start_x = enemy.x
            enemy._jump_start_y = enemy.y
            enemy._jump_timer = 0
            enemy._jump_switched_to_fall = false

            -- Hold jump frame 1 (airborne pose)
            enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
            enemy.animation.frame = 1
            enemy.animation:pause()
        end,
        update = function(enemy, dt)
            enemy._jump_timer = enemy._jump_timer + dt
            local progress = math.min(1, enemy._jump_timer / JUMP_DURATION)

            local start_x = enemy._jump_start_x
            local start_y = enemy._jump_start_y
            local end_x = enemy._jump_target_x or start_x
            local end_y = enemy._jump_target_y or start_y

            -- Linear X
            enemy.x = start_x + (end_x - start_x) * progress

            -- Parabolic Y arc
            local base_y = start_y + (end_y - start_y) * progress
            local arc_offset = JUMP_ARC_HEIGHT * 4 * progress * (1 - progress)
            enemy.y = base_y - arc_offset

            -- Sync combat hitbox position
            combat.update(enemy)

            -- Switch to fall animation at peak
            if not enemy._jump_switched_to_fall and progress >= 0.5 then
                enemy._jump_switched_to_fall = true
                enemy_common.set_animation(enemy, common.ANIMATIONS.FALL)
            end

            -- Contact damage
            local player = enemy.target_player
            if player and not player:is_invincible() and player:health() > 0 then
                if combat.collides(enemy, player) then
                    player:take_damage(JUMP_CONTACT_DAMAGE, enemy.x)
                end
            end

            if progress >= 1 then
                enemy.x = end_x
                enemy.y = end_y
                combat.update(enemy)
                enemy:set_state(get_landing_state())
            end
        end,
        draw = common.draw_sprite,
    }
end

--- Create a Landing state. Plays LAND animation, then transitions.
---@param get_next_state function Returns the state to transition to after landing
---@return table state Landing state definition
function common.create_landing_state(get_next_state)
    return {
        name = "landing",
        start = function(enemy)
            enemy.invulnerable = false
            enemy.gravity = 1.5
            enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
            audio.play_landing_sound()
        end,
        update = function(enemy, _dt)
            if enemy.animation:is_finished() then
                enemy:set_state(get_next_state())
            end
        end,
        draw = common.draw_sprite,
    }
end

--- Create a MakeChoice state. For now, transitions to idle.
---@param get_idle_state function Returns the idle state to transition to
---@return table state MakeChoice state definition
function common.create_make_choice_state(get_idle_state)
    return {
        name = "make_choice",
        start = function(enemy)
            -- Face toward player
            if enemy.target_player then
                enemy.direction = enemy_common.direction_to_player(enemy)
                if enemy.animation then
                    enemy.animation.flipped = enemy.direction
                end
            end
        end,
        update = function(enemy, _dt)
            enemy:set_state(get_idle_state())
        end,
        draw = common.draw_sprite,
    }
end

--------------------------------------------------------------------------------
-- Shared jump states (reused across all phases)
-- Chain: prejump -> jump -> landing -> enemy.states.make_choice (phase-specific)
--------------------------------------------------------------------------------

common.states = {}

common.states.prejump = {
    name = "prejump",
    start = function(enemy)
        enemy.invulnerable = true
        enemy.vx = 0
        enemy.gravity = 0
        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation:pause()

        if enemy._jump_target_x then
            local dir = enemy._jump_target_x > enemy.x and 1 or -1
            enemy.direction = dir
            enemy.animation.flipped = dir
        end

        enemy._prejump_timer = 0
    end,
    update = function(enemy, dt)
        enemy._prejump_timer = enemy._prejump_timer + dt
        if enemy._prejump_timer >= PREJUMP_MS / 1000 then
            enemy:set_state(common.states.jump)
        end
    end,
    draw = common.draw_sprite,
}

common.states.jump = {
    name = "jump",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.vx = 0
        enemy.vy = 0
        enemy.gravity = 0

        enemy._jump_start_x = enemy.x
        enemy._jump_start_y = enemy.y
        enemy._jump_timer = 0
        enemy._jump_switched_to_fall = false

        -- Hold jump frame 1 (airborne pose)
        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation.frame = 1
        enemy.animation:pause()
    end,
    update = function(enemy, dt)
        enemy._jump_timer = enemy._jump_timer + dt
        local progress = math.min(1, enemy._jump_timer / JUMP_DURATION)

        local start_x = enemy._jump_start_x
        local start_y = enemy._jump_start_y
        local end_x = enemy._jump_target_x or start_x
        local end_y = enemy._jump_target_y or start_y

        -- Linear X
        enemy.x = start_x + (end_x - start_x) * progress

        -- Parabolic Y arc
        local base_y = start_y + (end_y - start_y) * progress
        local arc_offset = JUMP_ARC_HEIGHT * 4 * progress * (1 - progress)
        enemy.y = base_y - arc_offset

        -- Sync combat hitbox position
        combat.update(enemy)

        -- Switch to fall animation at peak
        if not enemy._jump_switched_to_fall and progress >= 0.5 then
            enemy._jump_switched_to_fall = true
            enemy.invulnerable = true
            enemy_common.set_animation(enemy, common.ANIMATIONS.FALL)
        end

        -- Contact damage
        local player = enemy.target_player
        if player and not player:is_invincible() and player:health() > 0 then
            if combat.collides(enemy, player) then
                player:take_damage(JUMP_CONTACT_DAMAGE, enemy.x, enemy)
            end
        end

        if progress >= 1 then
            enemy.x = end_x
            enemy.y = end_y
            combat.update(enemy)
            enemy:set_state(enemy.states.landing)
        end
    end,
    draw = common.draw_sprite,
}

common.states.landing = {
    name = "landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(enemy.states.make_choice)
        end
    end,
    draw = common.draw_sprite,
}

--------------------------------------------------------------------------------
-- Shared dive-bomb states (reused by phase 2 and phase 3)
-- These reference enemy.states.* for phase-specific routing and
-- enemy._hazard_cleanup() for phase-specific hazard teardown.
--------------------------------------------------------------------------------

local DIVE_MAKE_CHOICE_DELAY = 0.8
local DIVE_JUMP_UP_DURATION = 0.5
local DIVE_WAIT = 1.5
local DIVE_DURATION = 0.75
local DIVE_CONTACT_DAMAGE = 3
local DIVE_TRAIL_INTERVAL = 0.05
local DIVE_OFF_SCREEN_OFFSET = 3  -- tiles above camera:get_y()

--- Hazard-aware landing: routes to bridge_attack in hazard mode, prep_attack otherwise.
common.states.hazard_landing = {
    name = "hazard_landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
        -- AoE knockback when landing on a bridge
        if enemy._entering_hazard_mode then
            common.bridge_landing_aoe(enemy)
        end
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            if enemy._entering_hazard_mode then
                enemy._entering_hazard_mode = false
                enemy:set_state(enemy.states.bridge_attack)
            else
                enemy:set_state(enemy.states.prep_attack)
            end
        end
    end,
    draw = common.draw_sprite,
}

--- Ascend off screen. If button was pressed, skip to ground mode.
common.states.jump_off_screen = {
    name = "jump_off_screen",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")

        -- Early exit: button was pressed during bridge_attack or dive loop
        if enemy._exit_dive_loop then
            enemy._exit_dive_loop = false
            if enemy._hazard_cleanup then enemy._hazard_cleanup() end
            enemy.invulnerable = false
            enemy:set_state(enemy.states.dive_make_choice)
            return
        end

        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        -- Refresh boss blocks
        coordinator.activate_blocks()

        -- Target: above camera top
        enemy._ascend_start_y = enemy.y
        enemy._ascend_target_y = coordinator.camera:get_y() - DIVE_OFF_SCREEN_OFFSET
        enemy._ascend_timer = 0

        -- Hold JUMP frame 1 (airborne pose)
        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation.frame = 1
        enemy.animation:pause()
    end,
    update = function(enemy, dt)
        enemy._ascend_timer = enemy._ascend_timer + dt
        local progress = math.min(1, enemy._ascend_timer / DIVE_JUMP_UP_DURATION)

        enemy.y = enemy._ascend_start_y + (enemy._ascend_target_y - enemy._ascend_start_y) * progress
        combat.update(enemy)

        if progress >= 1 then
            enemy:set_state(enemy.states.dive_bomb)
        end
    end,
    draw = common.draw_sprite,
}

--- Dive bomb: wait off-screen, then plunge at player position.
common.states.dive_bomb = {
    name = "dive_bomb",
    start = function(enemy)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        enemy._dive_waiting = true
        enemy._dive_timer = 0
        enemy._dive_trail_timer = 0
    end,
    update = function(enemy, dt)
        coordinator = coordinator or require("Enemies/Bosses/valkyrie/coordinator")
        enemy._dive_timer = enemy._dive_timer + dt

        if enemy._dive_waiting then
            -- Wait phase: invisible off-screen
            if enemy._dive_timer >= DIVE_WAIT then
                enemy._dive_waiting = false
                enemy._dive_timer = 0

                -- Move valkyrie to player's X (invisible off-screen)
                -- Floor Y = bottom of valkyrie_boss_middle zone
                local player = enemy.target_player
                local box = enemy.box

                if player then
                    local player_cx = player.x + (player.box.x + player.box.w / 2)
                    local offset = (math.random() < 0.5) and -3 or 3
                    local target_x = player_cx - (box.x + box.w / 2) + offset

                    -- Clamp within camera horizontal bounds
                    local cam = coordinator.camera
                    if cam then
                        local cam_left = cam:get_x()
                        local cam_right = cam_left + cam:get_viewport_width() / sprites.tile_size
                        local enemy_left = target_x + box.x
                        local enemy_right = target_x + box.x + box.w
                        if enemy_left < cam_left then
                            target_x = target_x + (cam_left - enemy_left)
                        elseif enemy_right > cam_right then
                            target_x = target_x - (enemy_right - cam_right)
                        end
                    end

                    enemy.x = target_x
                    enemy._dive_target_x = player_cx - (box.x + box.w / 2)
                end

                local middle_zone = coordinator.get_zone("middle")
                local floor_y = middle_zone and (middle_zone.y + (middle_zone.height or 0)) or enemy.y
                enemy._dive_target_y = floor_y - (box.y + box.h)

                if not player then
                    enemy._dive_target_x = enemy.x
                end
                enemy._dive_start_x = enemy.x
                enemy._dive_start_y = enemy.y

                -- Refresh boss blocks
                coordinator.activate_blocks()

                -- Switch to FALL animation, face toward target
                enemy_common.set_animation(enemy, common.ANIMATIONS.FALL)
                local dir = enemy._dive_target_x > enemy.x and 1 or -1
                enemy.direction = dir
                enemy.animation.flipped = dir
            end
        else
            -- Descent phase: linear tween to target
            local progress = math.min(1, enemy._dive_timer / DIVE_DURATION)

            enemy.x = enemy._dive_start_x + (enemy._dive_target_x - enemy._dive_start_x) * progress
            enemy.y = enemy._dive_start_y + (enemy._dive_target_y - enemy._dive_start_y) * progress

            combat.update(enemy)

            -- Ghost trail
            enemy._dive_trail_timer = enemy._dive_trail_timer + dt
            if enemy._dive_trail_timer >= DIVE_TRAIL_INTERVAL then
                enemy._dive_trail_timer = enemy._dive_trail_timer - DIVE_TRAIL_INTERVAL
                common.spawn_ghost_trail(enemy)
            end

            -- Contact damage
            local player = enemy.target_player
            if player and not player:is_invincible() and player:health() > 0 then
                if combat.collides(enemy, player) then
                    player:take_damage(DIVE_CONTACT_DAMAGE, enemy.x, enemy)
                end
            end

            if progress >= 1 then
                if enemy._exit_dive_loop then
                    enemy._exit_dive_loop = false
                    enemy:set_state(enemy.states.ground_landing)
                else
                    audio.play_landing_sound()
                    enemy:set_state(enemy.states.jump_off_screen)
                end
            end
        end
    end,
    draw = function(enemy)
        -- Invisible during wait phase
        if enemy._dive_waiting then return end
        common.draw_sprite(enemy)
    end,
}

--- Landing after dive bomb exit: transition to ground attack pattern.
common.states.ground_landing = {
    name = "ground_landing",
    start = function(enemy)
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy_common.set_animation(enemy, common.ANIMATIONS.LAND)
        audio.play_landing_sound()
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(enemy.states.dive_make_choice)
        end
    end,
    draw = common.draw_sprite,
}

--- Face player, wait, then jump to nearest zone for attack.
common.states.dive_make_choice = {
    name = "dive_make_choice",
    start = function(enemy)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
        if enemy.animation then
            enemy.animation.flipped = enemy.direction
        end
        enemy._choice_timer = 0
    end,
    update = function(enemy, dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
        end

        enemy._choice_timer = enemy._choice_timer + dt
        if enemy._choice_timer >= DIVE_MAKE_CHOICE_DELAY then
            common.set_jump_target_nearest_player(enemy)
            enemy:set_state(enemy.states.prejump)
        end
    end,
    draw = common.draw_sprite,
}

--- Check if the player overlaps the spear hitbox extending in front of the valkyrie.
--- The spear adds one hitbox-width of reach beyond the body, doubling effective range.
---@param enemy table The enemy instance
---@param player table The player instance
---@return boolean True if spear hitbox overlaps player
local function spear_collides(enemy, player)
    local box = enemy.box
    local pbox = player.box

    local ex = enemy.x + box.x
    local ey = enemy.y + box.y

    -- Spear extends one hitbox-width in the facing direction
    local spear_x
    if enemy.direction == 1 then
        spear_x = ex + box.w
    else
        spear_x = ex - box.w
    end

    local px = player.x + pbox.x
    local py = player.y + pbox.y

    return spear_x < px + pbox.w and spear_x + box.w > px
       and ey < py + pbox.h and ey + box.h > py
end

--------------------------------------------------------------------------------
-- Shared attack states (reused across phases)
-- Chain: prep_attack -> dash_attack -> recover -> enemy.states.make_choice
--------------------------------------------------------------------------------

common.states.prep_attack = {
    name = "prep_attack",
    start = function(enemy)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
        end
        enemy_common.set_animation(enemy, common.ANIMATIONS.JUMP)
        enemy.animation:pause()
        enemy.animation.flipped = enemy.direction
        enemy._in_prep_attack = true
        enemy._prep_timer = 0
    end,
    update = function(enemy, dt)
        enemy._prep_timer = enemy._prep_timer + dt
        if enemy._prep_timer >= PREP_DURATION then
            enemy:set_state(enemy.states.dash_attack)
        end
    end,
    draw = common.draw_sprite,
}

common.states.dash_attack = {
    name = "dash_attack",
    start = function(enemy)
        enemy._in_prep_attack = false
        local player = enemy.target_player
        if player then
            local enemy_cx = enemy.x + (enemy.box.x + enemy.box.w / 2)
            local player_cx = player.x + (player.box.x + player.box.w / 2)
            local dir = (player_cx > enemy_cx) and 1 or -1
            enemy.direction = dir
            enemy._dash_target_x = enemy.x + dir * DASH_DISTANCE
        else
            enemy._dash_target_x = enemy.x
        end
        enemy._dash_target_y = enemy.y
        enemy._dash_start_x = enemy.x
        enemy._dash_start_y = enemy.y
        enemy._dash_timer = 0
        enemy._dash_trail_timer = 0

        enemy.invulnerable = true
        enemy.gravity = 0
        enemy.vx = 0
        enemy.vy = 0

        enemy_common.set_animation(enemy, common.ANIMATIONS.DASH_ATTACK)
        enemy.animation.flipped = enemy.direction

        audio.play_sfx(audio.dash, 0.15)
    end,
    update = function(enemy, dt)
        enemy._dash_timer = enemy._dash_timer + dt
        local progress = math.min(1, enemy._dash_timer / DASH_DURATION)

        enemy.x = enemy._dash_start_x + (enemy._dash_target_x - enemy._dash_start_x) * progress
        enemy.y = enemy._dash_start_y + (enemy._dash_target_y - enemy._dash_start_y) * progress

        -- Sync combat hitbox
        combat.update(enemy)

        -- Ghost trail
        enemy._dash_trail_timer = enemy._dash_trail_timer + dt
        if enemy._dash_trail_timer >= GHOST_TRAIL_INTERVAL then
            enemy._dash_trail_timer = enemy._dash_trail_timer - GHOST_TRAIL_INTERVAL
            common.spawn_ghost_trail(enemy)
        end

        local player = enemy.target_player
        if player and not player:is_invincible() and player:health() > 0 then
            if combat.collides(enemy, player) or spear_collides(enemy, player) then
                player:take_damage(DASH_CONTACT_DAMAGE, enemy.x, enemy)
            end
        end

        if progress >= 1 then
            enemy:set_state(enemy.states.recover)
        end
    end,
    draw = common.draw_sprite,
}

common.states.recover = {
    name = "recover",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.RECOVER)
        enemy.animation.flipped = enemy.direction
        enemy.invulnerable = false
        enemy.gravity = 1.5
        enemy._recover_timer = 0
    end,
    update = function(enemy, dt)
        enemy._recover_timer = enemy._recover_timer + dt
        if enemy._recover_timer >= RECOVER_DURATION then
            enemy:set_state(enemy.states.make_choice)
        end
    end,
    draw = common.draw_sprite,
}

--------------------------------------------------------------------------------
-- Standard state factories
--------------------------------------------------------------------------------

--- Create a standard hit state that transitions to a return state.
---@param get_return_state function Returns the state to go to after hit animation
---@return table state Hit state definition
function common.create_hit_state(get_return_state)
    return {
        name = "hit",
        start = function(enemy)
            enemy_common.set_animation(enemy, common.ANIMATIONS.HIT)
            enemy.vx = (enemy.hit_direction or -1) * 2
        end,
        update = function(enemy, dt)
            enemy.vx = enemy_common.apply_friction(enemy.vx, 0.9, dt)
            if enemy.animation:is_finished() then
                enemy:set_state(get_return_state())
            end
        end,
        draw = common.draw_sprite,
    }
end

--- Create a standard death state.
---@return table state Death state definition
function common.create_death_state()
    return {
        name = "death",
        start = function(enemy)
            enemy_common.set_animation(enemy, common.ANIMATIONS.DEATH)
            enemy.vx = (enemy.hit_direction or -1) * 4
            enemy.vy = 0
            enemy.gravity = 0
        end,
        update = function(enemy, dt)
            enemy.vx = enemy_common.apply_friction(enemy.vx, 0.9, dt)
            if enemy.animation:is_finished() then
                enemy.marked_for_destruction = true
            end
        end,
        draw = common.draw_sprite,
    }
end

return common
