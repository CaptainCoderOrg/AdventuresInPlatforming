--- Cinematic state: Player walks automatically to a target position with controls locked.
--- Used for boss intro sequences and scripted moments.
--- Target: player.cinematic_target = { x = number }
--- Options:
---   player.cinematic_walk_speed = number (optional custom walk speed, defaults to player:get_speed())
--- Callbacks:
---   player.cinematic_can_move = function() -> boolean (optional, called each frame until returns true)
---   player.cinematic_on_complete = function() (called when walk finishes)
---   player.cinematic_update = function(dt) -> boolean (called each frame after walk, returns true when done)
local Animation = require('Animation')
local common = require('player.common')

local cinematic = { name = "cinematic" }

-- Tolerance for arrival detection (in tiles)
local ARRIVAL_TOLERANCE = 0.1

--- Clears all cinematic-related properties from the player.
---@param player table The player object
local function clear_cinematic_properties(player)
    player.cinematic_target = nil
    player.cinematic_on_complete = nil
    player.cinematic_update = nil
    player.cinematic_can_move = nil
    player.cinematic_walk_speed = nil
end

--- Called when entering cinematic state. Sets idle animation initially, zeroes velocity.
---@param player table The player object
function cinematic.start(player)
    player.animation = Animation.new(common.animations.IDLE)
    player.vx = 0
    player.vy = 0
    player._cinematic_walking = true   -- Track if still in walking phase
    player._cinematic_move_started = false  -- Track if actually moving yet
    common.reset_footsteps(player)
end

--- Handles input while in cinematic state. Controls are locked (no-op).
---@param _player table The player object (unused)
function cinematic.input(_player)
    -- Controls locked during cinematic
end

--- Updates cinematic state. Walks toward target position, then waits for cinematic to complete.
---@param player table The player object
---@param dt number Delta time
function cinematic.update(player, dt)
    -- Walking phase
    if player._cinematic_walking then
        local target = player.cinematic_target
        if not target then
            -- No target set, return to idle
            player._cinematic_walking = false
            player:set_state(player.states.idle)
            return
        end

        -- Check if we should wait before starting to move
        if not player._cinematic_move_started then
            if player.cinematic_can_move then
                if not player.cinematic_can_move() then
                    -- Still waiting, stay in idle
                    common.apply_gravity(player, dt)
                    return
                end
            end
            -- Ready to move, switch to run animation
            player._cinematic_move_started = true
            player.animation = Animation.new(common.animations.RUN)
            common.reset_footsteps(player)
        end

        local dx = target.x - player.x
        local distance = math.abs(dx)

        -- Check if arrived at target
        if distance < ARRIVAL_TOLERANCE then
            player.vx = 0
            player._cinematic_walking = false

            -- Switch to idle animation for waiting phase
            player.animation = Animation.new(common.animations.IDLE)

            -- Call completion callback if set
            if player.cinematic_on_complete then
                player.cinematic_on_complete()
            end

            -- If no update callback, exit cinematic immediately
            if not player.cinematic_update then
                clear_cinematic_properties(player)
                player:set_state(player.states.idle)
            end
            return
        end

        -- Walk toward target (use custom speed if set)
        local speed = player.cinematic_walk_speed or player:get_speed()
        if dx > 0 then
            player.direction = 1
            player.vx = speed
        else
            player.direction = -1
            player.vx = -speed
        end

        -- Play footstep sounds while walking
        common.update_footsteps(player, dt)

        -- Apply gravity (but don't transition to air state)
        common.apply_gravity(player, dt)
    else
        -- Waiting phase - call cinematic update callback
        if player.cinematic_update then
            local done = player.cinematic_update(dt)
            if done then
                clear_cinematic_properties(player)
                player:set_state(player.states.idle)
            end
        else
            player:set_state(player.states.idle)
        end

        -- Apply gravity during waiting phase too
        common.apply_gravity(player, dt)
    end
end

--- Renders the player.
---@param player table The player object
function cinematic.draw(player)
    common.draw(player)
end

return cinematic
