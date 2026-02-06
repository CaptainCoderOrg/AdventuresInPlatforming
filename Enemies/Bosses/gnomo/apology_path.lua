--- Gnomo Boss Apology Path: Peaceful resolution when player has adept_apology item.
--- Completely separate from the boss coordinator to avoid state bugs.
--- Sequence: intro cinematic -> green descends -> dialogue -> axe up -> gnomos exit -> axe down -> collect
local audio = require("audio")
local music = require("audio/music")
local Effects = require("Effects")
local Prop = require("Prop")
local common = require("Enemies/Bosses/gnomo/common")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")
local dialogue_manager = require("dialogue/manager")
local dialogue_screen = require("ui/dialogue_screen")

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
local PHASE_EXCLAIM = 5
local PHASE_TURN = 6
local PHASE_GREEN_DESCENDS = 7
local PHASE_DIALOGUE = 8
local PHASE_AXE_UP = 9
local PHASE_GNOMOS_EXIT = 10
local PHASE_AXE_DOWN = 11
local PHASE_WAIT_COLLECT = 12
local PHASE_COMPLETE = 13

-- Timing constants (seconds)
local DOOR_CLOSE_WAIT = 1.2
local QUESTION_DURATION = 1
local EXCLAIM_DURATION = 0.6
local TURN_DURATION = 0.4
local DESCENT_DURATION = 0.8
local JUMP_EXIT_DURATION = 0.5
local LEAVE_BOTTOM_DURATION = 0.3

-- Movement constants
local CINEMATIC_WALK_SPEED_MULT = 0.5

