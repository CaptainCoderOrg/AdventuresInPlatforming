--- Valkyrie Boss Apology Path: Peaceful resolution when player has valkyrie_apology item.
--- Completely separate from the boss coordinator to avoid state bugs.
--- Sequence: intro cinematic -> valkyrie falls -> dialogue -> shard drop -> valkyrie exits -> collect
local audio = require("audio")
local canvas = require("canvas")
local music = require("audio/music")
local Effects = require("Effects")
local Prop = require("Prop")
local coordinator = require("Enemies/Bosses/valkyrie/coordinator")
local valk_common = require("Enemies/Bosses/valkyrie/common")
local dialogue_manager = require("dialogue/manager")
local dialogue_screen = require("ui/dialogue_screen")
local enemy_common = require("Enemies/common")
local sprites_items = require("sprites/items")

-- Lazy-loaded modules
local platforms = nil

-- References set by main.lua
local camera_ref = nil

local apology_path = {}

-- Phase constants
local PHASE_IDLE = 0
local PHASE_WAIT_MUSIC_FADE = 1
local PHASE_WALKING = 2
local PHASE_DOOR_CLOSING = 3
local PHASE_QUESTION = 4
local PHASE_VALKYRIE_FALL = 5
local PHASE_VALKYRIE_LAND_LEFT = 6
local PHASE_VALKYRIE_JUMP = 7
local PHASE_VALKYRIE_LAND_RIGHT = 8
local PHASE_VALKYRIE_QUESTION = 9
local PHASE_DIALOGUE = 10
local PHASE_SHARD_DROP = 11
local PHASE_VALKYRIE_EXIT = 12
local PHASE_WAIT_COLLECT = 13
local PHASE_COMPLETE = 14

-- Timing constants (seconds)
local DOOR_CLOSE_WAIT = 1.2
local QUESTION_DURATION = 1
local FALL_DURATION = 1.2
local FALL_START_OFFSET_Y = -8
local VALKYRIE_QUESTION_DURATION = 0.8
local JUMP_DURATION = 0.8
local JUMP_ARC_HEIGHT = 4
local EXIT_JUMP_DURATION = 0.8
local EXIT_JUMP_HEIGHT = 6

-- Movement constants
local CINEMATIC_WALK_SPEED_MULT = 0.5

-- Minimal exit state with alpha-aware drawing
local exit_state = {
    name = "apology_exit",
    start = function() end,
    update = function() end,
    draw = function(enemy)
        local needs_alpha = enemy.alpha and enemy.alpha < 1
        if needs_alpha then
            canvas.set_global_alpha(enemy.alpha)
        end
        valk_common.draw_sprite(enemy)
        if needs_alpha then
            canvas.set_global_alpha(1)
        end
    end,
}

-- State
local state = {
    started = false,
    phase = PHASE_IDLE,
    timer = 0,
    player = nil,
    door = nil,
    -- Valkyrie entity (from coordinator)
    valkyrie = nil,
    -- Fall tween
    fall_start_x = 0,
    fall_start_y = 0,
    fall_end_x = 0,
    fall_end_y = 0,
    -- Jump arc tween (bridge_left -> pillar_1)
    jump_start_x = 0,
    jump_start_y = 0,
    jump_end_x = 0,
    jump_end_y = 0,
    jump_switched_to_fall = false,
    -- Shard tracking
    shard_prop = nil,
    shard_landed = false,
    -- Exit tween
    exit_start_x = 0,
    exit_start_y = 0,
    exit_end_y = 0,
    exit_timer = 0,
}

--- Lazy load platforms module
local function get_platforms()
    if not platforms then
        platforms = require("platforms")
    end
    return platforms
end

--- Advance to the next phase and reset timer.
---@param next_phase number Phase constant to transition to
local function advance_phase(next_phase)
    state.phase = next_phase
    state.timer = 0
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
---@param player table The player instance
---@param enemy table The valkyrie enemy instance
local function face_player_toward_enemy(player, enemy)
    if not player or not enemy then return end
    local dir = enemy.x > player.x and 1 or -1
    player.direction = dir
    player.animation.flipped = dir
end

--- Called when the arcane shard lands on the ground.
local function on_shard_landed()
    local plat = get_platforms()
    local middle = plat.spawn_points["valkyrie_boss_middle"]
    local ground_y
    if middle then
        ground_y = middle.y + middle.height - 1
    else
        ground_y = state.valkyrie and (state.valkyrie.y + 3) or 0
    end

    local drop_x = state.valkyrie and (state.valkyrie.x + 0.5) or 0
    state.shard_prop = Prop.spawn("stackable_item", drop_x, ground_y, { item_id = "arcane_shard" })
    state.shard_landed = true
