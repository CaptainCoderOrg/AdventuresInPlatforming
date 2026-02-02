--- Unified input handling for keyboard and gamepad with configurable bindings
local canvas = require("canvas")
local controls_config = require("config/controls")
local settings_storage = require("settings_storage")

local controls = {}

local TRIGGER_THRESHOLD = 0.1   -- Minimum trigger press to register as held
local CAMERA_DEADZONE = 0.15    -- Prevents stick drift on camera look

-- Runtime bindings (initialized from defaults)
local keyboard_bindings = {}
local gamepad_bindings = {}

-- Lookup tables for scheme-based operations
local bindings = { keyboard = keyboard_bindings, gamepad = gamepad_bindings }
local defaults = { keyboard = controls_config.keyboard_defaults, gamepad = controls_config.gamepad_defaults }

-- Track last used input device ("keyboard", "mouse", or "gamepad")
local last_input_device = "keyboard"

-- Mouse position tracking for movement detection
local last_mouse_x = nil
local last_mouse_y = nil

--- Initialize controls with default bindings, then load saved bindings from storage
---@return nil
function controls.init()
    -- Set defaults
    for scheme, default_bindings in pairs(defaults) do
        for action_id, code in pairs(default_bindings) do
            bindings[scheme][action_id] = code
        end
    end

    -- Load and apply saved bindings (uses set_all_bindings for validation)
    settings_storage.init()
    controls.set_all_bindings("keyboard", settings_storage.load_bindings("keyboard"))
    controls.set_all_bindings("gamepad", settings_storage.load_bindings("gamepad"))
end

--- Get current binding for an action
---@param scheme string "keyboard" or "gamepad"
---@param action_id string Action identifier
---@return number|nil Key or button code
function controls.get_binding(scheme, action_id)
    local scheme_bindings = bindings[scheme]
    return scheme_bindings and scheme_bindings[action_id]
end

--- Set binding for an action
---@param scheme string "keyboard" or "gamepad"
---@param action_id string Action identifier
---@param code number Key or button code
---@return nil
function controls.set_binding(scheme, action_id, code)
    local scheme_bindings = bindings[scheme]
    if scheme_bindings then
        scheme_bindings[action_id] = code
    end
end

--- Reset a single binding to default
---@param scheme string "keyboard" or "gamepad"
---@param action_id string Action identifier
---@return nil
function controls.reset_binding(scheme, action_id)
    local scheme_bindings = bindings[scheme]
    local scheme_defaults = defaults[scheme]
    if scheme_bindings and scheme_defaults then
        scheme_bindings[action_id] = scheme_defaults[action_id]
    end
end

--- Reset all bindings for a scheme to defaults
---@param scheme string "keyboard" or "gamepad"
---@return nil
function controls.reset_all(scheme)
    local scheme_bindings = bindings[scheme]
    local scheme_defaults = defaults[scheme]
    if scheme_bindings and scheme_defaults then
        for action_id, code in pairs(scheme_defaults) do
            scheme_bindings[action_id] = code
        end
    end
end

--- Get all bindings for a scheme (for persistence)
---@param scheme string "keyboard" or "gamepad"
---@return table bindings Copy of action_id -> code mapping
function controls.get_all_bindings(scheme)
    local scheme_bindings = bindings[scheme]
    if not scheme_bindings then return {} end
    local copy = {}
    for action_id, code in pairs(scheme_bindings) do
        copy[action_id] = code
    end
    return copy
end

--- Set all bindings for a scheme (for persistence)
---@param scheme string "keyboard" or "gamepad"
---@param new_bindings table action_id -> code mapping
---@return nil
function controls.set_all_bindings(scheme, new_bindings)
    local scheme_bindings = bindings[scheme]
    if not scheme_bindings or not new_bindings then return end
    for action_id, code in pairs(new_bindings) do
        -- Only set known actions (silently ignores obsolete/invalid bindings from storage)
        if defaults[scheme][action_id] ~= nil then
            scheme_bindings[action_id] = code
        end
    end
end

