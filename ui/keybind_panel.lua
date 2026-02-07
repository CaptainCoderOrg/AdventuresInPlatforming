--- Keybind panel with scheme tabs and reset button
local canvas = require("canvas")
local controls = require("controls")
local controls_config = require("config/controls")
local keybind_row = require("ui/keybind_row")
local button = require("ui/button")
local utils = require("ui/utils")

local keybind_panel = {}
keybind_panel.__index = keybind_panel

-- Layout constants
local SCHEME_TAB_HEIGHT = 12
local ROW_START_Y = 15
local ROW_SPACING = 0
local RESET_BUTTON_HEIGHT = 12
local RESET_BUTTON_WIDTH = 40

-- Two-column layout configuration
local COLUMN_WIDTH = 72
local COLUMN_GAP = 22
local COLUMN_X = { [1] = 0, [2] = COLUMN_WIDTH + COLUMN_GAP }

-- Layout: { column (1=left, 2=right), row_within_column }
-- Left column: jump, attack, swap weapon, dash, block, ability 1-2
-- Right column: up, left, down, right, ability 3-4
local COLUMN_LAYOUT = {
    { 2, 2 }, { 2, 4 }, { 2, 1 }, { 2, 3 },              -- Left, Right, Up, Down (right col)
    { 1, 1 }, { 1, 2 },                                    -- Jump, Attack (left col)
    { 1, 6 }, { 1, 7 }, { 2, 6 }, { 2, 7 },              -- Ability 1-2 (left), Ability 3-4 (right, gap after Right)
    { 1, 3 }, { 1, 4 }, { 1, 5 },                          -- Swap weapon, Dash, Block (left col)
}

-- Max rows in the taller column (left column has 7 rows)
local MAX_ROWS_IN_COLUMN = 7

local SCHEMES = { "keyboard", "gamepad" }
local SCHEME_LABELS = {
    keyboard = "Keyboard & Mouse",
    gamepad = "Gamepad",
}

--- Create a new keybind panel
---@param opts {x: number, y: number, width: number, height: number, on_change: function|nil}
---@return table keybind_panel
function keybind_panel.create(opts)
    local self = setmetatable({}, keybind_panel)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 166  -- Two columns + gap
    self.height = opts.height or 160
    self.on_change = opts.on_change

    self.scheme_index = 1

    self.rows = {}
    for i, action in ipairs(controls_config.actions) do
        local layout = COLUMN_LAYOUT[i] or { 1, 1 }
        local row = keybind_row.create({
            action_id = action.id,
            label = action.label,
            scheme = SCHEMES[self.scheme_index],
            label_x = 2,
            binding_x = 62,
            binding_width = 10,
        })
        row.column = layout[1]
        row.column_row = layout[2]
        row.action_index = i
        table.insert(self.rows, row)
    end

    self.reset_button = button.create({
        x = 0, y = 0,
        width = RESET_BUTTON_WIDTH,
        height = RESET_BUTTON_HEIGHT,
        label = "Reset",
        text_only = true,
        on_click = function()
            self:reset_to_defaults()
            if self.on_change then self.on_change() end
        end
    })

    -- Focus tracking
    -- -1 = scheme tab, 1 to #rows = rows, #rows+1 = reset button
    -- Start on first row of left column (abilities)
    self.focus_index = self:find_row_at(1, 1) or 1

    return self
end

--- Get the current scheme name
---@return string
function keybind_panel:get_scheme()
    return SCHEMES[self.scheme_index]
end

