--- Volume falloff functions for proximity audio
--- Each function takes t (0-1 interpolation factor) and returns volume multiplier (0-1)

local falloff = {}

--- Linear falloff: volume decreases linearly with distance
---@param t number Interpolation factor (0 at inner radius, 1 at outer radius)
---@return number Volume multiplier (0-1)
function falloff.linear(t)
    return 1 - t
end

--- Smooth falloff: cosine curve for smoother transitions at boundaries
---@param t number Interpolation factor (0 at inner radius, 1 at outer radius)
---@return number Volume multiplier (0-1)
function falloff.smooth(t)
    return (1 + math.cos(math.pi * t)) / 2
end

--- Exponential falloff: realistic sound attenuation
---@param t number Interpolation factor (0 at inner radius, 1 at outer radius)
---@return number Volume multiplier (0-1)
function falloff.exponential(t)
    return math.exp(-3 * t)
end

return falloff