-- State
local state = {
    started = false,
    phase = PHASE_IDLE,
    timer = 0,
    player = nil,
    door = nil,
    -- Green gnomo descent
    green_gnomo = nil,
    descent_start_x = 0,
    descent_start_y = 0,
    descent_end_x = 0,
    descent_end_y = 0,
    -- Axe tracking
    axe_prop = nil,
    waypoint_x = 0,
    waypoint_y = 0,
    drop_x = 0,
    drop_y = 0,
    -- Exit tracking
    exit_timers = {},  -- color -> timer
    exit_start_positions = {},  -- color -> {x, y}
    exit_end_positions = {},  -- color -> {x, y}
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

--- Get spawn point position by ID.
---@param id string Spawn point ID
---@return number|nil x, number|nil y Position in tiles
local function get_marker_position(id)
    local plat = get_platforms()
    local point = plat.spawn_points[id]
    if point then
        return point.x, point.y
    end
    return nil, nil
end

--- Find the green gnomo from coordinator's registered enemies.
---@return table|nil green_gnomo The green gnomo instance
local function find_green_gnomo()
    return coordinator.enemies["green"]
end

--- Make all gnomos invulnerable and freeze them.
local function freeze_all_gnomos()
    for _, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction then
            gnomo.invulnerable = true
            gnomo.vx = 0
            gnomo.vy = 0
            gnomo.gravity = 0
        end
    end
end

--- Set up descent animation for green gnomo.
local function setup_green_descent()
    state.green_gnomo = find_green_gnomo()
    if not state.green_gnomo then return end

    -- Start position: platform_0
    local start_x, start_y = get_marker_position("gnomo_boss_platform_0")
    state.descent_start_x = start_x or state.green_gnomo.x
    state.descent_start_y = start_y or state.green_gnomo.y

    -- End position: near exit_bottom_right
    local end_x, end_y = get_marker_position("gnomo_boss_exit_bottom_right")
    state.descent_end_x = end_x or state.descent_start_x
    state.descent_end_y = end_y or state.descent_start_y

    -- Position green gnomo at start
    state.green_gnomo.x = state.descent_start_x
    state.green_gnomo.y = state.descent_start_y
    state.green_gnomo.alpha = 1

    -- Make intangible during descent
    if not state.green_gnomo._intangible_shape then
        common.make_intangible(state.green_gnomo)
    end

    -- Set to jump animation (upward frame)
    local enemy_common = require("Enemies/common")
    enemy_common.set_animation(state.green_gnomo, state.green_gnomo.animations.JUMP)
    common.set_jump_frame_range(state.green_gnomo, common.FRAME_UPWARD_START, common.FRAME_UPWARD_END)

    -- Face left (toward player)
    common.set_direction(state.green_gnomo, -1)
end

--- Update green gnomo descent animation.
---@param progress number Progress 0-1
local function update_green_descent(progress)
    if not state.green_gnomo then return end

    local eased = common.smoothstep(progress)

    -- Parabolic arc for Y (jump up then down)
    local arc_height = 2  -- tiles
    local arc = 4 * arc_height * progress * (1 - progress)

    state.green_gnomo.x = common.lerp(state.descent_start_x, state.descent_end_x, eased)
    state.green_gnomo.y = common.lerp(state.descent_start_y, state.descent_end_y, eased) - arc

    -- Switch animation frame based on progress
    if progress < 0.5 then
        common.set_jump_frame_range(state.green_gnomo, common.FRAME_UPWARD_START, common.FRAME_UPWARD_END)
    else
        common.set_jump_frame_range(state.green_gnomo, common.FRAME_DOWNWARD_START, common.FRAME_DOWNWARD_END)
    end
end

-- Minimal exit state that uses alpha-aware drawing
local exit_state = {
    name = "apology_exit",
    start = common.noop,
    update = common.noop,
    draw = common.draw_with_alpha,
}

--- Set up exit animations for all gnomos.
local function setup_gnomo_exits()
    state.exit_timers = {}
    state.exit_start_positions = {}
    state.exit_end_positions = {}

    local stagger = 0
    for color, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction then
            state.exit_timers[color] = -stagger  -- Negative = delayed start
            state.exit_start_positions[color] = { x = gnomo.x, y = gnomo.y }

            if color == "green" then
                -- Green exits right (leave_bottom style)
                state.exit_end_positions[color] = {
                    x = gnomo.x + common.BOTTOM_OFFSET_X,
                    y = gnomo.y,
                }
                -- Face right
                common.set_direction(gnomo, 1)
                local enemy_common = require("Enemies/common")
                enemy_common.set_animation(gnomo, gnomo.animations.RUN)
            else
                -- Others jump to nearest hole
                local hole_index = common.find_nearest_hole(gnomo)
                local hole_id = common.HOLE_IDS[hole_index]
                local hx, hy = get_marker_position(hole_id)
                state.exit_end_positions[color] = {
                    x = hx or gnomo.x,
                    y = hy or gnomo.y,
                }
                local enemy_common = require("Enemies/common")
                enemy_common.set_animation(gnomo, gnomo.animations.JUMP)
                common.set_jump_frame_range(gnomo, common.FRAME_UPWARD_START, common.FRAME_UPWARD_END)
            end

            -- Make intangible
            if not gnomo._intangible_shape then
                common.make_intangible(gnomo)
            end

            -- Set to exit state for alpha-aware drawing
            gnomo.state = exit_state

            stagger = stagger + 0.15
        end
    end
end

--- Update gnomo exit animations.
---@param dt number Delta time
---@return boolean all_done True if all exits complete
local function update_gnomo_exits(dt)
    local all_done = true

    for color, gnomo in pairs(coordinator.enemies) do
        if not gnomo.marked_for_destruction and state.exit_timers[color] then
            state.exit_timers[color] = state.exit_timers[color] + dt

            local timer = state.exit_timers[color]
            if timer < 0 then
                -- Still waiting to start
                all_done = false
            else
                local duration = color == "green" and LEAVE_BOTTOM_DURATION or JUMP_EXIT_DURATION
                local progress = math.min(1, timer / duration)
                local eased = common.smoothstep(progress)

                local start_pos = state.exit_start_positions[color]
                local end_pos = state.exit_end_positions[color]

                gnomo.x = common.lerp(start_pos.x, end_pos.x, eased)
                gnomo.y = common.lerp(start_pos.y, end_pos.y, eased)

                -- Fade based on exit style
                local fade_start = color == "green" and 0 or 0.6
                if progress >= fade_start then
                    local fade_progress = (progress - fade_start) / (1 - fade_start)
                    gnomo.alpha = 1 - fade_progress
                end

                if progress < 1 then
                    all_done = false
                else
                    gnomo.alpha = 0
                    gnomo.marked_for_destruction = true
                end
            end
        end
    end

    return all_done
end

--- Cinematic update callback (called via player.cinematic_update).
--- Returns true when cinematic portion is complete and player should be freed.
---@param dt number Delta time in seconds
---@return boolean done True if player should exit cinematic state
local function cinematic_update(dt)
    if state.phase == PHASE_IDLE or state.phase == PHASE_WALKING then
        return false
    end

    state.timer = state.timer + dt
    local player = state.player

    -- Phase: Door closing
    if state.phase == PHASE_DOOR_CLOSING and state.timer >= DOOR_CLOSE_WAIT then
        advance_phase(PHASE_QUESTION)
        if player then
            Effects.create_text(player.x, player.y - 0.3, "?", "#FFFF00", 12)
            audio.play_huh()
        end
        return false
    end

    -- Phase: Question mark shown
    if state.phase == PHASE_QUESTION and state.timer >= QUESTION_DURATION then
        advance_phase(PHASE_EXCLAIM)
        audio.play_exclamation()
        for _, enemy in pairs(coordinator.enemies) do
            if not enemy.marked_for_destruction then
                Effects.create_text(enemy.x, enemy.y - 0.3, "!!", "#FF0000", 12)
            end
        end
        return false
    end

    -- Phase: Exclamation shown
    if state.phase == PHASE_EXCLAIM and state.timer >= EXCLAIM_DURATION then
        advance_phase(PHASE_TURN)
        if player then
            player.direction = 1
            player.animation.flipped = 1
        end
        return false
    end

    -- Phase: Player turns
    if state.phase == PHASE_TURN and state.timer >= TURN_DURATION then
        advance_phase(PHASE_GREEN_DESCENDS)
        setup_green_descent()
        return false
    end

    -- Phase: Green gnomo descends
    if state.phase == PHASE_GREEN_DESCENDS then
        local progress = math.min(1, state.timer / DESCENT_DURATION)
        update_green_descent(progress)

        if progress >= 1 then
            advance_phase(PHASE_DIALOGUE)
            -- Restore tangible for dialogue (but still invulnerable)
            if state.green_gnomo and state.green_gnomo._intangible_shape then
                common.restore_tangible(state.green_gnomo)
                state.green_gnomo.invulnerable = true
            end
            -- Start dialogue screen
            if camera_ref then
                dialogue_screen.start("gnomo_apology", state.player, camera_ref)
            end
        end
        return false
    end

    -- Phase: Dialogue
    if state.phase == PHASE_DIALOGUE then
        -- Wait for dialogue_screen to finish
        if not dialogue_screen.is_active() then
            apology_path.start_axe_sequence()
        end
        return false
    end

    -- Phase: Axe flying up to waypoint
    if state.phase == PHASE_AXE_UP then
        -- Flying axe handles itself via Effects, we wait for callback
        return false
    end

    -- Phase: Gnomos exiting
    if state.phase == PHASE_GNOMOS_EXIT then
        local all_done = update_gnomo_exits(dt)
        if all_done then
            advance_phase(PHASE_AXE_DOWN)
            -- Start axe descent
            Effects.create_flying_axe(state.waypoint_x, state.waypoint_y,
                state.drop_x, state.drop_y, apology_path.on_axe_landed)
        end
        return false
    end

    -- Phase: Axe falling to drop location
    if state.phase == PHASE_AXE_DOWN then
        -- Flying axe handles itself
        return false
    end

    -- Phase: Waiting for player to collect axe
    if state.phase == PHASE_WAIT_COLLECT then
        if state.axe_prop and state.axe_prop.marked_for_destruction then
            apology_path.complete()
            return true
        end
        return false
    end

    return state.phase == PHASE_COMPLETE
end

--- Set references for dialogue screen.
--- Called from main.lua when loading a level.
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

    -- Fade out level music
    music.fade_out(1)

    if not player then
        -- Skip to completion if no player
        apology_path.complete()
        return
    end

    -- Lazy load platforms
    platforms = get_platforms()

    -- Find target position
    local target_pos = platforms.spawn_points["gnomo_boss_player_start_position"]
    if not target_pos then
        apology_path.complete()
        return
    end

    -- Find the boss door
    state.door = Prop.find_by_id("gnomo_boss_door")

    -- Freeze all gnomos immediately
    freeze_all_gnomos()

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

--- Start the axe flight sequence after dialogue.
function apology_path.start_axe_sequence()
    -- Get waypoint and drop positions
    local waypoint_x, waypoint_y = get_marker_position("gnomo_boss_axe_target")
    local drop_x, drop_y = get_marker_position("gnomo_boss_axe_drop")

    if waypoint_x and waypoint_y then
        state.waypoint_x = waypoint_x
        state.waypoint_y = waypoint_y
    else
        state.waypoint_x = state.green_gnomo and (state.green_gnomo.x + 2) or 0
        state.waypoint_y = state.green_gnomo and (state.green_gnomo.y - 3) or 0
    end

    if drop_x and drop_y then
        state.drop_x = drop_x
        state.drop_y = drop_y
    else
        state.drop_x = state.waypoint_x
        state.drop_y = state.waypoint_y + 5
    end

    -- Spawn flying axe from green gnomo to waypoint
    local start_x = state.green_gnomo and (state.green_gnomo.x + 0.5) or state.waypoint_x
    local start_y = state.green_gnomo and state.green_gnomo.y or state.waypoint_y

    advance_phase(PHASE_AXE_UP)
    Effects.create_flying_axe(start_x, start_y, state.waypoint_x, state.waypoint_y, apology_path.on_axe_reached_waypoint)
end

--- Called when axe reaches waypoint.
function apology_path.on_axe_reached_waypoint()
    advance_phase(PHASE_GNOMOS_EXIT)
    setup_gnomo_exits()
end

--- Called when axe lands at drop location.
function apology_path.on_axe_landed()
    -- Spawn the throwing_axe unique item
    state.axe_prop = Prop.spawn("unique_item", state.drop_x, state.drop_y, { item_id = "throwing_axe" })
    advance_phase(PHASE_WAIT_COLLECT)

    -- Free player movement (exit cinematic state)
    if state.player then
        state.player:set_state(state.player.states.idle)
    end
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
            if item == "adept_apology" then
                table.remove(player.unique_items, i)
                break
            end
        end
    end

    -- Set flag for quest completion
    dialogue_manager.set_flag("apology_delivered_to_gnomos")

    -- Journal: record apology delivery
    if player and player.journal then
        player.journal["apology_delivered"] = player.journal["apology_delivered"] or "active"
    end

    -- Open the door
    local door = Prop.find_by_id("gnomo_boss_door")
    if door and not door.marked_for_destruction then
        Prop.set_state(door, "opening")
    end

    -- Mark all gnomos for destruction
    for _, gnomo in pairs(coordinator.enemies) do
        gnomo.marked_for_destruction = true
    end

    state.phase = PHASE_COMPLETE
end

--- Draw function (dialogue is handled by dialogue_screen).
function apology_path.draw()
    -- Dialogue rendering is handled by dialogue_screen via hud.draw()
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

--- Main update called from main.lua tick (like victory.update).
--- Handles phases that continue after player is freed from cinematic state.
---@param _dt number Delta time (unused)
function apology_path.update(_dt)
    -- Only handle PHASE_WAIT_COLLECT - player is free but we watch for axe collection
    if state.phase ~= PHASE_WAIT_COLLECT then
        return
    end

    if state.axe_prop and state.axe_prop.marked_for_destruction then
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
    state.green_gnomo = nil
    state.descent_start_x = 0
    state.descent_start_y = 0
    state.descent_end_x = 0
    state.descent_end_y = 0
    state.axe_prop = nil
    state.waypoint_x = 0
    state.waypoint_y = 0
    state.drop_x = 0
    state.drop_y = 0
    state.exit_timers = {}
    state.exit_start_positions = {}
    state.exit_end_positions = {}
    camera_ref = nil
end

return apology_path