--- Detect any pressed key for rebinding
---@return number|nil Key code if a key was pressed this frame
function controls.detect_key_press()
    for _, key_code in ipairs(controls_config.get_all_keys()) do
        -- Skip ESC as it's reserved for menu toggle
        if key_code ~= canvas.keys.ESCAPE and canvas.is_key_pressed(key_code) then
            return key_code
        end
    end
    return nil
end

--- Detect any pressed mouse button for rebinding
---@return number|nil Mouse button code if a button was pressed this frame
function controls.detect_mouse_press()
    if canvas.is_mouse_pressed(0) then
        return controls_config.MOUSE_LEFT
    end
    if canvas.is_mouse_pressed(2) then
        return controls_config.MOUSE_RIGHT
    end
    if canvas.is_mouse_pressed(1) then
        return controls_config.MOUSE_MIDDLE
    end
    return nil
end

--- Detect any pressed key or mouse button for rebinding (keyboard scheme)
---@return number|nil Key or mouse code if input was detected this frame
function controls.detect_keyboard_input()
    -- Check mouse first (more specific)
    local mouse = controls.detect_mouse_press()
    if mouse then return mouse end
    -- Then check keyboard
    return controls.detect_key_press()
end

--- Detect any pressed gamepad button for rebinding
---@return number|nil Button code if a button was pressed this frame
function controls.detect_button_press()
    for _, button_code in ipairs(controls_config.get_all_buttons()) do
        if canvas.is_gamepad_button_pressed(1, button_code) then
            return button_code
        end
    end
    return nil
end

--- Get display name for current binding
---@param scheme string "keyboard" or "gamepad"
---@param action_id string Action identifier
---@return string Display name
function controls.get_binding_name(scheme, action_id)
    local code = controls.get_binding(scheme, action_id)
    if not code then return "None" end
    if scheme == "keyboard" then
        return controls_config.get_key_name(code)
    else
        return controls_config.get_button_name(code)
    end
end

--- Get the last used input device
---@return string "keyboard", "mouse", or "gamepad"
function controls.get_last_input_device()
    return last_input_device
end

-- Map mouse button codes to canvas button numbers
local mouse_button_map = {
    [controls_config.MOUSE_LEFT] = 0,
    [controls_config.MOUSE_RIGHT] = 2,
    [controls_config.MOUSE_MIDDLE] = 1,
}

-- Helper to check keyboard/mouse binding with configurable check functions
local function check_key_binding(action_id, mouse_fn, key_fn)
    local code = keyboard_bindings[action_id]
    if not code then return false end

    if controls_config.is_mouse_button(code) then
        local mouse_btn = mouse_button_map[code]
        if mouse_btn and mouse_fn(mouse_btn) then
            last_input_device = "mouse"
            return true
        end
    elseif key_fn(code) then
        last_input_device = "keyboard"
        return true
    end
    return false
end

-- Helper to check gamepad binding with configurable threshold
local function check_gamepad_binding(action_id, threshold)
    local button = gamepad_bindings[action_id]
    if button and canvas.get_gamepad_button(1, button) > threshold then
        last_input_device = "gamepad"
        return true
    end
    return false
end

local function is_key_binding_pressed(action_id)
    return check_key_binding(action_id, canvas.is_mouse_pressed, canvas.is_key_pressed)
end

local function is_key_binding_down(action_id)
    return check_key_binding(action_id, canvas.is_mouse_down, canvas.is_key_down)
end

local function is_button_binding_pressed(action_id)
    local button = gamepad_bindings[action_id]
    if button and canvas.is_gamepad_button_pressed(1, button) then
        last_input_device = "gamepad"
        return true
    end
    return false
end

local function is_button_binding_down(action_id)
    return check_gamepad_binding(action_id, 0)
end

local function is_trigger_binding_down(action_id)
    return check_gamepad_binding(action_id, TRIGGER_THRESHOLD)
end

--- Check if ability swap input was pressed this frame
---@return boolean pressed True if swap_ability binding was pressed
function controls.swap_ability_pressed()
    return is_key_binding_pressed("swap_ability")
        or is_button_binding_pressed("swap_ability")
end

