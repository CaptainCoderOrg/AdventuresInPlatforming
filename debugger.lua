local canvas = require('canvas')
local config = require('config')
local profiler = require('profiler')

local BUDGET_60FPS = profiler.BUDGET_60FPS
local BUDGET_30FPS = profiler.BUDGET_30FPS
local SECTION_WARNING_MS = 2  -- Individual sections above this threshold are highlighted red

-- Module-level reusable tables to avoid per-frame allocations
local cached_children = {}
local cached_roots = {}
local child_sort_fn = function(a, b) return a.max > b.max end

local debugger = {}

--- Get color for a frame time value based on fps budget
---@param ms number Frame time in milliseconds
---@return string Hex color code
local function get_frame_color(ms)
    if ms > BUDGET_30FPS then
        return "#FF4444"  -- Red: < 30fps
    elseif ms > BUDGET_60FPS then
        return "#FFAA44"  -- Yellow: < 60fps
    else
        return "#44FF44"  -- Green: >= 60fps
    end
end

--- Returns a colored status string for an ability flag
---@param enabled boolean Whether the ability is unlocked
---@return string color Hex color for the status
---@return string text Status text ("ON" or "OFF")
local function ability_status(enabled)
    if enabled then
        return "#44FF44", "ON"
    else
        return "#FF4444", "OFF"
    end
end

--- Draw debug overlay showing FPS, player state, and bounding boxes
---@param player table Player instance to display debug info for
---@return nil
function debugger.draw(player)
    if not config.debug then return end
    local h = canvas.get_height()
    local w = canvas.get_width()

    canvas.set_font_size(24)
    local FPS = string.format("FPS: %.0f", 1/canvas.get_delta())
    local metrics = canvas.get_text_metrics(FPS)
    local text_height = metrics.actual_bounding_box_ascent + metrics.actual_bounding_box_descent
    canvas.set_text_baseline("top")

    canvas.set_color("#00000051")
    canvas.fill_rect(w - metrics.width - 4, h - text_height*2, metrics.width + 4, text_height*2)
    canvas.set_color("#dede2bff")
    canvas.draw_text(w - metrics.width - 4, h - text_height*2, FPS)


    local GROUNDED = "is_grounded: " .. tostring(player.is_grounded)
    local POS = string.format("POS: %.2f, %.2f", player.x, player.y)
    local CAN_CLIMB = "can_climb: " .. tostring(player.can_climb) .. " is_climbing: " .. tostring(player.is_climbing)
    local PLAYER_STATE = "state: " .. player.state.name
    canvas.draw_text(0, 0, GROUNDED)
    canvas.draw_text(0, 24, POS)
    canvas.draw_text(0, 48, CAN_CLIMB)
    canvas.draw_text(0, 72, PLAYER_STATE)

    -- Draw ability unlock status panel (top-right)
    local line_h = 20
    local panel_width = 180
    local ability_x = w - panel_width
    local ability_y = 0

    canvas.set_font_size(16)
    canvas.set_color("#FFFFFF")
    canvas.draw_text(ability_x, ability_y, "Abilities (1-7 to toggle):")
    ability_y = ability_y + line_h

    -- NOTE: This table is allocated per-frame when debug mode is on.
    -- Could be moved to module scope with in-place flag updates if GC pressure becomes an issue.
    -- Monitor for performance problems during extended debug sessions.
    local abilities = {
        { key = "1", name = "Double Jump", flag = player.has_double_jump },
        { key = "2", name = "Dash",        flag = player.can_dash },
        { key = "3", name = "Wall Slide",  flag = player.has_wall_slide },
        { key = "4", name = "Hammer",      flag = player.has_hammer },
        { key = "5", name = "Axe",         flag = player.has_axe },
        { key = "6", name = "Shuriken",    flag = player.has_shuriken },
        { key = "7", name = "Shield",      flag = player.has_shield },
    }

    for _, ability in ipairs(abilities) do
        local color, status = ability_status(ability.flag)
        canvas.set_color("#AAAAAA")
        canvas.draw_text(ability_x, ability_y, ability.key .. ":")
        canvas.set_color("#FFFFFF")
        canvas.draw_text(ability_x + 25, ability_y, ability.name)
        canvas.set_color(color)
        canvas.draw_text(ability_x + 120, ability_y, status)
        ability_y = ability_y + line_h
    end

    if config.profiler then
        debugger.draw_profiler()
    end
end

