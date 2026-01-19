--- Spike trap prop that damages the player and teleports them to their last safe position
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local Animation = require("Animation")

local SpikeTrap = {}
SpikeTrap.all = {}  -- Object pool

-- Default timing for alternating mode
local DEFAULT_EXTEND_TIME = 1.5
local DEFAULT_RETRACT_TIME = 1.5

-- State constants
local STATE = {
    EXTENDED = "extended",
    RETRACTING = "retracting",
    RETRACTED = "retracted",
    EXTENDING = "extending",
}

-- Animation definition: 6 frames, 16x16
local SPIKE_ANIM = Animation.create_definition(sprites.environment.spikes, 6, {
    ms_per_frame = 100,
    width = 16,
    height = 16,
    loop = false
})

-- Hitbox dimensions (1 wide, 0.8 tall, anchored at bottom of tile)
local HITBOX_W = 1
local HITBOX_H = 0.8

--- Check if player is touching a spike trap (overlapping bounding boxes)
---@param trap table SpikeTrap instance
---@param player table Player instance
---@return boolean True if player overlaps trap tile
local function player_touching(trap, player)
    local px, py = player.x + player.box.x, player.y + player.box.y
    local pw, ph = player.box.w, player.box.h
    local sx = trap.x
    local sy = trap.y + (1 - HITBOX_H)

    return px < sx + HITBOX_W and px + pw > sx and
           py < sy + HITBOX_H and py + ph > sy
end

--- Start animation transition (EXTENDED -> RETRACTING, RETRACTED -> EXTENDING)
---@param trap table SpikeTrap instance
---@param next_state string State to transition to
---@param anim_options table Animation options (start_frame, reverse)
local function start_transition(trap, next_state, anim_options)
    trap.state = next_state
    trap.animation = Animation.new(SPIKE_ANIM, anim_options)
end

--- Finish animation transition (RETRACTING -> RETRACTED, EXTENDING -> EXTENDED)
---@param trap table SpikeTrap instance
---@param next_state string State to transition to
local function finish_transition(trap, next_state)
    trap.state = next_state
    trap.timer = 0
    trap.animation:pause()
end

--- Create a new spike trap at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param options table|nil Optional configuration: mode, extend_time, retract_time, start_retracted
---@return table SpikeTrap instance
function SpikeTrap.new(x, y, options)
    options = options or {}

    local start_retracted = options.start_retracted or false
    local initial_state = start_retracted and STATE.RETRACTED or STATE.EXTENDED
    local initial_frame = start_retracted and 5 or 0

    local self = {
        x = x,
        y = y,
        mode = options.mode or "static",
        extend_time = options.extend_time or DEFAULT_EXTEND_TIME,
        retract_time = options.retract_time or DEFAULT_RETRACT_TIME,
        state = initial_state,
        timer = 0,
        animation = Animation.new(SPIKE_ANIM, { start_frame = initial_frame }),
        group = options.group,  -- Optional group name for retract_group()
    }
    -- Pause animation for static states (EXTENDED or RETRACTED)
    self.animation:pause()

    table.insert(SpikeTrap.all, self)
    return self
end

--- Update all spike traps (check player overlap and apply damage/teleport)
---@param dt number Delta time in seconds
---@param player table Player instance
function SpikeTrap.update(dt, player)
    for _, trap in ipairs(SpikeTrap.all) do
        -- Update animation
        trap.animation:play(dt)

        -- State machine logic for alternating mode
        if trap.mode == "alternating" then
            if trap.state == STATE.EXTENDED then
                trap.timer = trap.timer + dt
                if trap.timer >= trap.extend_time then
                    start_transition(trap, STATE.RETRACTING, { start_frame = 0 })
                end
            elseif trap.state == STATE.RETRACTING then
                if trap.animation:is_finished() then
                    finish_transition(trap, STATE.RETRACTED)
                end
            elseif trap.state == STATE.RETRACTED then
                trap.timer = trap.timer + dt
                if trap.timer >= trap.retract_time then
                    start_transition(trap, STATE.EXTENDING, { start_frame = 5, reverse = true })
                end
            elseif trap.state == STATE.EXTENDING then
                if trap.animation:is_finished() then
                    finish_transition(trap, STATE.EXTENDED)
                end
            end
        end

        -- Damage check (only when extended or extending)
        local is_dangerous = trap.state == STATE.EXTENDED or trap.state == STATE.EXTENDING
        if is_dangerous and player_touching(trap, player) and not player:is_invincible() and player:health() > 0 then
            player:take_damage(1)
        end
    end
end

--- Renders all spike traps to the screen.
--- Converts tile coordinates to screen pixels and draws debug hitboxes when enabled.
function SpikeTrap.draw()
    local tile_size = sprites.tile_size

    for _, trap in ipairs(SpikeTrap.all) do
        local screen_x = trap.x * tile_size
        local screen_y = trap.y * tile_size
        trap.animation:draw(screen_x, screen_y)

        if config.bounding_boxes then
            canvas.set_color("#FF00FF")  -- Magenta for spike traps
            local hitbox_x = screen_x
            local hitbox_y = screen_y + (1 - HITBOX_H) * tile_size
            canvas.draw_rect(hitbox_x, hitbox_y, HITBOX_W * tile_size, HITBOX_H * tile_size)
        end
    end
end

--- Remove all spike traps (for level reload)
function SpikeTrap.clear()
    SpikeTrap.all = {}
end

--- Retract all spike traps in a specific group.
--- Affects traps in EXTENDED or EXTENDING states.
---@param group_name string Group to target
function SpikeTrap.retract_group(group_name)
    for _, trap in ipairs(SpikeTrap.all) do
        if trap.group == group_name and
           (trap.state == STATE.EXTENDED or trap.state == STATE.EXTENDING) then
            start_transition(trap, STATE.RETRACTING, { start_frame = 0 })
        end
    end
end

return SpikeTrap