end

--- Cinematic update callback (called via player.cinematic_update).
---@param dt number Delta time in seconds
---@return boolean done True if player should exit cinematic state
local function cinematic_update(dt)
    if state.phase == PHASE_IDLE or state.phase == PHASE_WALKING then
        return false
    end

    state.timer = state.timer + dt
    local player = state.player
    local enemy = state.valkyrie

    -- Phase: Door closing
    if state.phase == PHASE_DOOR_CLOSING and state.timer >= DOOR_CLOSE_WAIT then
        advance_phase(PHASE_QUESTION)
        if player then
            Effects.create_text(player.x, player.y - 0.3, "?", "#FFFF00", 12)
            audio.play_huh()
        end
        return false
    end

    -- Phase: Player question mark
    if state.phase == PHASE_QUESTION and state.timer >= QUESTION_DURATION then
        -- Set up valkyrie fall to left bridge
        local plat = get_platforms()
        local landing = plat.spawn_points["valkyrie_bridge_left"]

        if enemy and landing then
            local land_y = align_hitbox_bottom(enemy, landing)
            state.fall_end_x = landing.x
            state.fall_end_y = land_y
            state.fall_start_x = landing.x
            state.fall_start_y = land_y + FALL_START_OFFSET_Y

            enemy.x = state.fall_start_x
            enemy.y = state.fall_start_y
            enemy.direction = -1
            enemy.vx = 0
            enemy.vy = 0
            enemy.gravity = 0
            enemy.invulnerable = true
            enemy_common.set_animation(enemy, valk_common.ANIMATIONS.FALL)
        end

        face_player_toward_enemy(player, enemy)
        advance_phase(PHASE_VALKYRIE_FALL)
        return false
    end

    -- Phase: Valkyrie falling from above
    if state.phase == PHASE_VALKYRIE_FALL then
        face_player_toward_enemy(player, enemy)
        if enemy then
            local progress = math.min(1, state.timer / FALL_DURATION)
            local eased = ease_in_quad(progress)

            enemy.x = state.fall_start_x + (state.fall_end_x - state.fall_start_x) * eased
            enemy.y = state.fall_start_y + (state.fall_end_y - state.fall_start_y) * eased

            if progress >= 1 then
                enemy.x = state.fall_end_x
                enemy.y = state.fall_end_y
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.LAND)
                audio.play_landing_sound()
                advance_phase(PHASE_VALKYRIE_LAND_LEFT)
            end
        else
            advance_phase(PHASE_COMPLETE)
        end
        return false
    end

    -- Phase: Valkyrie lands on left bridge, then sets up jump to pillar 1
    if state.phase == PHASE_VALKYRIE_LAND_LEFT then
        face_player_toward_enemy(player, enemy)
        if enemy and enemy.animation:is_finished() then
            -- Set up arc jump to pillar 1
            local pillar = coordinator.get_pillar_zone(1)
            if pillar then
                local land_y = align_hitbox_bottom(enemy, pillar)
                state.jump_start_x = enemy.x
                state.jump_start_y = enemy.y
                state.jump_end_x = pillar.x
                state.jump_end_y = land_y
                state.jump_switched_to_fall = false

                enemy.direction = 1
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.JUMP)
                advance_phase(PHASE_VALKYRIE_JUMP)
            else
                advance_phase(PHASE_VALKYRIE_QUESTION)
            end
        end
        return false
    end

    -- Phase: Valkyrie arc jumps from left bridge to pillar 1
    if state.phase == PHASE_VALKYRIE_JUMP then
        if enemy then
            local progress = math.min(1, state.timer / JUMP_DURATION)

            -- Linear X interpolation
            enemy.x = state.jump_start_x + (state.jump_end_x - state.jump_start_x) * progress

            -- Parabolic Y arc: base lerp + arc offset
            local base_y = state.jump_start_y + (state.jump_end_y - state.jump_start_y) * progress
            local arc_offset = 4 * JUMP_ARC_HEIGHT * progress * (1 - progress)
            enemy.y = base_y - arc_offset

            -- Switch to fall animation at midpoint
            if progress >= 0.5 and not state.jump_switched_to_fall then
                state.jump_switched_to_fall = true
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.FALL)
            end

            if progress >= 1 then
                enemy.x = state.jump_end_x
                enemy.y = state.jump_end_y
                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.LAND)
                audio.play_landing_sound()
                advance_phase(PHASE_VALKYRIE_LAND_RIGHT)
            end
        else
            advance_phase(PHASE_COMPLETE)
        end
        return false
    end

    -- Phase: Valkyrie lands on pillar 1, turns to face player
    if state.phase == PHASE_VALKYRIE_LAND_RIGHT then
        if enemy and enemy.animation:is_finished() then
            -- Turn to face the player
            enemy.direction = -1
            enemy_common.set_animation(enemy, valk_common.ANIMATIONS.IDLE)
            if enemy.animation then
                enemy.animation.flipped = enemy.direction
            end
            face_player_toward_enemy(player, enemy)
            Effects.create_text(enemy.x, enemy.y - 0.3, "?", "#FFFF00", 12)
            advance_phase(PHASE_VALKYRIE_QUESTION)
        end
        return false
    end

    -- Phase: Valkyrie question mark
    if state.phase == PHASE_VALKYRIE_QUESTION and state.timer >= VALKYRIE_QUESTION_DURATION then
        advance_phase(PHASE_DIALOGUE)
        if camera_ref then
            dialogue_screen.start("valkyrie_apology", state.player, camera_ref)
        end
        return false
    end

    -- Phase: Dialogue
    if state.phase == PHASE_DIALOGUE then
        if not dialogue_screen.is_active() then
            advance_phase(PHASE_SHARD_DROP)
            -- Drop arcane shard from valkyrie
            if enemy then
                local plat = get_platforms()
                local middle = plat.spawn_points["valkyrie_boss_middle"]
                local ground_y
                if middle then
                    ground_y = middle.y + middle.height - 1
                else
                    ground_y = enemy.y + 3
                end

                Effects.create_flying_object(enemy.x + 0.5, enemy.y, enemy.x + 0.5, ground_y, {
                    sprite = sprites_items.arcane_shard,
                    rotations = 0,
                    flight_duration = 0.75,
                    on_complete = on_shard_landed,
                })
            end
        end
        return false
    end

    -- Phase: Shard dropping
    if state.phase == PHASE_SHARD_DROP then
        if state.shard_landed then
            advance_phase(PHASE_VALKYRIE_EXIT)
            -- Set up exit: valkyrie jumps up and off screen
            if enemy then
                state.exit_start_x = enemy.x
                state.exit_start_y = enemy.y
                state.exit_end_y = enemy.y - EXIT_JUMP_HEIGHT
                state.exit_timer = 0
                enemy.alpha = 1

                enemy_common.set_animation(enemy, valk_common.ANIMATIONS.JUMP)
                if enemy.animation then
                    enemy.animation.frame = 1
                    enemy.animation:pause()
                end

                -- Switch to alpha-aware exit state for fade-out drawing
                enemy.state = exit_state
            end
        end
        return false
    end

    -- Phase: Valkyrie exits (jumps off screen)
    if state.phase == PHASE_VALKYRIE_EXIT then
        if enemy then
            state.exit_timer = state.exit_timer + dt
            local progress = math.min(1, state.exit_timer / EXIT_JUMP_DURATION)

            enemy.y = state.exit_start_y + (state.exit_end_y - state.exit_start_y) * progress

            -- Fade out
            enemy.alpha = 1 - progress

            if progress >= 1 then
                enemy.marked_for_destruction = true
                advance_phase(PHASE_WAIT_COLLECT)
                -- Free player movement
                if player then
                    player:set_state(player.states.idle)
                end
            end
        else
            advance_phase(PHASE_WAIT_COLLECT)
            if player then
                player:set_state(player.states.idle)
            end
        end
        return false
    end

    -- Phase: Waiting for shard collection
    if state.phase == PHASE_WAIT_COLLECT then
        if state.shard_prop and state.shard_prop.marked_for_destruction then
            apology_path.complete()
            return true
        end
        return false
    end

    return state.phase == PHASE_COMPLETE
