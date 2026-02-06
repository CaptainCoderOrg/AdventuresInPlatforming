--- Fast travel panel for teleporting between visited campfires
--- Displayed in the info panel area of the rest screen when using the Orb of Teleportation
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local controls = require("controls")
local utils = require("ui/utils")

local fast_travel_panel = {}

-- 9-slice definition (same as simple_dialogue / status_panel)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Layout
local PADDING_TOP = 7
local PADDING_LEFT = 10
local PADDING_RIGHT = 9
local HEADER_FONT_SIZE = 9
local ITEM_FONT_SIZE = 8
local LINE_HEIGHT = 10
local HEADER_HEIGHT = 14

-- Display names for level IDs (fallback to raw ID if not mapped)
local LEVEL_DISPLAY_NAMES = {
    dungeon = "Gnomos Hideout",
    garden = "Garden",
}

local active = false
---@type {key: string, name: string, level_id: string, x: number, y: number, display_level: string}[]
local destinations = {}
local selected_index = 1
local hovered_index = nil
local panel_width = 200  -- Updated by draw() to match actual layout width

--- Sort destinations alphabetically by level_id then name
---@param a {level_id: string, name: string} First destination entry
---@param b {level_id: string, name: string} Second destination entry
---@return boolean less_than True if a should sort before b
local function sort_destinations(a, b)
    if a.level_id ~= b.level_id then
        return a.level_id < b.level_id
    end
    return a.name < b.name
end

--- Show the fast travel panel with available destinations
---@param visited_campfires table Keyed by "level_id:name" -> {name, level_id, x, y}
---@param current_key string Key of the current campfire to exclude
function fast_travel_panel.show(visited_campfires, current_key)
    destinations = {}
    for key, entry in pairs(visited_campfires) do
        if key ~= current_key then
            table.insert(destinations, {
                key = key,
                name = entry.name,
                level_id = entry.level_id,
                display_level = LEVEL_DISPLAY_NAMES[entry.level_id] or entry.level_id,
                x = entry.x,
                y = entry.y,
            })
        end
    end
    table.sort(destinations, sort_destinations)
    selected_index = 1
    hovered_index = nil
    active = true
end

--- Hide the fast travel panel
function fast_travel_panel.hide()
    active = false
    destinations = {}
    selected_index = 1
    hovered_index = nil
end

--- Check if the panel is active
---@return boolean is_active True if the fast travel panel is currently showing
function fast_travel_panel.is_active()
    return active
end

--- Get the currently selected destination
---@return table|nil destination {name, level_id, x, y}
function fast_travel_panel.get_selected_destination()
    return destinations[selected_index]
end

--- Handle input and return action result
---@return table|nil result {action = "back"} or {action = "teleport", destination = entry}
function fast_travel_panel.input()
    if not active then return nil end

    if controls.menu_back_pressed() then
        return { action = "back" }
    end

    if #destinations == 0 then return nil end

    if controls.menu_up_pressed() then
        selected_index = selected_index - 1
        if selected_index < 1 then selected_index = #destinations end
    elseif controls.menu_down_pressed() then
        selected_index = selected_index + 1
        if selected_index > #destinations then selected_index = 1 end
    end

    if controls.menu_confirm_pressed() then
        local dest = destinations[selected_index]
        if dest then
            return { action = "teleport", destination = dest }
        end
    end

    return nil
end

--- Update with mouse hover detection
---@param _ number Delta time (unused, for API consistency)
---@param local_mx number Mouse X relative to panel
---@param local_my number Mouse Y relative to panel
---@param mouse_active boolean Whether mouse is active
function fast_travel_panel.update(_, local_mx, local_my, mouse_active)
    hovered_index = nil
    if not active or not mouse_active or #destinations == 0 then return end

    local item_y_start = PADDING_TOP + HEADER_HEIGHT
    for i = 1, #destinations do
        local item_y = item_y_start + (i - 1) * LINE_HEIGHT
        if local_mx >= PADDING_LEFT and local_mx < panel_width - PADDING_RIGHT and
           local_my >= item_y and local_my < item_y + LINE_HEIGHT then
            hovered_index = i
            selected_index = i
            return
        end
    end
end

--- Handle mouse click (call after update in the same frame)
---@return table|nil result Same as input() return
function fast_travel_panel.handle_click()
    if not active or not hovered_index then return nil end
    if canvas.is_mouse_pressed(0) then
        local dest = destinations[hovered_index]
        if dest then
            return { action = "teleport", destination = dest }
        end
    end
    return nil
end

--- Draw the fast travel panel
---@param x number Panel X position
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
function fast_travel_panel.draw(x, y, width, height)
    if not active then return end
    panel_width = width

    nine_slice.draw(slice, x, y, width, height)

    canvas.save()

    -- Header
    canvas.set_font_family("menu_font")
    canvas.set_font_size(HEADER_FONT_SIZE)
    canvas.set_text_baseline("top")
    canvas.set_text_align("left")
    utils.draw_outlined_text("Where To?", x + PADDING_LEFT, y + PADDING_TOP, "#FFFFFF")

    -- Destination list
    canvas.set_font_size(ITEM_FONT_SIZE)
    local item_y_start = y + PADDING_TOP + HEADER_HEIGHT

    if #destinations == 0 then
        canvas.set_text_align("left")
        canvas.set_color("#888888")
        canvas.draw_text(x + PADDING_LEFT, item_y_start, "No other campfires visited.")
        canvas.restore()
        return
    end

    local mouse_mode = controls.is_mouse_active()

    for i, dest in ipairs(destinations) do
        local item_y = item_y_start + (i - 1) * LINE_HEIGHT
        local is_selected = false
        if mouse_mode then
            is_selected = hovered_index == i
        else
            is_selected = selected_index == i
        end

        local color = is_selected and "#FFFF00" or "#FFFFFF"
        canvas.set_text_align("left")
        utils.draw_outlined_text(dest.name, x + PADDING_LEFT, item_y, color)

        canvas.set_text_align("right")
        canvas.set_color(is_selected and "#CCCC00" or "#888888")
        canvas.draw_text(x + width - PADDING_RIGHT, item_y, dest.display_level)
    end

    canvas.restore()
end

return fast_travel_panel
