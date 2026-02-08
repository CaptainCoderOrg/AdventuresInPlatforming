--- Control configuration: action definitions, default bindings, and display names
local canvas = require("canvas")

local controls_config = {}

-- Special codes for mouse buttons (strings to distinguish from key codes)
controls_config.MOUSE_LEFT = "MOUSE_LEFT"
controls_config.MOUSE_RIGHT = "MOUSE_RIGHT"
controls_config.MOUSE_MIDDLE = "MOUSE_MIDDLE"

-- Action definitions with IDs and display labels
controls_config.actions = {
    { id = "move_left",   label = "Move Left" },
    { id = "move_right",  label = "Move Right" },
    { id = "move_up",     label = "Up / Climb" },
    { id = "move_down",   label = "Down" },
    { id = "jump",        label = "Jump" },
    { id = "attack",      label = "Attack" },
    { id = "ability_1",   label = "Ability 1" },
    { id = "ability_2",   label = "Ability 2" },
    { id = "ability_3",   label = "Ability 3" },
    { id = "ability_4",   label = "Ability 4" },
    { id = "ability_5",   label = "Ability 5" },
    { id = "ability_6",   label = "Ability 6" },
    { id = "swap_weapon", label = "Swap Weapon" },
}

-- Default keyboard bindings (action_id -> canvas.keys.* constant)
controls_config.keyboard_defaults = {
    move_left   = canvas.keys.A,
    move_right  = canvas.keys.D,
    move_up     = canvas.keys.W,
    move_down   = canvas.keys.S,
    jump        = canvas.keys.SPACE,
    attack      = controls_config.MOUSE_LEFT,
    ability_1   = controls_config.MOUSE_RIGHT,
    ability_2   = canvas.keys.DIGIT_2,
    ability_3   = canvas.keys.DIGIT_3,
    ability_4   = canvas.keys.DIGIT_4,
    ability_5   = canvas.keys.SHIFT,
    ability_6   = canvas.keys.Q,
    swap_weapon = canvas.keys.E,
}

-- Default gamepad bindings (action_id -> canvas.buttons.* constant)
controls_config.gamepad_defaults = {
    move_left   = canvas.buttons.DPAD_LEFT,
    move_right  = canvas.buttons.DPAD_RIGHT,
    move_up     = canvas.buttons.DPAD_UP,
    move_down   = canvas.buttons.DPAD_DOWN,
    jump        = canvas.buttons.SOUTH,
    attack      = canvas.buttons.WEST,
    ability_1   = canvas.buttons.NORTH,
    ability_2   = canvas.buttons.EAST,
    ability_3   = canvas.buttons.LB,
    ability_4   = canvas.buttons.LT,
    ability_5   = canvas.buttons.RB,
    ability_6   = canvas.buttons.RT,
    swap_weapon = canvas.buttons.SELECT,
}

-- Human-readable display names for keyboard keys
controls_config.key_display_names = {
    [canvas.keys.A] = "A",
    [canvas.keys.B] = "B",
    [canvas.keys.C] = "C",
    [canvas.keys.D] = "D",
    [canvas.keys.E] = "E",
    [canvas.keys.F] = "F",
    [canvas.keys.G] = "G",
    [canvas.keys.H] = "H",
    [canvas.keys.I] = "I",
    [canvas.keys.J] = "J",
    [canvas.keys.K] = "K",
    [canvas.keys.L] = "L",
    [canvas.keys.M] = "M",
    [canvas.keys.N] = "N",
    [canvas.keys.O] = "O",
    [canvas.keys.P] = "P",
    [canvas.keys.Q] = "Q",
    [canvas.keys.R] = "R",
    [canvas.keys.S] = "S",
    [canvas.keys.T] = "T",
    [canvas.keys.U] = "U",
    [canvas.keys.V] = "V",
    [canvas.keys.W] = "W",
    [canvas.keys.X] = "X",
    [canvas.keys.Y] = "Y",
    [canvas.keys.Z] = "Z",
    [canvas.keys.DIGIT_0] = "0",
    [canvas.keys.DIGIT_1] = "1",
    [canvas.keys.DIGIT_2] = "2",
    [canvas.keys.DIGIT_3] = "3",
    [canvas.keys.DIGIT_4] = "4",
    [canvas.keys.DIGIT_5] = "5",
    [canvas.keys.DIGIT_6] = "6",
    [canvas.keys.DIGIT_7] = "7",
    [canvas.keys.DIGIT_8] = "8",
    [canvas.keys.DIGIT_9] = "9",
    [canvas.keys.SPACE] = "Space",
    [canvas.keys.ENTER] = "Enter",
    [canvas.keys.SHIFT] = "Shift",
    [canvas.keys.CTRL] = "Ctrl",
    [canvas.keys.ALT] = "Alt",
    [canvas.keys.TAB] = "Tab",
    [canvas.keys.BACKSPACE] = "Backspace",
    [canvas.keys.UP] = "Up",
    [canvas.keys.DOWN] = "Down",
    [canvas.keys.LEFT] = "Left",
    [canvas.keys.RIGHT] = "Right",
    [canvas.keys.COMMA] = ",",
    [canvas.keys.PERIOD] = ".",
    [canvas.keys.SLASH] = "/",
    [canvas.keys.SEMICOLON] = ";",
    [canvas.keys.QUOTE] = "'",
    [canvas.keys.BRACKET_LEFT] = "[",
    [canvas.keys.BRACKET_RIGHT] = "]",
    [canvas.keys.BACKSLASH] = "\\",
    [canvas.keys.MINUS] = "-",
    [canvas.keys.EQUAL] = "=",
    [canvas.keys.BACKQUOTE] = "`",
    [canvas.keys.DELETE] = "Delete",
    [canvas.keys.INSERT] = "Insert",
    [canvas.keys.HOME] = "Home",
    [canvas.keys.END] = "End",
    [canvas.keys.PAGE_UP] = "PgUp",
    [canvas.keys.PAGE_DOWN] = "PgDn",
    [canvas.keys.ESCAPE] = "Esc",
}