--- Cycle to the next or previous scheme
---@param direction number 1 for next, -1 for previous
function keybind_panel:cycle_scheme(direction)
    self.scheme_index = ((self.scheme_index - 1 + direction) % #SCHEMES) + 1
    self:update_row_schemes()
end

--- Update all rows to use the current scheme and cancel any active listening
---@return nil
function keybind_panel:update_row_schemes()
    local scheme = self:get_scheme()
    for _, row in ipairs(self.rows) do
        row:set_scheme(scheme)
        row:cancel_listening()  -- Cancel any active listening when switching schemes
    end
end

--- Reset all bindings for the current scheme to their default values
---@return nil
function keybind_panel:reset_to_defaults()
    controls.reset_all(self:get_scheme())
end

--- Check if any row is currently listening for input
---@return boolean listening True if any row is in listening mode
function keybind_panel:is_listening()
    for _, row in ipairs(self.rows) do
        if row:is_listening() then
            return true
        end
    end
    return false
end

--- Check if any row just captured a keybind this frame
---@return boolean True if a keybind was just captured
function keybind_panel:just_captured()
    for _, row in ipairs(self.rows) do
        if row.just_captured then
            return true
        end
    end
    return false
end

--- Check if input should be blocked (listening or just captured)
---@return boolean True if rest screen input should be blocked
function keybind_panel:is_capturing_input()
    return self:is_listening() or self:just_captured()
end

--- Cancel any active key listening on all rows
---@return nil
function keybind_panel:cancel_listening()
    for _, row in ipairs(self.rows) do
        row:cancel_listening()
    end
end

--- Get the focused row, or nil if focus is not on a row
---@return table|nil row The focused keybind_row or nil
function keybind_panel:get_focused_row()
    if self.focus_index >= 1 and self.focus_index <= #self.rows then
        return self.rows[self.focus_index]
    end
    return nil
end

--- Find the row index at a given column and column_row position
---@param column number Column (1=left, 2=right)
---@param column_row number Row within the column (1-indexed)
---@return number|nil Row index or nil if not found
function keybind_panel:find_row_at(column, column_row)
    for i, row in ipairs(self.rows) do
        if row.column == column and row.column_row == column_row then
            return i
        end
    end
    return nil
end

--- Find the nearest row in an adjacent column
---@param from_index number Current row index
---@param to_column number Target column (1=left, 2=right)
---@return number|nil Row index in target column or nil
function keybind_panel:find_nearest_in_column(from_index, to_column)
    local current_row = self.rows[from_index]
    if not current_row then return nil end

    -- Try to find a row at the same column_row position
    local target = self:find_row_at(to_column, current_row.column_row)
    if target then return target end

    -- Find the closest row in the target column
    local best_index = nil
    local best_distance = math.huge
    for i, row in ipairs(self.rows) do
        if row.column == to_column then
            local dist = math.abs(row.column_row - current_row.column_row)
            if dist < best_distance then
                best_distance = dist
                best_index = i
            end
        end
    end
    return best_index
end

--- Get the max column_row for a given column
---@param column number Column (1=left, 2=right)
---@return number Max row count in that column
function keybind_panel:get_max_row_in_column(column)
    local max_row = 0
    for _, row in ipairs(self.rows) do
        if row.column == column and row.column_row > max_row then
            max_row = row.column_row
        end
    end
    return max_row
end

--- Handle keyboard/gamepad input for navigation and keybind editing
--- Note: focus_index -2 (settings tab) and -1 (scheme tab) are handled by settings_menu
---@return nil
function keybind_panel:input()
    if self:is_listening() then
        return
    end

    local reset_focus = #self.rows + 1
    local current_row = self.rows[self.focus_index]

    if controls.menu_up_pressed() then
        if self.focus_index == reset_focus then
            -- From reset button, go to bottom of left column
            local max_left_row = self:get_max_row_in_column(1)
            self.focus_index = self:find_row_at(1, max_left_row) or self.focus_index
        elseif current_row then
            if current_row.column_row > 1 then
                -- Move up within the same column
                local target = self:find_row_at(current_row.column, current_row.column_row - 1)
                if target then
                    self.focus_index = target
                end
            else
                -- At top of column, go to scheme tab
                self.focus_index = -1
            end
        elseif self.focus_index == -1 then
            -- From scheme tab, wrap to reset button
            self.focus_index = reset_focus
        end
    elseif controls.menu_down_pressed() then
        if self.focus_index == -1 then
            -- From scheme tab, go to first row of left column
            self.focus_index = self:find_row_at(1, 1) or 5
        elseif current_row then
            local max_row = self:get_max_row_in_column(current_row.column)
            if current_row.column_row < max_row then
                -- Move down within the same column
                local target = self:find_row_at(current_row.column, current_row.column_row + 1)
                if target then
                    self.focus_index = target
                end
            else
                -- At bottom of column, go to reset button
                self.focus_index = reset_focus
            end
        elseif self.focus_index == reset_focus then
            -- From reset button, wrap to settings tab
            self.focus_index = -2
        end
    elseif controls.menu_left_pressed() then
        if self.focus_index == -1 then
            -- On scheme tab, cycle scheme
            self:cycle_scheme(-1)
        elseif current_row and current_row.column == 2 then
            -- In right column, jump to nearest left column row
            local target = self:find_nearest_in_column(self.focus_index, 1)
            if target then
                self.focus_index = target
            end
        end
    elseif controls.menu_right_pressed() then
        if self.focus_index == -1 then
            -- On scheme tab, cycle scheme
            self:cycle_scheme(1)
        elseif current_row and current_row.column == 1 then
            -- In left column, jump to nearest right column row
            local target = self:find_nearest_in_column(self.focus_index, 2)
            if target then
                self.focus_index = target
            end
        end
    end

    if controls.menu_confirm_pressed() then
        if self.focus_index >= 1 and self.focus_index <= #self.rows then
            local row = self.rows[self.focus_index]
            if row:can_start_listening() then
                row:start_listening()
            end
        elseif self.focus_index == reset_focus then
            self:reset_to_defaults()
        end
    end
end

--- Update the keybind panel
---@param dt number Delta time in seconds
---@param local_mx number Local mouse X coordinate
---@param local_my number Local mouse Y coordinate
---@param mouse_active boolean Whether mouse input is active
---@return nil
function keybind_panel:update(dt, local_mx, local_my, mouse_active)
    local was_listening = self:is_listening()

    for _, row in ipairs(self.rows) do
        row:update(dt)
    end

    -- Notify when a keybind was just captured
    if self:just_captured() and self.on_change then
        self.on_change()
    end

    local reset_y = self:get_reset_button_y()
    self.reset_button.x = (self.width - RESET_BUTTON_WIDTH) / 2
    self.reset_button.y = reset_y
    self.reset_button:update(local_mx, local_my)

    -- Skip mouse hover handling while listening, just finished listening, or using keyboard
    if self:is_listening() or was_listening or not mouse_active then
        return
    end

    local scheme_tab_top = 0
    local scheme_tab_bottom = SCHEME_TAB_HEIGHT
    if local_my >= scheme_tab_top and local_my <= scheme_tab_bottom
        and local_mx >= 0 and local_mx <= self.width then
        self.focus_index = -1
        if canvas.is_mouse_pressed(0) then
            local center = self.width / 2
            if local_mx < center - 30 then
                self:cycle_scheme(-1)
            else
                self:cycle_scheme(1)
            end
        end
    end

    local row_height = keybind_row.get_height()
    for i, row in ipairs(self.rows) do
        local col_x = COLUMN_X[row.column]
        local row_y = ROW_START_Y + (row.column_row - 1) * (row_height + ROW_SPACING)
        if local_my >= row_y and local_my <= row_y + row_height
            and local_mx >= col_x and local_mx <= col_x + COLUMN_WIDTH then
            self.focus_index = i
            if canvas.is_mouse_pressed(0) and row:can_start_listening() then
                row:start_listening()
            end
        end
    end

    -- Reset button handles its own click via button:update callback
    local reset_x = self.reset_button.x
    if local_my >= reset_y and local_my <= reset_y + RESET_BUTTON_HEIGHT
        and local_mx >= reset_x and local_mx <= reset_x + RESET_BUTTON_WIDTH then
        self.focus_index = #self.rows + 1
    end
end

--- Calculate the Y position for the reset button
---@return number
function keybind_panel:get_reset_button_y()
    local row_height = keybind_row.get_height()
    return ROW_START_Y + MAX_ROWS_IN_COLUMN * (row_height + ROW_SPACING) + 5
end

--- Render the keybind panel with scheme tabs, keybind rows, and reset button
---@return nil
function keybind_panel:draw()
    local scheme_label = SCHEME_LABELS[self:get_scheme()]
    local tab_focused = self.focus_index == -1
    local tab_color = tab_focused and "#FFFF00" or "#FFFFFF"
    local arrow_color = tab_focused and "#FFFF00" or "#888888"

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")

    local tab_center_x = self.width / 2
    local tab_y = 6

    utils.draw_outlined_text("<", tab_center_x - 45, tab_y, arrow_color)
    utils.draw_outlined_text(">", tab_center_x + 42, tab_y, arrow_color)

    local label_metrics = canvas.get_text_metrics(scheme_label)
    utils.draw_outlined_text(scheme_label, tab_center_x - label_metrics.width / 2, tab_y, tab_color)

    local row_height = keybind_row.get_height()
    for i, row in ipairs(self.rows) do
        local col_x = COLUMN_X[row.column]
        row.x = col_x
        row.y = ROW_START_Y + (row.column_row - 1) * (row_height + ROW_SPACING)
        row.width = COLUMN_WIDTH
        row:draw(self.focus_index == i, self:has_conflict(i))
    end

    self.reset_button:draw(self.focus_index == #self.rows + 1)
end

--- Get the total height needed by the panel content
---@return number height Height in pixels
function keybind_panel:get_content_height()
    local row_height = keybind_row.get_height()
    return ROW_START_Y + MAX_ROWS_IN_COLUMN * (row_height + ROW_SPACING) + RESET_BUTTON_HEIGHT + 5
end

--- Check if a row's binding conflicts with another row
---@param row_index number Index of the row to check
---@return boolean has_conflict True if binding is used by another action
function keybind_panel:has_conflict(row_index)
    local row = self.rows[row_index]
    local binding = controls.get_binding(row.scheme, row.action_id)
    if not binding then return false end

    for i, other_row in ipairs(self.rows) do
        if i ~= row_index then
            local other_binding = controls.get_binding(other_row.scheme, other_row.action_id)
            if other_binding == binding then
                return true
            end
        end
    end
    return false
end

--- Reset focus to the first row of left column and auto-select scheme based on last input device
---@return nil
function keybind_panel:reset_focus()
    -- Focus on first row of left column (abilities)
    self.focus_index = self:find_row_at(1, 1) or 1
    self:cancel_listening()

    local last_device = controls.get_last_input_device()
    if last_device == "gamepad" then
        self.scheme_index = 2
    else
        self.scheme_index = 1
    end
    self:update_row_schemes()
end

return keybind_panel
