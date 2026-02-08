--- Valkyrie Boss Cinematic: Manages the intro sequence for the boss encounter.
--- Sequence: music fades -> slow walk to position -> turn left -> door closes ->
---   "?" -> valkyrie falls to left bridge -> lands -> turns right -> jumps arc to
---   right bridge -> lands -> turns to player -> slow attack -> phase 0
local audio = require("audio")
local music = require("audio/music")
local Prop = require("Prop")
local Effects = require("Effects")
local enemy_common = require("Enemies/common")
local coordinator = require("Enemies/Bosses/valkyrie/coordinator")
local valk_common = require("Enemies/Bosses/valkyrie/common")

-- Lazy-loaded to avoid circular dependency (platforms -> triggers -> registry -> valkyrie -> cinematic)
local platforms

-- Cinematic phases
local PHASE_IDLE = 0
local PHASE_WAIT_MUSIC_FADE = 1
local PHASE_WALKING = 2
local PHASE_TURN_TO_DOOR = 3
local PHASE_DOOR_CLOSING = 4
local PHASE_QUESTION = 5
local PHASE_VALKYRIE_FALL = 6
local PHASE_VALKYRIE_LAND_LEFT = 7
local PHASE_VALKYRIE_JUMP = 8
local PHASE_VALKYRIE_LAND_RIGHT = 9
local PHASE_VALKYRIE_ATTACK = 10
local PHASE_START_FIGHT = 11

-- Movement constants
local CINEMATIC_WALK_SPEED_MULT = 0.5

-- Timing constants (seconds)
local TURN_TO_DOOR_DURATION = 0.3
local DOOR_CLOSE_WAIT = 1.2
local QUESTION_DURATION = 1
local FALL_DURATION = 1.2          -- How long the valkyrie falls from above
local FALL_START_OFFSET_Y = -8     -- Tiles above landing point to start from
local JUMP_DURATION = 0.8          -- How long the arc jump takes
local JUMP_ARC_HEIGHT = 4          -- Tiles above start/end for arc peak

-- Attack at 25% speed (base ms_per_frame is 60, so 4x = 240)
local ATTACK_SLOW_MS = 240

local cinematic = {
    started = false,
    door = nil,
    player = nil,
    phase = PHASE_IDLE,
    timer = 0,
    -- Tween endpoints (reused for fall and jump)
    tween_start_x = 0,
    tween_start_y = 0,
    tween_end_x = 0,
    tween_end_y = 0,
    -- Jump switch flag (tracks if we switched from JUMP to FALL anim)
    jump_switched_to_fall = false,
}

--- Advance to the next cinematic phase and reset timer.
---@param next_phase number Phase constant to transition to
local function advance_phase(next_phase)
    cinematic.phase = next_phase
    cinematic.timer = 0
end

--- Ease-in quadratic (accelerating fall).
---@param t number Progress 0-1
---@return number Eased value
local function ease_in_quad(t)
    return t * t
end

--- Calculate enemy.y for hitbox-bottom alignment with a zone's bottom edge.
---@param enemy table Enemy with .box field
---@param zone table Zone with .y and .height
---@return number enemy_y position
local function align_hitbox_bottom(enemy, zone)
    local box = enemy.box or { x = 0.25, y = 0.625, w = 0.6875, h = 0.9375 }
    local target_bottom = zone.y + (zone.height or 0)
    return target_bottom - (box.y + box.h)
end

--- Face the player toward the valkyrie's current position.
local function face_player_toward_enemy(player, enemy)
    if not player or not enemy then return end
    local dir = enemy.x > player.x and 1 or -1
    player.direction = dir
    player.animation.flipped = dir
end

