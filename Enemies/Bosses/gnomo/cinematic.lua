--- Gnomo Boss Cinematic: Manages the intro sequence for the boss encounter.
--- Sequence: Stop -> music fades -> slow walk to position -> door closes -> "?" -> "!!" -> turn -> fight
local audio = require("audio")
local music = require("audio/music")
local Prop = require("Prop")
local Effects = require("Effects")
local coordinator = require("Enemies/Bosses/gnomo/coordinator")

-- Lazy-loaded to avoid circular dependency (platforms -> triggers -> registry -> gnomo -> cinematic)
local platforms

-- Cinematic phases
local PHASE_IDLE = 0
local PHASE_WAIT_MUSIC_FADE = 1
local PHASE_WALKING = 2
local PHASE_DOOR_CLOSING = 3
local PHASE_QUESTION = 4
local PHASE_EXCLAIM = 5
local PHASE_TURN = 6
local PHASE_START_FIGHT = 7

-- Movement constants
local CINEMATIC_WALK_SPEED_MULT = 0.5  -- Half normal speed for dramatic effect

-- Timing constants (seconds)
local DOOR_CLOSE_WAIT = 1.2    -- Wait for door animation
local QUESTION_DURATION = 1    -- Time before exclaim
local EXCLAIM_DURATION = 0.6   -- Time before turn
local TURN_DURATION = 0.4      -- Time before fight starts

local cinematic = {
    started = false,   -- Prevent re-triggering
    door = nil,        -- Cached door reference
    player = nil,      -- Cached player reference
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

    if phase == PHASE_DOOR_CLOSING and cinematic.timer >= DOOR_CLOSE_WAIT then
        advance_phase(PHASE_QUESTION)
        if player then
            Effects.create_text(player.x, player.y - 0.3, "?", "#FFFF00", 12)
            audio.play_huh()
        end
        return false
    end

    if phase == PHASE_QUESTION and cinematic.timer >= QUESTION_DURATION then
        advance_phase(PHASE_EXCLAIM)
        audio.play_exclamation()
        for _, enemy in pairs(coordinator.enemies) do
            if not enemy.marked_for_destruction then
                Effects.create_text(enemy.x, enemy.y - 0.3, "!!", "#FF0000", 12)
            end
        end
        return false
    end

    if phase == PHASE_EXCLAIM and cinematic.timer >= EXCLAIM_DURATION then
        advance_phase(PHASE_TURN)
        if player then
            player.direction = 1
            player.animation.flipped = 1
        end
        return false
    end

    if phase == PHASE_TURN and cinematic.timer >= TURN_DURATION then
        advance_phase(PHASE_START_FIGHT)
        coordinator.start(cinematic.player)
        return true
    end

    return false
end

--- Start the cinematic intro sequence.
--- Finds the player start position and door, then begins the walk sequence.
---@param player table The player instance
function cinematic.start(player)
    if cinematic.started then return end
    if coordinator.is_active() then return end

    cinematic.started = true
    cinematic.phase = PHASE_WAIT_MUSIC_FADE

    -- Fade out the level music as the cinematic begins
    music.fade_out(1)

    if not player then
        -- No player, skip cinematic and start boss directly
        coordinator.start()
        return
    end

    -- Cache player reference
    cinematic.player = player

    -- Lazy load platforms to avoid circular dependency
    platforms = platforms or require("platforms")

    -- Find the target position for the player
    local target_pos = platforms.spawn_points["gnomo_boss_player_start_position"]
    if not target_pos then
        -- No position defined, skip cinematic
        coordinator.start()
        return
    end

    -- Find the boss door
    cinematic.door = Prop.find_by_id("gnomo_boss_door")

    -- Set up the cinematic walk with wait and slow speed
    player.cinematic_target = { x = target_pos.x }
    player.cinematic_on_complete = cinematic.on_walk_complete
    player.cinematic_update = cinematic.update
    player.cinematic_can_move = cinematic.can_move
    player.cinematic_walk_speed = player:get_speed() * CINEMATIC_WALK_SPEED_MULT
    player:set_state(player.states.cinematic)
end

--- Check if the player can start moving toward the target.
--- Returns true once the music has faded out.
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
--- Begins the door closing phase.
function cinematic.on_walk_complete()
    -- Close the door if found
    if cinematic.door and not cinematic.door.marked_for_destruction then
        Prop.set_state(cinematic.door, "closing")
    end

    -- Player faces left (toward the door)
    local player = cinematic.player
    if player then
        player.direction = -1
        player.animation.flipped = -1
    end

    advance_phase(PHASE_DOOR_CLOSING)
end

--- Check if cinematic is currently active.
---@return boolean True if cinematic is running
function cinematic.is_active()
    return cinematic.phase ~= PHASE_IDLE and cinematic.phase ~= PHASE_START_FIGHT
end

--- Check if cinematic is in the music fade wait phase.
---@return boolean True if waiting for music to fade
function cinematic.is_waiting_for_music()
    return cinematic.phase == PHASE_WAIT_MUSIC_FADE
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
