--- Journal panel for tracking quest progress
--- Displayed in the info panel area of the rest screen
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local controls = require("controls")
local utils = require("ui/utils")
local entries_registry = require("journal/entries")

local journal_panel = {}

-- 9-slice definition (same as simple_dialogue / status_panel)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Pre-built parent->children lookup from static registry (avoids full scan in has_children)
local children_of = {}
for id, def in pairs(entries_registry) do
    if def.parent then
        if not children_of[def.parent] then children_of[def.parent] = {} end
        table.insert(children_of[def.parent], id)
    end
end

-- Layout
local PADDING_TOP = 7
local PADDING_LEFT = 10
local PADDING_RIGHT = 9
local HEADER_FONT_SIZE = 9
local ITEM_FONT_SIZE = 8
local LINE_HEIGHT = 10
local HEADER_HEIGHT = 14
local INDENT_PX = 14  -- ICON_SIZE + ICON_GAP + extra padding for readability
local ICON_SIZE = 6
local ICON_GAP = 4  -- Gap between icon and title text

-- State
local active = false
local journal_data = {}       -- Reference to player.journal
local journal_read = {}       -- Reference to player.journal_read
local selected_index = 1      -- Index into visible_entries
local hovered_index = nil
local scroll_offset = 0       -- Number of entries scrolled past
local collapsed = {}          -- entry_id -> true if collapsed
local visible_entries = {}    -- Built list of {id, depth, has_children, title, status}
local panel_width = 200
local max_visible_lines = 10  -- Computed from panel height
local cached_has_unread = false
local unread_dirty = true      -- Invalidated on show/hide/mark_entry_read

--- Get the depth of an entry by walking the parent chain
---@param entry_id string
---@return number depth (0 = top-level)
local function get_depth(entry_id)
    local depth = 0
    local current = entries_registry[entry_id]
    while current and current.parent do
        depth = depth + 1
        current = entries_registry[current.parent]
    end
    return depth
end

--- Check if an entry has any children that exist in the journal
---@param entry_id string
---@return boolean has_children True if entry has children in journal
local function has_children(entry_id)
    local kids = children_of[entry_id]
    if not kids then return false end
    for _, kid_id in ipairs(kids) do
        if journal_data[kid_id] then return true end
    end
    return false
end

--- Check if any ancestor of an entry is collapsed
---@param entry_id string
---@return boolean is_collapsed True if any ancestor is collapsed
local function is_ancestor_collapsed(entry_id)
    local def = entries_registry[entry_id]
    if not def or not def.parent then return false end
    local parent_id = def.parent
    while parent_id do
        if collapsed[parent_id] then return true end
        local parent_def = entries_registry[parent_id]
        if not parent_def then break end
        parent_id = parent_def.parent
    end
    return false
end

--- Get the root ancestor's journal status (keeps entire hierarchies sorted together)
---@param entry_id string
---@return string "active" or "complete"
local function get_root_status(entry_id)
    local root_id = entry_id
    local def = entries_registry[root_id]
    while def and def.parent do
        root_id = def.parent
        def = entries_registry[root_id]
    end
    return journal_data[root_id] or "active"
end

--- Get effective display status (complete if self or any ancestor is complete)
---@param entry_id string
---@return string "active" or "complete"
local function get_effective_status(entry_id)
    if journal_data[entry_id] == "complete" then return "complete" end
    local def = entries_registry[entry_id]
    if not def then return journal_data[entry_id] or "active" end
    local parent_id = def.parent
    while parent_id do
        if journal_data[parent_id] == "complete" then return "complete" end
        local parent_def = entries_registry[parent_id]
        if not parent_def then break end
        parent_id = parent_def.parent
    end
    return journal_data[entry_id] or "active"
end

--- Build a sort key for hierarchical sorting
--- Returns a string like "0.001.001.002" where first segment is root status (0=active, 1=complete)
---@param entry_id string
---@return string sort_key Hierarchical sort key string
local function build_sort_key(entry_id)
    local parts = {}
    local current_id = entry_id
    while current_id do
        local def = entries_registry[current_id]
        if not def then break end
        table.insert(parts, 1, string.format("%03d", def.sort_order or 999))
        current_id = def.parent
    end
    -- Use root ancestor's status so the entire hierarchy stays grouped
    local status_prefix = get_root_status(entry_id) == "complete" and "1" or "0"
    table.insert(parts, 1, status_prefix)
    return table.concat(parts, ".")
end