--- Check if ability input was pressed this frame
---@return boolean pressed True if ability binding was pressed
function controls.ability_pressed()
    return is_key_binding_pressed("ability")
        or is_button_binding_pressed("ability")
end

--- Check if weapon swap input was pressed this frame
---@return boolean pressed True if swap_weapon binding was pressed
function controls.swap_weapon_pressed()
    return is_key_binding_pressed("swap_weapon")
        or is_button_binding_pressed("swap_weapon")
end

--- Check if block input is currently held down
---@return boolean down True if block binding is held
function controls.block_down()
    return is_key_binding_down("block")
        or is_trigger_binding_down("block")
end

--- Check if up directional input is currently held
---@return boolean down True if move_up binding is held
function controls.up_down()
    return is_key_binding_down("move_up")
        or is_button_binding_down("move_up")
end

--- Check if up directional input was pressed this frame
---@return boolean pressed True if move_up binding was pressed
function controls.up_pressed()
    return is_key_binding_pressed("move_up")
        or is_button_binding_pressed("move_up")
end

--- Check if down directional input is currently held
---@return boolean down True if move_down binding is held
function controls.down_down()
    return is_key_binding_down("move_down")
        or is_button_binding_down("move_down")
end

--- Get horizontal camera look input from right analog stick
---@return number x Axis value from -1 (left) to +1 (right), or 0 within deadzone
function controls.get_camera_look_x()
    local right_stick_x = canvas.get_gamepad_axis(1, canvas.axes.RIGHT_STICK_X)
    if math.abs(right_stick_x) < CAMERA_DEADZONE then return 0 end
    return right_stick_x
end

--- Get vertical camera look input from right analog stick
---@return number y Axis value from -1 (up) to +1 (down), or 0 within deadzone
function controls.get_camera_look_y()
    local right_stick_y = canvas.get_gamepad_axis(1, canvas.axes.RIGHT_STICK_Y)
    if math.abs(right_stick_y) < CAMERA_DEADZONE then return 0 end
    return right_stick_y
end

--- Check if jump input was pressed this frame
---@return boolean pressed True if jump binding was pressed
function controls.jump_pressed()
    return is_key_binding_pressed("jump")
        or is_button_binding_pressed("jump")
end

--- Check if left movement input is currently held
---@return boolean down True if move_left binding is held
function controls.left_down()
    return is_key_binding_down("move_left")
        or is_button_binding_down("move_left")
end

--- Check if right movement input is currently held
---@return boolean down True if move_right binding is held
function controls.right_down()
    return is_key_binding_down("move_right")
        or is_button_binding_down("move_right")
end

--- Check if dash input was pressed this frame
---@return boolean pressed True if dash binding was pressed
function controls.dash_pressed()
    return is_key_binding_pressed("dash")
        or is_button_binding_pressed("dash")
end

--- Check if attack input was pressed this frame
---@return boolean pressed True if attack binding was pressed
function controls.attack_pressed()
    return is_key_binding_pressed("attack")
        or is_button_binding_pressed("attack")
end

-- Helper for menu navigation input (checks keyboard keys and gamepad button)
local function check_menu_input_pressed(key1, key2, gamepad_button)
    if canvas.is_key_pressed(key1) or (key2 and canvas.is_key_pressed(key2)) then
        last_input_device = "keyboard"
        return true
    end
    if canvas.is_gamepad_button_pressed(1, gamepad_button) then
        last_input_device = "gamepad"
        return true
    end
    return false
end

-- Helper for menu navigation held state (checks keyboard keys and gamepad button)
local function check_menu_input_down(key1, key2, gamepad_button)
    if canvas.is_key_down(key1) or (key2 and canvas.is_key_down(key2)) then
        last_input_device = "keyboard"
        return true
    end
    if canvas.get_gamepad_button(1, gamepad_button) > 0 then
        last_input_device = "gamepad"
        return true
    end
    return false
end

--- Check if settings/pause menu input was pressed this frame (not rebindable)
---@return boolean pressed True if ESCAPE or gamepad START was pressed
function controls.settings_pressed()
    return check_menu_input_pressed(canvas.keys.ESCAPE, nil, canvas.buttons.START)