end

--- Set references for dialogue screen.
---@param _player table Player instance (unused, kept for consistency)
---@param camera table Camera instance
function apology_path.set_refs(_player, camera)
    camera_ref = camera
end

--- Start the apology path sequence.
---@param player table The player instance
function apology_path.start(player)
    if state.started then return end
    if coordinator.is_active() then return end

    state.started = true
    state.phase = PHASE_WAIT_MUSIC_FADE
    state.player = player
    state.valkyrie = coordinator.enemy

    -- Fade out level music
    music.fade_out(1)

    if not player then
        apology_path.complete()
        return
    end

    -- Lazy load platforms
    platforms = get_platforms()

    local target_pos = platforms.spawn_points["valkyrie_boss_player_start_position"]
    if not target_pos then
        apology_path.complete()
        return
    end

    -- Find the boss door
    state.door = Prop.find_by_id(coordinator.DOOR_ID)

    -- Make valkyrie invulnerable and freeze
    if state.valkyrie and not state.valkyrie.marked_for_destruction then
        state.valkyrie.invulnerable = true
        state.valkyrie.vx = 0
        state.valkyrie.vy = 0
        state.valkyrie.gravity = 0
    end

    -- Set up cinematic walk
    player.cinematic_target = { x = target_pos.x }
    player.cinematic_on_complete = apology_path.on_walk_complete
    player.cinematic_update = cinematic_update
    player.cinematic_can_move = apology_path.can_move
    player.cinematic_walk_speed = player:get_speed() * CINEMATIC_WALK_SPEED_MULT
    player:set_state(player.states.cinematic)