--- Build the visible entries list (active first, then complete)
local function build_visible_entries()
    visible_entries = {}

    -- Collect all entries in the journal
    local candidates = {}
    for id, entry_status in pairs(journal_data) do
        if entries_registry[id] and (entry_status == "active" or entry_status == "complete") then
            table.insert(candidates, id)
        end
    end

    -- Sort by status (active first) then hierarchical sort key
    table.sort(candidates, function(a, b)
        return build_sort_key(a) < build_sort_key(b)
    end)

    -- Filter out entries with collapsed ancestors
    for _, id in ipairs(candidates) do
        if not is_ancestor_collapsed(id) then
            local depth = get_depth(id)
            local children = has_children(id)
            table.insert(visible_entries, {
                id = id,
                depth = depth,
                has_children = children,
                title = entries_registry[id].title,
                status = get_effective_status(id),
            })
        end
    end
end

--- Mark the entry at the given index as read
---@param index number Index into visible_entries
local function mark_entry_read(index)
    local entry = visible_entries[index]
    if entry then
        journal_read[entry.id] = true
        unread_dirty = true
    end
end

--- Show the journal panel
---@param data table player.journal table
---@param read_data table|nil player.journal_read table
function journal_panel.show(data, read_data)
    journal_data = data or {}
    journal_read = read_data or {}
    active = true
    selected_index = 1
    hovered_index = nil
    scroll_offset = 0
    collapsed = {}
    unread_dirty = true
    build_visible_entries()
    mark_entry_read(selected_index)
end

--- Hide the journal panel
function journal_panel.hide()
    active = false
    journal_data = {}
    journal_read = {}
    visible_entries = {}
    selected_index = 1
    hovered_index = nil
    scroll_offset = 0
    collapsed = {}
    unread_dirty = true
end

--- Check if the panel is active
---@return boolean is_active True if panel is currently shown
function journal_panel.is_active()
    return active
end

--- Clamp selected_index and scroll_offset to valid ranges
local function clamp_selection()
    if #visible_entries == 0 then
        selected_index = 1
        scroll_offset = 0
        return
    end
    if selected_index < 1 then selected_index = #visible_entries end
    if selected_index > #visible_entries then selected_index = 1 end

    -- Adjust scroll to keep selection visible
    if selected_index <= scroll_offset then
        scroll_offset = selected_index - 1
    elseif selected_index > scroll_offset + max_visible_lines then
        scroll_offset = selected_index - max_visible_lines
    end
end

--- Toggle collapse on the currently selected entry
local function toggle_collapse()
    local entry = visible_entries[selected_index]
    if not entry or not entry.has_children then return end
    if collapsed[entry.id] then
        collapsed[entry.id] = nil
    else
        collapsed[entry.id] = true
    end
    build_visible_entries()
    clamp_selection()
end

--- Handle input and return action result
---@return table|nil result {action = "back"} or nil
function journal_panel.input()
    if not active then return nil end

    if controls.menu_back_pressed() then
        return { action = "back" }
    end

    if #visible_entries == 0 then return nil end

    -- Navigate entries
    if controls.menu_up_pressed() then
        selected_index = selected_index - 1
        clamp_selection()
        mark_entry_read(selected_index)
    elseif controls.menu_down_pressed() then
        selected_index = selected_index + 1
        clamp_selection()
        mark_entry_read(selected_index)
    end

    -- Confirm toggles collapse on entries with children
    if controls.menu_confirm_pressed() then
        toggle_collapse()
    end

    return nil
end

