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
    self.width = opts.width or 130
    self.height = opts.height or 160
    self.on_change = opts.on_change

    self.scheme_index = 1

    self.rows = {}
    for _, action in ipairs(controls_config.actions) do
        local row = keybind_row.create({
            action_id = action.id,
            label = action.label,
            scheme = SCHEMES[self.scheme_index],
        })
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
    -- -1 = scheme tab, 0 to #rows = rows, #rows+1 = reset button
    self.focus_index = 0  -- Start on first row

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

--- Handle keyboard/gamepad input for navigation and keybind editing
--- Note: focus_index -2 (settings tab) and -1 (scheme tab) are handled by settings_menu
---@return nil
function keybind_panel:input()
    if self:is_listening() then
        return
    end

    local reset_focus = #self.rows + 1

    if controls.menu_up_pressed() then
        self.focus_index = self.focus_index - 1
        if self.focus_index < 1 then
            self.focus_index = -1
        end
    elseif controls.menu_down_pressed() then
        self.focus_index = self.focus_index + 1
        if self.focus_index > reset_focus then
            self.focus_index = -2
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
        local row_y = ROW_START_Y + (i - 1) * (row_height + ROW_SPACING)
        if local_my >= row_y and local_my <= row_y + row_height
            and local_mx >= 0 and local_mx <= self.width then
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
    return ROW_START_Y + #self.rows * (row_height + ROW_SPACING) + 5
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
        row.x = 0
        row.y = ROW_START_Y + (i - 1) * (row_height + ROW_SPACING)
        row.width = self.width
        row:draw(self.focus_index == i, self:has_conflict(i))
    end

    self.reset_button:draw(self.focus_index == #self.rows + 1)
end

--- Get the total height needed by the panel content
---@return number height Height in pixels
function keybind_panel:get_content_height()
    local row_height = keybind_row.get_height()
    return ROW_START_Y + #self.rows * (row_height + ROW_SPACING) + RESET_BUTTON_HEIGHT + 5
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

--- Reset focus to the first row and auto-select scheme based on last input device
---@return nil
function keybind_panel:reset_focus()
    self.focus_index = 1
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