--- Update the cinematic sequence (called from player cinematic state).
---@param dt number Delta time in seconds
---@return boolean done True if cinematic is complete
function cinematic.update(dt)
    local phase = cinematic.phase
    if phase == PHASE_IDLE or phase == PHASE_WALKING then
        return false
    end

    cinematic.timer = cinematic.timer + dt
    local player = cinematic.player
    local enemy = coordinator.enemy

    if phase == PHASE_TURN_TO_DOOR and cinematic.timer >= TURN_TO_DOOR_DURATION then
        if cinematic.door and not cinematic.door.marked_for_destruction then
            Prop.set_state(cinematic.door, "closing")
        end
        advance_phase(PHASE_DOOR_CLOSING)
        return false
    end

    if phase == PHASE_DOOR_CLOSING and cinematic.timer >= DOOR_CLOSE_WAIT then
        advance_phase(PHASE_QUESTION)
        if player then
            Effects.create_text(player.x, player.y - 0.3, "?", "#FFFF00", 12)
            audio.play_huh()
        end
        return false
    end

    if phase == PHASE_QUESTION and cinematic.timer >= QUESTION_DURATION then
        -- Set up valkyrie fall tween to left bridge
        platforms = platforms or require("platforms")
        local landing = platforms.spawn_points["valkyrie_bridge_left"]

        if enemy and landing then
            local land_y = align_hitbox_bottom(enemy, landing)
            cinematic.tween_end_x = landing.x
            cinematic.tween_end_y = land_y
            cinematic.tween_start_x = landing.x
            cinematic.tween_start_y = land_y + FALL_START_OFFSET_Y

            enemy.x = cinematic.tween_start_x
            enemy.y = cinematic.tween_start_y
            enemy.direction = -1  -- Face left toward player
            enemy.vx = 0
            enemy.vy = 0
            enemy.gravity = 0
            enemy_common.set_animation(enemy, valk_common.ANIMATIONS.FALL)
        end

        face_player_toward_enemy(player, enemy)

        advance_phase(PHASE_VALKYRIE_FALL)
        return false
    end

    -- Fall from above to left bridge
    if phase == PHASE_VALKYRIE_FALL then
        face_player_toward_enemy(player, enemy)
        if enemy then
            local progress = math.min(1, cinematic.timer / FALL_DURATION)
            local eased = ease_in_quad(progress)

            enemy.x = cinematic.tween_start_x + (cinematic.tween_end_x - cinematic.tween_start_x) * eased
            enemy.y = cinematic.tween_start_y + (cinematic.tween_end_y - cinematic.tween_start_y) * eased

            if progress >= 1 then
                enemy.x = cinematic.tween_end_x
                enemy.y = cinematic.tween_end_y
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.LAND)
                audio.play_landing_sound()
                advance_phase(PHASE_VALKYRIE_LAND_LEFT)
            end
        else
            advance_phase(PHASE_START_FIGHT)
        end
        return false
    end

    -- Land on left bridge, then set up arc jump to right bridge
    if phase == PHASE_VALKYRIE_LAND_LEFT then
        face_player_toward_enemy(player, enemy)
        if enemy and enemy.animation:is_finished() then
            platforms = platforms or require("platforms")
            local right_bridge = platforms.spawn_points["valkyrie_bridge_right"]

            if right_bridge then
                -- Turn to face right before jumping
                enemy.direction = 1
                enemy.animation.flipped = 1

                -- Set up arc jump endpoints
                cinematic.tween_start_x = enemy.x
                cinematic.tween_start_y = enemy.y
                cinematic.tween_end_x = right_bridge.x
                cinematic.tween_end_y = align_hitbox_bottom(enemy, right_bridge)
                cinematic.jump_switched_to_fall = false

                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.JUMP)
            end

            advance_phase(PHASE_VALKYRIE_JUMP)
        end
        return false
    end

    -- Arc jump from left bridge to right bridge
    if phase == PHASE_VALKYRIE_JUMP then
        face_player_toward_enemy(player, enemy)
        if enemy then
            local progress = math.min(1, cinematic.timer / JUMP_DURATION)

            -- Linear X interpolation
            enemy.x = cinematic.tween_start_x + (cinematic.tween_end_x - cinematic.tween_start_x) * progress

            -- Parabolic Y arc: y = start + (end-start)*t - 4*height*t*(1-t)
            local base_y = cinematic.tween_start_y + (cinematic.tween_end_y - cinematic.tween_start_y) * progress
            local arc_offset = JUMP_ARC_HEIGHT * 4 * progress * (1 - progress)
            enemy.y = base_y - arc_offset

            -- Switch to fall animation at peak (halfway)
            if not cinematic.jump_switched_to_fall and progress >= 0.5 then
                cinematic.jump_switched_to_fall = true
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.FALL)
            end

            if progress >= 1 then
                enemy.x = cinematic.tween_end_x
                enemy.y = cinematic.tween_end_y
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.LAND)
                audio.play_landing_sound()
                advance_phase(PHASE_VALKYRIE_LAND_RIGHT)
            end
        else
            advance_phase(PHASE_START_FIGHT)
        end
        return false
    end

    -- Land on right bridge, turn to face player, play slow attack
    if phase == PHASE_VALKYRIE_LAND_RIGHT then
        face_player_toward_enemy(player, enemy)
        if enemy and enemy.animation:is_finished() then
            enemy.direction = -1  -- Face left toward player
            enemy_common.set_animation(enemy, valk_common.ANIMATIONS.ATTACK)
            enemy.animation.ms_per_frame = ATTACK_SLOW_MS
            advance_phase(PHASE_VALKYRIE_ATTACK)
        end
        return false
    end

    if phase == PHASE_VALKYRIE_ATTACK then
        face_player_toward_enemy(player, enemy)
        if enemy and enemy.animation:is_finished() then
            advance_phase(PHASE_START_FIGHT)
            coordinator.start(cinematic.player)
            return true
        end
        return false
    end

    return false