--- Update with mouse hover detection
---@param _ number Delta time (unused)
---@param local_mx number Mouse X relative to panel
---@param local_my number Mouse Y relative to panel
---@param mouse_active boolean Whether mouse is active
function journal_panel.update(_, local_mx, local_my, mouse_active)
    hovered_index = nil
    if not active or not mouse_active or #visible_entries == 0 then return end

    local item_y_start = PADDING_TOP + HEADER_HEIGHT
    for i = 1, math.min(#visible_entries - scroll_offset, max_visible_lines) do
        local item_y = item_y_start + (i - 1) * LINE_HEIGHT
        if local_mx >= PADDING_LEFT and local_mx < panel_width - PADDING_RIGHT and
           local_my >= item_y and local_my < item_y + LINE_HEIGHT then
            hovered_index = i + scroll_offset
            selected_index = hovered_index
            mark_entry_read(hovered_index)
            return
        end
    end
end

--- Handle mouse click (call after update in the same frame)
---@return table|nil result Same as input() return
function journal_panel.handle_click()
    if not active or not hovered_index then return nil end
    if canvas.is_mouse_pressed(0) then
        -- Toggle collapse if entry has children
        local entry = visible_entries[hovered_index]
        if entry and entry.has_children then
            toggle_collapse()
        end
    end
    return nil
end

--- Get the description of the currently selected entry
---@return string|nil description
function journal_panel.get_selected_description()
    if not active or #visible_entries == 0 then return nil end
    local entry = visible_entries[selected_index]
    if not entry then return nil end
    local def = entries_registry[entry.id]
    if not def then return nil end
    return def.description
end

--- Check if any journal entries are unread (cached, invalidated on show/hide/mark_entry_read)
---@param data table player.journal table
---@param read_data table player.journal_read table
---@return boolean True if any entry in data is not in read_data
function journal_panel.has_unread(data, read_data)
    if not unread_dirty then return cached_has_unread end
    unread_dirty = false
    if not data or not read_data then
        cached_has_unread = false
        return false
    end
    cached_has_unread = false
    for entry_id, status in pairs(data) do
        if (status == "active" or status == "complete") and not read_data[entry_id] then
            cached_has_unread = true
            break
        end
    end
    return cached_has_unread
end

--- Draw the journal panel
---@param x number Panel X position
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
function journal_panel.draw(x, y, width, height)
    if not active then return end
    panel_width = width

    -- Compute max visible lines from available space
    local content_height = height - PADDING_TOP - HEADER_HEIGHT - 7
    max_visible_lines = math.floor(content_height / LINE_HEIGHT)
    if max_visible_lines < 1 then max_visible_lines = 1 end

    nine_slice.draw(slice, x, y, width, height)

    canvas.save()

    -- Draw header
    canvas.set_font_family("menu_font")
    canvas.set_font_size(HEADER_FONT_SIZE)
    canvas.set_text_baseline("top")
    canvas.set_text_align("left")
    utils.draw_outlined_text("Journal", x + PADDING_LEFT, y + PADDING_TOP, "#FFFFFF")

    -- Draw entries
    canvas.set_font_size(ITEM_FONT_SIZE)
    local item_y_start = y + PADDING_TOP + HEADER_HEIGHT

    if #visible_entries == 0 then
        canvas.set_text_align("left")
        canvas.set_color("#888888")
        canvas.draw_text(x + PADDING_LEFT, item_y_start, "No entries.")
        canvas.restore()
        return
    end

    local mouse_mode = controls.is_mouse_active()
    local visible_count = math.min(#visible_entries - scroll_offset, max_visible_lines)

    for i = 1, visible_count do
        local entry_index = i + scroll_offset
        local entry = visible_entries[entry_index]
        if not entry then break end

        local item_y = item_y_start + (i - 1) * LINE_HEIGHT
        local indent = entry.depth * INDENT_PX
        local is_complete = entry.status == "complete"

        local active_index = mouse_mode and hovered_index or selected_index
        local is_selected = active_index == entry_index

        -- Active entries: white (yellow when selected); complete entries: gray (yellow when selected)
        local color
        if is_selected then
            color = "#FFFF00"
        elseif is_complete then
            color = "#888888"
        else
            color = "#FFFFFF"
        end

        local text_x = x + PADDING_LEFT + indent

        -- Draw collapse/expand icon for entries with children
        if entry.has_children then
            local icon = collapsed[entry.id] and sprites.ui.icon_expand or sprites.ui.icon_collapse
            local icon_y = item_y + (LINE_HEIGHT - ICON_SIZE) / 2 - 2
            canvas.draw_image(icon, text_x, icon_y, ICON_SIZE, ICON_SIZE)
            text_x = text_x + ICON_SIZE + ICON_GAP
        end

        canvas.set_text_align("left")
        utils.draw_outlined_text(entry.title, text_x, item_y, color)

        -- Draw "Complete" label or unread indicator right-aligned
        if not journal_read[entry.id] then
            -- Unread: draw golden asterisk
            canvas.set_text_align("right")
            canvas.set_color("#FFD700")
            canvas.draw_text(x + width - PADDING_RIGHT, item_y, "*")
        elseif is_complete then
            canvas.set_text_align("right")
            canvas.set_color("#888888")
            canvas.draw_text(x + width - PADDING_RIGHT, item_y, "Complete")
        end
    end

    -- Draw scroll indicators if needed
    if scroll_offset > 0 then
        canvas.set_text_align("right")
        canvas.set_color("#888888")
        canvas.draw_text(x + width - PADDING_RIGHT, y + PADDING_TOP + HEADER_HEIGHT - 2, "^")
    end
    if scroll_offset + max_visible_lines < #visible_entries then
        canvas.set_text_align("right")
        canvas.set_color("#888888")
        local bottom_y = item_y_start + visible_count * LINE_HEIGHT
        canvas.draw_text(x + width - PADDING_RIGHT, bottom_y - 2, "v")
    end

    canvas.restore()
end

return journal_panel