end

--- Check if player can start moving (music faded).
---@return boolean True if ready to move
function apology_path.can_move()
    if state.phase == PHASE_WAIT_MUSIC_FADE then
        if music.is_faded_out() then
            state.phase = PHASE_WALKING
            return true
        end
        return false
    end
    return true
end

--- Called when player finishes walking to position.
function apology_path.on_walk_complete()
    -- Close the door
    if state.door and not state.door.marked_for_destruction then
        Prop.set_state(state.door, "closing")
    end

    -- Player faces left
    local player = state.player
    if player then
        player.direction = -1
        player.animation.flipped = -1
    end

    advance_phase(PHASE_DOOR_CLOSING)
end

--- Complete the apology path and set flags.
function apology_path.complete()
    local player = state.player

    -- Mark boss as defeated
    if player and player.defeated_bosses then
        player.defeated_bosses[coordinator.boss_id] = true
    end

    -- Remove apology item from player inventory
    if player and player.unique_items then
        for i, item in ipairs(player.unique_items) do
            if item == "valkyrie_apology" then
                table.remove(player.unique_items, i)
                break
            end
        end
    end

    -- Set flag for quest completion
    dialogue_manager.set_flag("valkyrie_apology_delivered")

    -- Journal: record apology delivery (written directly to avoid toast during cinematic)
    if player and player.journal then
        player.journal["valkyrie_apology_delivered"] = player.journal["valkyrie_apology_delivered"] or "active"
    end

    -- Open the door
    local door = Prop.find_by_id(coordinator.DOOR_ID)
    if door and not door.marked_for_destruction then
        Prop.set_state(door, "opening")
    end

    -- Mark valkyrie for destruction (may already be marked)
    if state.valkyrie and not state.valkyrie.marked_for_destruction then
        state.valkyrie.marked_for_destruction = true
    end

    state.phase = PHASE_COMPLETE
end

--- Check if apology path is currently active.
---@return boolean True if sequence is in progress
function apology_path.is_active()
    return state.phase ~= PHASE_IDLE and state.phase ~= PHASE_COMPLETE
end

--- Check if sequence is complete.
---@return boolean True if finished
function apology_path.is_complete()
    return state.phase == PHASE_COMPLETE
end

--- Main update called from coordinator.update (like victory.update).
--- Handles phases that continue after player is freed from cinematic state.
---@param _dt number Delta time (unused)
function apology_path.update(_dt)
    if state.phase ~= PHASE_WAIT_COLLECT then
        return
    end

    if state.shard_prop and state.shard_prop.marked_for_destruction then
        apology_path.complete()
    end
end

--- Reset apology path state for level cleanup.
function apology_path.reset()
    state.started = false
    state.phase = PHASE_IDLE
    state.timer = 0
    state.player = nil
    state.door = nil
    state.valkyrie = nil
    state.fall_start_x = 0
    state.fall_start_y = 0
    state.fall_end_x = 0
    state.fall_end_y = 0
    state.jump_start_x = 0
    state.jump_start_y = 0
    state.jump_end_x = 0
    state.jump_end_y = 0
    state.jump_switched_to_fall = false
    state.shard_prop = nil
    state.shard_landed = false
    state.exit_start_x = 0
    state.exit_start_y = 0
    state.exit_end_y = 0
    state.exit_timer = 0
    camera_ref = nil
end

return apology_path