end

--- Start the cinematic intro sequence.
---@param player table The player instance
function cinematic.start(player)
    if cinematic.started then return end
    if coordinator.is_active() then return end

    cinematic.started = true
    cinematic.phase = PHASE_WAIT_MUSIC_FADE

    music.fade_out(1)

    if not player then
        coordinator.start()
        return
    end

    cinematic.player = player

    platforms = platforms or require("platforms")

    local target_pos = platforms.spawn_points["valkyrie_boss_player_start_position"]
    if not target_pos then
        coordinator.start()
        return
    end

    cinematic.door = Prop.find_by_id("valkrie_boss_door")

    player.cinematic_target = { x = target_pos.x }
    player.cinematic_on_complete = cinematic.on_walk_complete
    player.cinematic_update = cinematic.update
    player.cinematic_can_move = cinematic.can_move
    player.cinematic_walk_speed = player:get_speed() * CINEMATIC_WALK_SPEED_MULT
    player:set_state(player.states.cinematic)
end

--- Check if the player can start moving toward the target.
---@return boolean True if ready to move
function cinematic.can_move()
    if cinematic.phase == PHASE_WAIT_MUSIC_FADE then
        if music.is_faded_out() then
            cinematic.phase = PHASE_WALKING
            return true
        end
        return false
    end
    return true
end

--- Called when the player finishes walking to the target position.
--- Player faces left (toward door), then door closing begins.
function cinematic.on_walk_complete()
    local player = cinematic.player
    if player then
        player.direction = -1
        player.animation.flipped = -1
    end

    advance_phase(PHASE_TURN_TO_DOOR)
end

--- Check if cinematic is currently active.
---@return boolean True if cinematic is running
function cinematic.is_active()
    return cinematic.phase ~= PHASE_IDLE and cinematic.phase ~= PHASE_START_FIGHT
end

--- Reset cinematic state for level cleanup.
function cinematic.reset()
    cinematic.started = false
    cinematic.door = nil
    cinematic.player = nil
    cinematic.phase = PHASE_IDLE
    cinematic.timer = 0
    cinematic.tween_start_x = 0
    cinematic.tween_start_y = 0
    cinematic.tween_end_x = 0
    cinematic.tween_end_y = 0
    cinematic.jump_switched_to_fall = false
end

return cinematic
