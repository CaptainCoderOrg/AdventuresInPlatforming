--- Playtime module: Tracks total time played for the current session
local Playtime = {}

-- Current playtime in seconds
local elapsed = 0

-- Whether playtime tracking is active
local is_paused = false

--- Reset playtime to 0
function Playtime.reset()
    elapsed = 0
end

--- Set playtime to a specific value (for loading from save)
---@param seconds number Playtime in seconds
function Playtime.set(seconds)
    elapsed = seconds or 0
end

--- Get current playtime in seconds
---@return number seconds Total seconds played
function Playtime.get()
    return elapsed
end

--- Update playtime (call each frame when gameplay is active)
---@param dt number Delta time in seconds
function Playtime.update(dt)
    if not is_paused then
        elapsed = elapsed + dt
    end
end

--- Pause playtime tracking
function Playtime.pause()
    is_paused = true
end

--- Resume playtime tracking
function Playtime.resume()
    is_paused = false
end

--- Check if playtime tracking is paused
---@return boolean paused True if paused
function Playtime.is_paused()
    return is_paused
end

return Playtime