end

--- Check if menu up navigation was pressed this frame (not rebindable)
---@return boolean pressed True if W, UP arrow, or gamepad DPAD_UP was pressed
function controls.menu_up_pressed()
    return check_menu_input_pressed(canvas.keys.W, canvas.keys.UP, canvas.buttons.DPAD_UP)
end

--- Check if menu down navigation was pressed this frame (not rebindable)
---@return boolean pressed True if S, DOWN arrow, or gamepad DPAD_DOWN was pressed
function controls.menu_down_pressed()
    return check_menu_input_pressed(canvas.keys.S, canvas.keys.DOWN, canvas.buttons.DPAD_DOWN)
end

--- Check if menu left navigation was pressed this frame (not rebindable)
---@return boolean pressed True if A, LEFT arrow, or gamepad DPAD_LEFT was pressed
function controls.menu_left_pressed()
    return check_menu_input_pressed(canvas.keys.A, canvas.keys.LEFT, canvas.buttons.DPAD_LEFT)
end

--- Check if menu left navigation is currently held (not rebindable)
---@return boolean down True if A, LEFT arrow, or gamepad DPAD_LEFT is held
function controls.menu_left_down()
    return check_menu_input_down(canvas.keys.A, canvas.keys.LEFT, canvas.buttons.DPAD_LEFT)
end

--- Check if menu right navigation was pressed this frame (not rebindable)
---@return boolean pressed True if D, RIGHT arrow, or gamepad DPAD_RIGHT was pressed
function controls.menu_right_pressed()
    return check_menu_input_pressed(canvas.keys.D, canvas.keys.RIGHT, canvas.buttons.DPAD_RIGHT)
end

--- Check if menu right navigation is currently held (not rebindable)
---@return boolean down True if D, RIGHT arrow, or gamepad DPAD_RIGHT is held
function controls.menu_right_down()
    return check_menu_input_down(canvas.keys.D, canvas.keys.RIGHT, canvas.buttons.DPAD_RIGHT)
end

--- Check if menu confirm input was pressed this frame (not rebindable)
---@return boolean pressed True if SPACE, ENTER, or gamepad SOUTH was pressed
function controls.menu_confirm_pressed()
    return check_menu_input_pressed(canvas.keys.SPACE, canvas.keys.ENTER, canvas.buttons.SOUTH)
end

--- Check if menu back/cancel input was pressed this frame (not rebindable)
---@return boolean pressed True if ESCAPE or gamepad EAST was pressed
function controls.menu_back_pressed()
    return check_menu_input_pressed(canvas.keys.ESCAPE, nil, canvas.buttons.EAST)
end

--- Update input mode based on mouse movement
--- Call this each frame before processing mouse input
---@return nil
function controls.update_mouse_activity()
    local mx, my = canvas.get_mouse_x(), canvas.get_mouse_y()

    if last_mouse_x ~= nil then
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            last_input_device = "mouse"
        end
    end

    last_mouse_x = mx
    last_mouse_y = my
end

--- Check if mouse input is currently active
---@return boolean True if mouse is the last used input device
function controls.is_mouse_active()
    return last_input_device == "mouse"
end

--- Get the binding scheme for the current input device
--- Maps "mouse" to "keyboard" since they share the same bindings
---@return string "keyboard" or "gamepad"
function controls.get_binding_scheme()
    if last_input_device == "gamepad" then
        return "gamepad"
    end
    return "keyboard"
end

--- Expand {action} placeholders in text to key/button names
--- Uses the current binding scheme to determine which binding to show
---@param text string Text with {action} placeholders (e.g., "Press {block} to block")
---@return string Text with placeholders replaced by key/button names
function controls.expand_bindings(text)
    if not text then return "" end
    local scheme = controls.get_binding_scheme()
    return text:gsub("{([%w_]+)}", function(action_id)
        local name = controls.get_binding_name(scheme, action_id)
        return name or ("{" .. action_id .. "}")
    end)
end

-- Initialize with defaults on load
controls.init()

return controls
