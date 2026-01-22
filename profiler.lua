local HISTORY_SIZE = 1800  -- 30 seconds at 60 fps

-- Frame budget thresholds (milliseconds per frame)
local BUDGET_60FPS = 16.67  -- 60 fps target
local BUDGET_30FPS = 33.33  -- 30 fps minimum
local SIGNIFICANT_MS = 0.5  -- Sections below this threshold are omitted from warnings

-- Module-level reusable tables to avoid per-frame allocations
local cached_results = {}
local cached_result_entries = {}  -- Pool of reusable entry tables
local result_sort_fn = function(a, b) return a.max > b.max end
local cached_samples = {}
local warning_details = {}

local profiler = {
    enabled = false,
    sections = {},      -- { name = { elapsed = 0, calls = 0, parent = nil, max = 0 } }
    frame_start = 0,
    frame_total = 0,
    _start_times = {},  -- Temporary storage for in-progress sections
    _section_stack = {}, -- Stack of active section names for hierarchy tracking
    -- Frame time history for graph
    history = {},           -- Circular buffer of frame times
    history_index = 1,      -- Current write position
    history_count = 0,      -- Number of samples stored (up to HISTORY_SIZE)
    _skip_frame = false,    -- Skip first frame after enabling (initialization spike)
}

--- Get current time in milliseconds
--- Uses os.clock() which returns CPU time in seconds (wasmoon/Lua 5.4)
--- Multiply by 1000 to get milliseconds
local function get_time_ms()
    return os.clock() * 1000
end

--- Call at frame start to reset per-frame timing stats
---@return nil
function profiler.begin_frame()
    if not profiler.enabled then return end
    profiler.frame_start = get_time_ms()

    for _, section in pairs(profiler.sections) do
        section.elapsed = 0
        section.calls = 0
    end
end

--- Start timing a named section
---@param name string Section name to start timing
function profiler.start(name)
    if not profiler.enabled then return end
    profiler._start_times[name] = get_time_ms()

    -- Track parent from current stack
    local parent = profiler._section_stack[#profiler._section_stack]
    if not profiler.sections[name] then
        profiler.sections[name] = { elapsed = 0, calls = 0, parent = parent, max = 0 }
    end

    table.insert(profiler._section_stack, name)
end

--- Stop timing a named section
---@param name string Section name to stop timing
function profiler.stop(name)
    if not profiler.enabled then return end
    local start = profiler._start_times[name]
    if not start then return end

    local elapsed = get_time_ms() - start
    local section = profiler.sections[name]

    section.elapsed = section.elapsed + elapsed
    section.calls = section.calls + 1
    profiler._start_times[name] = nil

    if section.elapsed > section.max then
        section.max = section.elapsed
    end

    if profiler._section_stack[#profiler._section_stack] == name then
        table.remove(profiler._section_stack)
    end
end

--- Call at frame end to finalize timing and store in history
---@return nil
function profiler.end_frame()
    if not profiler.enabled then return end
    profiler.frame_total = get_time_ms() - profiler.frame_start

    -- Skip frame if flagged (after enabling or after printing warning)
    if profiler._skip_frame then
        profiler._skip_frame = false
        return
    end

    -- Log warning for frames above 60fps budget
    if profiler.frame_total > BUDGET_60FPS then
        -- Clear warning_details by truncating
        for i = 1, #warning_details do warning_details[i] = nil end
        -- Build details from sections sorted by elapsed time
        for name, data in pairs(profiler.sections) do
            if data.elapsed > SIGNIFICANT_MS then
                warning_details[#warning_details + 1] = string.format("%s:%.1fms", name, data.elapsed)
            end
        end
        table.sort(warning_details)
        local details_str = #warning_details > 0 and table.concat(warning_details, ", ") or "no section data"
        print(string.format("\27[33m[PROFILER] FRAME TOOK %.2fms - %s\27[0m", profiler.frame_total, details_str))
        profiler._skip_frame = true  -- Skip next frame (printing is expensive)
    end

    profiler.history[profiler.history_index] = profiler.frame_total
    profiler.history_index = (profiler.history_index % HISTORY_SIZE) + 1
    if profiler.history_count < HISTORY_SIZE then
        profiler.history_count = profiler.history_count + 1
    end
end

--- Get sorted results for display
---@return table results Sorted list of { name, elapsed, calls, parent, max }
---@return number frame_total Total frame time in ms
function profiler.get_results()
    -- Clear cached_results by truncating
    for i = 1, #cached_results do cached_results[i] = nil end

    local count = 0
    for name, data in pairs(profiler.sections) do
        count = count + 1
        -- Reuse or create entry table from pool
        local entry = cached_result_entries[count]
        if not entry then
            entry = {}
            cached_result_entries[count] = entry
        end
        entry.name = name
        entry.elapsed = data.elapsed
        entry.calls = data.calls
        entry.parent = data.parent
        entry.max = data.max
        cached_results[count] = entry
    end
    -- Sort by max time (highest first) for stable ordering
    table.sort(cached_results, result_sort_fn)
    return cached_results, profiler.frame_total
end

--- Get frame time history for graph display (max of every 2 frames)
---@return table samples Array of frame times, oldest to newest
---@return number max_value Maximum frame time in the history
function profiler.get_history()
    -- Clear cached_samples by truncating
    for i = 1, #cached_samples do cached_samples[i] = nil end

    if profiler.history_count == 0 then
        return cached_samples, 0
    end

    local max_val = 0

    -- Oldest entry: when buffer is full, it's at the write position; otherwise start at 1
    local oldest = profiler.history_count < HISTORY_SIZE and 1 or profiler.history_index

    -- Downsample by taking max of every 2 frames
    for i = 0, profiler.history_count - 1, 2 do
        local idx1 = ((oldest - 1 + i) % HISTORY_SIZE) + 1
        local val1 = profiler.history[idx1] or 0
        local val2 = 0

        -- Include second frame if it exists
        if i + 1 < profiler.history_count then
            local idx2 = ((oldest + i) % HISTORY_SIZE) + 1
            val2 = profiler.history[idx2] or 0
        end

        local bucket_max = math.max(val1, val2)
        cached_samples[#cached_samples + 1] = bucket_max
        max_val = math.max(max_val, bucket_max)
    end

    return cached_samples, max_val
end

--- Toggle profiler on/off and reset history when enabling
---@return nil
function profiler.toggle()
    profiler.enabled = not profiler.enabled
    if profiler.enabled then
        profiler.sections = {}
        profiler._start_times = {}
        profiler._section_stack = {}
        profiler.history = {}
        profiler.history_index = 1
        profiler.history_count = 0
        profiler._skip_frame = true
    end
end

--- Get the maximum history buffer size
---@return number Maximum number of samples in history buffer
function profiler.get_history_size()
    return HISTORY_SIZE
end

-- Export budget constants for use by debugger
profiler.BUDGET_60FPS = BUDGET_60FPS
profiler.BUDGET_30FPS = BUDGET_30FPS

return profiler
