--- Valkyrie Boss Cinematic: Manages the intro sequence for the boss encounter.
--- Sequence: music fades -> slow walk to position -> turn left -> door closes -> "?" -> turn right -> fight
local audio = require("audio")
local music = require("audio/music")
local Prop = require("Prop")
local Effects = require("Effects")
local coordinator = require("Enemies/Bosses/valkyrie/coordinator")

-- Lazy-loaded to avoid circular dependency (platforms -> triggers -> registry -> valkyrie -> cinematic)
local platforms

-- Cinematic phases
local PHASE_IDLE = 0
local PHASE_WAIT_MUSIC_FADE = 1
local PHASE_WALKING = 2
local PHASE_TURN_TO_DOOR = 3
local PHASE_DOOR_CLOSING = 4
local PHASE_QUESTION = 5
local PHASE_TURN_TO_BOSS = 6
local PHASE_START_FIGHT = 7

-- Movement constants
local CINEMATIC_WALK_SPEED_MULT = 0.5

-- Timing constants (seconds)
local TURN_TO_DOOR_DURATION = 0.3
local DOOR_CLOSE_WAIT = 1.2
local QUESTION_DURATION = 1
local TURN_TO_BOSS_DURATION = 0.4

local cinematic = {
    started = false,
    door = nil,
    player = nil,
    phase = PHASE_IDLE,
    timer = 0,
}

--- Advance to the next cinematic phase and reset timer.
---@param next_phase number Phase constant to transition to
local function advance_phase(next_phase)
    cinematic.phase = next_phase
    cinematic.timer = 0
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
        advance_phase(PHASE_TURN_TO_BOSS)
        if player then
            player.direction = 1
            player.animation.flipped = 1
        end
        return false
    end

    if phase == PHASE_TURN_TO_BOSS and cinematic.timer >= TURN_TO_BOSS_DURATION then
        advance_phase(PHASE_START_FIGHT)
        coordinator.start(cinematic.player)
        return true
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
end

return cinematic
