--- Screen fade utility for level transitions
local canvas = require("canvas")

local screen_fade = {}

local STATE = {
    IDLE = "idle",
    FADING_OUT = "fading_out",
    HOLDING = "holding",
    FADING_IN = "fading_in",
}

-- Configuration
local FADE_OUT_DURATION = 0.3
local HOLD_DURATION = 0.1
local FADE_IN_DURATION = 0.3

-- State
local state = STATE.IDLE
local fade_progress = 0
local on_black_callback = nil

--- Start a fade out -> callback -> fade in sequence
---@param callback function Called when screen is fully black
function screen_fade.start(callback)
    if state ~= STATE.IDLE then return end
    state = STATE.FADING_OUT
    fade_progress = 0
    on_black_callback = callback
end

--- Check if a fade is currently active
---@return boolean True if fading
function screen_fade.is_active()
    return state ~= STATE.IDLE
end

--- Update fade animation
---@param dt number Delta time in seconds
function screen_fade.update(dt)
    if state == STATE.IDLE then return end

    if state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.HOLDING
        end
    elseif state == STATE.HOLDING then
        fade_progress = fade_progress + dt / HOLD_DURATION
        if fade_progress >= 1 then
            -- Execute callback while screen is black
            if on_black_callback then
                on_black_callback()
                on_black_callback = nil
            end
            fade_progress = 0
            state = STATE.FADING_IN
        end
    elseif state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.IDLE
        end
    end
end

--- Calculate alpha for current state
---@return number alpha Value between 0 and 1
local function get_alpha()
    if state == STATE.FADING_OUT then
        return fade_progress
    elseif state == STATE.HOLDING then
        return 1
    elseif state == STATE.FADING_IN then
        return 1 - fade_progress
    else
        return 0
    end
end

--- Draw the fade overlay (call after all other drawing)
function screen_fade.draw()
    if state == STATE.IDLE then return end

    local alpha = get_alpha()
    canvas.set_global_alpha(alpha)
    canvas.set_color("#000000")
    canvas.fill_rect(0, 0, canvas.get_width(), canvas.get_height())
    canvas.set_global_alpha(1)
end

return screen_fade
