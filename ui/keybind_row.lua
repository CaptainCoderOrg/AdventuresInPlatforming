--- Keybind row UI component for displaying and rebinding a single action
local canvas = require("canvas")
local utils = require("ui/utils")
local controls = require("controls")
local sprites = require("sprites")

local keybind_row = {}
keybind_row.__index = keybind_row

-- Default layout constants (can be overridden via create opts)
local ROW_HEIGHT = 12
local DEFAULT_LABEL_X = 2
local DEFAULT_BINDING_X = 38
local DEFAULT_BINDING_WIDTH = 32

-- Sprite scale constants (sized to fit in 12px row height)
-- Keyboard sprites are 64x64 base
local KEYBOARD_SCALE = 0.15625        -- 64 * 0.15625 = 10px
local KEYBOARD_WORD_SCALE = 0.234375  -- 64 * 0.234375 = 15px (word keys need more width)
-- Gamepad sprites are 16x16 base
local GAMEPAD_SCALE = 0.625           -- 16 * 0.625 = 10px
local GAMEPAD_SHOULDER_SCALE = 0.9375 -- 16 * 0.9375 = 15px (shoulder buttons are wider)

--- Get keyboard sprite scale for a specific key code
---@param code number Key code
---@return number Scale multiplier
local function get_key_scale(code)
    if sprites.controls.is_word_key(code) then
        return KEYBOARD_WORD_SCALE
    end
    return KEYBOARD_SCALE
end

--- Get gamepad button scale for a specific button code
---@param code number Button code
---@return number Scale multiplier
local function get_button_scale(code)
    if sprites.controls.is_shoulder_button(code) then
        return GAMEPAD_SHOULDER_SCALE
    end
    return GAMEPAD_SCALE
end

--- Create a new keybind row component
---@param opts {action_id: string, label: string, scheme: string, label_x: number|nil, binding_x: number|nil, binding_width: number|nil}
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
    -- Configurable layout options
    self.label_x = opts.label_x or DEFAULT_LABEL_X
    self.binding_x = opts.binding_x or DEFAULT_BINDING_X
    self.binding_width = opts.binding_width or DEFAULT_BINDING_WIDTH
    return self
end

--- Set the control scheme (keyboard or gamepad)
---@param scheme string "keyboard" or "gamepad"
---@return nil
function keybind_row:set_scheme(scheme)
    self.scheme = scheme
end

--- Start listening for a new key/button press
---@return nil
function keybind_row:start_listening()
    self.listening = true
    self.listen_time = 0
end

--- Stop listening and keep the current binding
---@return nil
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

    self.listen_time = self.listen_time + dt

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
---@return nil
function keybind_row:draw(focused, has_conflict)
    local label_color = focused and "#FFFF00" or "#FFFFFF"
    local binding_color = "#AAAAAA"

    if self.listening then
        binding_color = "#88FF88"  -- Ready to accept input
    elseif focused then
        binding_color = has_conflict and "#FF8888" or "#FFFF00"
    elseif has_conflict then
        binding_color = "#FF4444"  -- Duplicate binding
    end

    if focused then
        canvas.set_color("#FFFFFF20")
        canvas.fill_rect(self.x, self.y, self.width, self.height)
    end

    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    canvas.set_text_baseline("middle")

    local text_y = self.y + self.height / 2
    utils.draw_outlined_text(self.label, self.x + self.label_x, text_y, label_color)

    if self.listening then
        local binding_text = "Press..."
        local metrics = canvas.get_text_metrics(binding_text)
        local binding_x = self.x + self.binding_x + (self.binding_width - metrics.width) / 2
        utils.draw_outlined_text(binding_text, binding_x, text_y, binding_color)
    else
        local code = controls.get_binding(self.scheme, self.action_id)
        if code then
            local is_gamepad = self.scheme == "gamepad"
            local sprite_scale = is_gamepad and get_button_scale(code) or get_key_scale(code)
            local base_size = is_gamepad and 16 or 64
            local sprite_size = base_size * sprite_scale
            local sprite_x = self.x + self.binding_x + (self.binding_width - sprite_size) / 2
            local sprite_y = self.y + (self.height - sprite_size) / 2

            if is_gamepad then
                sprites.controls.draw_button(code, sprite_x, sprite_y, sprite_scale)
            else
                sprites.controls.draw_key(code, sprite_x, sprite_y, sprite_scale)
            end
        end
    end
end

--- Get the row height for layout calculations
---@return number height Height in pixels
function keybind_row.get_height()
    return ROW_HEIGHT
end

return keybind_row