--- Draw profiler overlay showing per-system timing breakdown
---@return nil
function debugger.draw_profiler()
    local results, frame_total = profiler.get_results()

    local x = 10
    local y = 120  -- Below existing debug text
    local line_height = 18
    local bar_x = 130
    local bar_max_width = 150
    local padding = 8

    -- Graph dimensions
    local graph_width = 900
    local graph_height = 100

    canvas.set_font_size(16)
    canvas.set_color("#FFFFFF")

    -- Header
    canvas.draw_text(x, y, string.format("Frame: %.2fms (budget: %.2fms)", frame_total, BUDGET_60FPS))
    y = y + line_height + 4

    -- Draw frame time graph
    debugger.draw_frame_graph(x, y, graph_width, graph_height)
    y = y + graph_height + 8

    -- Draw background box for section breakdown (30% alpha, after graph)
    local num_rows = #results
    local section_height = (num_rows * line_height) + padding * 2
    canvas.set_color("#0000004D")
    canvas.fill_rect(x - padding, y - padding, bar_max_width + 250, section_height)

    -- Clear cached tables by truncating arrays
    for i = 1, #cached_roots do cached_roots[i] = nil end
    for _, list in pairs(cached_children) do
        for i = 1, #list do list[i] = nil end
    end

    -- Build hierarchy: group children by parent
    local update_result = nil  -- Keep "update" separate to pin at top
    for _, result in ipairs(results) do
        if result.parent then
            if not cached_children[result.parent] then
                cached_children[result.parent] = {}
            end
            local list = cached_children[result.parent]
            list[#list + 1] = result
        elseif result.name == "update" then
            update_result = result
        else
            cached_roots[#cached_roots + 1] = result
        end
    end

    -- Sort children by max time for stable ordering
    for _, list in pairs(cached_children) do
        if #list > 0 then
            table.sort(list, child_sort_fn)
        end
    end

    -- Pin "update" at top of roots
    if update_result then
        table.insert(cached_roots, 1, update_result)
    end

    -- Draw a single section row, returns the y position for the next row
    local function draw_section(result, indent, row_y)
        local indent_px = indent * 12
        local available_width = bar_max_width - indent_px
        local bar_width = math.min(result.elapsed * 10, available_width)
        local max_width = math.min(result.max * 10, available_width)

        -- Background bar
        canvas.set_color("#333333")
        canvas.fill_rect(bar_x + indent_px, row_y, available_width, line_height - 2)

        -- Elapsed bar (red if > 2ms)
        canvas.set_color(result.elapsed > SECTION_WARNING_MS and "#FF4444" or "#44FF44")
        canvas.fill_rect(bar_x + indent_px, row_y, bar_width, line_height - 2)

        -- Max marker (red vertical line)
        if result.max > 0 then
            canvas.set_color("#FF0000")
            canvas.fill_rect(bar_x + indent_px + max_width - 1, row_y, 2, line_height - 2)
        end

        -- Text (white for all)
        canvas.set_color("#FFFFFF")
        local prefix = indent > 0 and "  " or ""
        canvas.draw_text(x + indent_px, row_y, string.format("%-12s", prefix .. result.name))
        canvas.draw_text(bar_x + bar_max_width + 10, row_y, string.format("%.2fms (%.2fms)", result.elapsed, result.max))

        return row_y + line_height
    end

    -- Per-system breakdown (hierarchical)
    canvas.set_font_size(14)
    for _, result in ipairs(cached_roots) do
        y = draw_section(result, 0, y)
        -- Draw children indented
        if cached_children[result.name] then
            for _, child in ipairs(cached_children[result.name]) do
                y = draw_section(child, 1, y)
            end
        end
    end
end

--- Draw frame time history graph
---@param x number Left edge
---@param y number Top edge
---@param width number Graph width in pixels
---@param height number Graph height in pixels
---@return nil
function debugger.draw_frame_graph(x, y, width, height)
    local samples, max_val = profiler.get_history()

    if #samples == 0 then
        canvas.set_color("#33333380")
        canvas.fill_rect(x, y, width, height)
        canvas.set_color("#888888")
        canvas.set_font_size(12)
        canvas.draw_text(x + 4, y + height/2 - 6, "Collecting data...")
        return
    end

    -- Scale: always show at least 30fps budget line, expand if needed
    local scale_max = math.max(BUDGET_30FPS, max_val)

    -- Background (50% alpha)
    canvas.set_color("#1a1a1a80")
    canvas.fill_rect(x, y, width, height)

    -- 60fps budget line
    local budget_60_y = y + height - (BUDGET_60FPS / scale_max) * height
    canvas.set_color("#444444")
    canvas.fill_rect(x, budget_60_y, width, 1)

    -- 30fps budget line
    local budget_30_y = y + height - (BUDGET_30FPS / scale_max) * height
    canvas.set_color("#663333")
    canvas.fill_rect(x, budget_30_y, width, 1)

    -- Draw line graph connecting all points with color based on value
    local fill_ratio = profiler.history_count / profiler.get_history_size()
    local used_width = width * fill_ratio
    local sample_width = used_width / math.max(1, #samples - 1)

    -- Draw line segments with appropriate colors
    for i = 1, #samples - 1 do
        local val1 = samples[i]
        local val2 = samples[i + 1]
        local px1 = x + (i - 1) * sample_width
        local py1 = y + height - (val1 / scale_max) * height
        local px2 = x + i * sample_width
        local py2 = y + height - (val2 / scale_max) * height

        -- Use color of the higher value for the segment
        canvas.set_color(get_frame_color(math.max(val1, val2)))
        canvas.begin_path()
        canvas.move_to(px1, py1)
        canvas.line_to(px2, py2)
        canvas.stroke()
    end

    -- Labels
    canvas.set_color("#FFFFFF")
    canvas.set_font_size(10)
    canvas.draw_text(x + width + 4, y, string.format("%.0fms", scale_max))
    canvas.draw_text(x + width + 4, budget_30_y - 4, string.format("%.2f", BUDGET_30FPS))
    canvas.draw_text(x + width + 4, budget_60_y - 4, string.format("%.2f", BUDGET_60FPS))
    canvas.draw_text(x + width + 4, y + height - 10, "0")
end

return debugger