-- Human-readable display names for gamepad buttons
controls_config.button_display_names = {
    [canvas.buttons.SOUTH] = "A",
    [canvas.buttons.EAST] = "B",
    [canvas.buttons.WEST] = "X",
    [canvas.buttons.NORTH] = "Y",
    [canvas.buttons.LB] = "LB",
    [canvas.buttons.RB] = "RB",
    [canvas.buttons.LT] = "LT",
    [canvas.buttons.RT] = "RT",
    [canvas.buttons.SELECT] = "Select",
    [canvas.buttons.START] = "Start",
    [canvas.buttons.L3] = "L3",
    [canvas.buttons.R3] = "R3",
    [canvas.buttons.DPAD_UP] = "DPad-Up",
    [canvas.buttons.DPAD_DOWN] = "DPad-Down",
    [canvas.buttons.DPAD_LEFT] = "DPad-Left",
    [canvas.buttons.DPAD_RIGHT] = "DPad-Right",
}

-- Display names for mouse buttons
controls_config.mouse_display_names = {
    [controls_config.MOUSE_LEFT] = "Mouse L",
    [controls_config.MOUSE_RIGHT] = "Mouse R",
    [controls_config.MOUSE_MIDDLE] = "Mouse M",
}

-- Lookup set for mouse button codes (avoids per-call string allocation)
local _mouse_buttons = {
    [controls_config.MOUSE_LEFT] = true,
    [controls_config.MOUSE_RIGHT] = true,
    [controls_config.MOUSE_MIDDLE] = true,
}

--- Check if a code is a mouse button
---@param code any Key or mouse code
---@return boolean
function controls_config.is_mouse_button(code)
    return _mouse_buttons[code] == true
end

--- Get display name for a key or mouse code
---@param code number|string Canvas key constant or mouse button code
---@return string name Display name or "Unknown"
function controls_config.get_key_name(code)
    if controls_config.is_mouse_button(code) then
        return controls_config.mouse_display_names[code] or "Unknown"
    end
    return controls_config.key_display_names[code] or "Unknown"
end

--- Get display name for a button code
---@param button_code number Canvas button constant
---@return string Display name or "Unknown"
function controls_config.get_button_name(button_code)
    return controls_config.button_display_names[button_code] or "Unknown"
end

-- Cached arrays for rebind detection (built on first call)
local all_keys_cache = nil
local all_buttons_cache = nil

--- Get all bindable key codes (for detecting input during rebind)
---@return table Array of key codes
function controls_config.get_all_keys()
    if all_keys_cache then return all_keys_cache end
    all_keys_cache = {}
    for code, _ in pairs(controls_config.key_display_names) do
        table.insert(all_keys_cache, code)
    end
    return all_keys_cache
end

--- Get all mouse button codes (for detecting input during rebind)
---@return table Array of mouse button codes
function controls_config.get_all_mouse_buttons()
    return {
        controls_config.MOUSE_LEFT,
        controls_config.MOUSE_RIGHT,
        controls_config.MOUSE_MIDDLE,
    }
end

--- Get all bindable button codes (for detecting input during rebind)
---@return table Array of button codes
function controls_config.get_all_buttons()
    if all_buttons_cache then return all_buttons_cache end
    all_buttons_cache = {}
    for code, _ in pairs(controls_config.button_display_names) do
        -- Exclude START as it's reserved for menu toggle
        if code ~= canvas.buttons.START then
            table.insert(all_buttons_cache, code)
        end
    end
    return all_buttons_cache
end

return controls_config
