--- Keybind row UI component for displaying and rebinding a single action
local canvas = require("canvas")
local utils = require("ui/utils")
local controls = require("controls")

local keybind_row = {}
keybind_row.__index = keybind_row

-- Layout constants
local ROW_HEIGHT = 12
local LABEL_X = 10
local BINDING_X = 95  -- Right side for binding display
local BINDING_WIDTH = 45

--- Create a new keybind row component
---@param opts {action_id: string, label: string, scheme: string}
---@return table keybind_row
function keybind_row.create(opts)
    local self = setmetatable({}, keybind_row)
    self.action_id = opts.action_id
    self.label = opts.label
    self.scheme = opts.scheme or "keyboard"
    self.x = 0
    self.y = 0
    self.width = 145
    self.height = ROW_HEIGHT
    self.listening = false
    self.listen_time = 0
    self.listen_timeout = 5  -- 5 second timeout
    self.just_captured = false  -- Prevents immediate re-listening after capture
    return self
end

--- Set the control scheme (keyboard or gamepad)
---@param scheme string "keyboard" or "gamepad"
function keybind_row:set_scheme(scheme)
    self.scheme = scheme
end

--- Start listening for a new key/button press
function keybind_row:start_listening()
    self.listening = true
    self.listen_time = 0
end

--- Stop listening and keep the current binding
function keybind_row:cancel_listening()
    self.listening = false
    self.listen_time = 0
end

--- Check if currently in listening mode
---@return boolean listening True if waiting for input
function keybind_row:is_listening()
    return self.listening
end

--- Check if this row can start listening (not listening and not just captured)
---@return boolean can_start True if row is ready to accept new binding
function keybind_row:can_start_listening()
    return not self.listening and not self.just_captured
end

--- Update the keybind row (handles listening state)
---@param dt number Delta time in seconds
---@return boolean changed True if binding was changed
function keybind_row:update(dt)
    -- Clear the just_captured flag from previous frame
    self.just_captured = false

    if not self.listening then
        return false
    end

    -- Update timeout
    self.listen_time = self.listen_time + dt

    -- Check for timeout
    if self.listen_time >= self.listen_timeout then
        self:cancel_listening()
        return false
    end

    -- Detect new input based on scheme
    local new_code = nil
    if self.scheme == "keyboard" then
        -- For keyboard: ESC or gamepad EAST cancels
        if controls.menu_back_pressed() then
            self:cancel_listening()
            return false
        end
        new_code = controls.detect_keyboard_input()
    else
        -- For gamepad: only ESC cancels (so all gamepad buttons can be bound)
        if canvas.is_key_pressed(canvas.keys.ESCAPE) then
            self:cancel_listening()
            return false
        end
        new_code = controls.detect_button_press()
    end

    if new_code then
        controls.set_binding(self.scheme, self.action_id, new_code)
        self.listening = false
        self.listen_time = 0
        self.just_captured = true  -- Prevent immediate re-listening
        return true
    end

    return false
end

--- Get the display text for the current binding
---@return string text Binding name or "Press..." if listening
function keybind_row:get_binding_text()
    if self.listening then
        return "Press..."
    end
    return controls.get_binding_name(self.scheme, self.action_id)
end

--- Render the keybind row with label and current binding display
---@param focused boolean Whether this row is focused
---@param has_conflict boolean Whether this binding conflicts with another
function keybind_row:draw(focused, has_conflict)
    local label_color = "#FFFFFF"
    local binding_color = "#AAAAAA"

    if has_conflict then
        binding_color = "#FF4444"  -- Red when conflicting
    end

    if focused then
        label_color = "#FFFF00"
        binding_color = has_conflict and "#FF8888" or "#FFFF00"  -- Lighter red if focused + conflict
    end

    if self.listening then
        binding_color = "#88FF88"  -- Green when listening
    end

    -- Draw focus background
    if focused then
        canvas.set_color("#FFFFFF20")
        canvas.fill_rect(self.x, self.y, self.width, self.height)
    end

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")

    -- Draw action label
    local text_y = self.y + self.height / 2
    utils.draw_outlined_text(self.label, self.x + LABEL_X, text_y, label_color)

    -- Draw binding (right-aligned)
    local binding_text = self:get_binding_text()
    local metrics = canvas.get_text_metrics(binding_text)
    local binding_x = self.x + BINDING_X + (BINDING_WIDTH - metrics.width) / 2
    utils.draw_outlined_text(binding_text, binding_x, text_y, binding_color)
end

--- Get the row height for layout calculations
---@return number height Height in pixels
function keybind_row.get_height()
    return ROW_HEIGHT
end

return keybind_row
