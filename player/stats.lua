--- Stat calculation utilities for player progression
local stats = {}

local DEFAULT_PERCENT_PER_POINT = 2.5
local MAX_POINTS = 20

-- Per-stat progression curves (diminishing returns)
local STAT_TIERS = {
    default = { 5, 5, 4, 4, 3, 3 },
    critical = { 5, 4, 3, 2.5 },
    defence = { 5, 5, 5, 3, 3, 3, 3, 3, 2.5 },
    recovery = { 5, 5, 5, 5, 5, 2.5 },
}

-- Pre-compute cumulative sums for O(1) lookup
local CUMULATIVE = {}
for stat_type, tiers in pairs(STAT_TIERS) do
    CUMULATIVE[stat_type] = { [0] = 0 }
    local sum = 0
    for i = 1, MAX_POINTS do
        sum = sum + (tiers[i] or DEFAULT_PERCENT_PER_POINT)
        CUMULATIVE[stat_type][i] = sum
    end
end

--- Calculates total stat percentage for a given number of points using diminishing returns.
---@param points number Number of stat points invested
---@param stat_type string|nil Stat name for per-stat curves (nil uses default)
---@return number Total percentage bonus
function stats.calculate_percent(points, stat_type)
    local cumulative = CUMULATIVE[stat_type] or CUMULATIVE.default
    if points <= 0 then return 0 end
    if points > MAX_POINTS then
        -- Beyond pre-computed range: use last value + default for extra points
        return cumulative[MAX_POINTS] + (points - MAX_POINTS) * DEFAULT_PERCENT_PER_POINT
    end
    return cumulative[points]
end

return stats
