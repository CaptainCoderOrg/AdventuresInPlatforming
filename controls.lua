--- Unified input handling for keyboard and gamepad
local canvas = require("canvas")
local controls = {}

local TRIGGER_THRESHOLD = 0.1   -- Minimum trigger press to register as held
local CAMERA_DEADZONE = 0.15    -- Prevents stick drift on camera look

--- Check if projectile switch input was pressed this frame
---@return boolean pressed True if 0 key or gamepad SELECT was pressed
function controls.next_projectile_pressed()
	return canvas.is_key_pressed(canvas.keys.DIGIT_0)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.SELECT)
end

--- Check if throw input was pressed this frame
---@return boolean pressed True if L key or gamepad NORTH was pressed
function controls.throw_pressed()
	return canvas.is_key_pressed(canvas.keys.L)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.NORTH)
end

--- Check if hammer attack input was pressed this frame
---@return boolean pressed True if I key or gamepad EAST was pressed
function controls.hammer_pressed()
	return canvas.is_key_pressed(canvas.keys.I)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.EAST)
end

--- Check if block input is currently held down
---@return boolean down True if U key or gamepad RT is held
function controls.block_down()
	return canvas.is_key_down(canvas.keys.U)
		or canvas.get_gamepad_button(1, canvas.buttons.RT) > TRIGGER_THRESHOLD
end

--- Check if up directional input is currently held
---@return boolean down True if W key or gamepad DPAD_UP is held
function controls.up_down()
	return canvas.is_key_down(canvas.keys.W)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_UP) > 0
end

--- Check if down directional input is currently held
---@return boolean down True if S key or gamepad DPAD_DOWN is held
function controls.down_down()
	return canvas.is_key_down(canvas.keys.S)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_DOWN) > 0
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
---@return boolean pressed True if SPACE, gamepad SOUTH, or left mouse was pressed
function controls.jump_pressed()
	return canvas.is_key_pressed(canvas.keys.SPACE)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.SOUTH)
		or canvas.is_mouse_pressed(0)
end

--- Check if left movement input is currently held
---@return boolean down True if A key or gamepad DPAD_LEFT is held
function controls.left_down()
	return canvas.is_key_down(canvas.keys.A)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_LEFT) > 0
end

--- Check if right movement input is currently held
---@return boolean down True if D key or gamepad DPAD_RIGHT is held
function controls.right_down()
	return canvas.is_key_down(canvas.keys.D)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_RIGHT) > 0
end

--- Check if dash input was pressed this frame
---@return boolean pressed True if SHIFT, K, gamepad RB/LB, or right mouse was pressed
function controls.dash_pressed()
	return canvas.is_key_pressed(canvas.keys.SHIFT)
		or canvas.is_key_pressed(canvas.keys.K)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.RB)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.LB)
		or canvas.is_mouse_pressed(2)
end

--- Check if attack input was pressed this frame
---@return boolean pressed True if J key or gamepad WEST was pressed
function controls.attack_pressed()
	return canvas.is_key_pressed(canvas.keys.J)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.WEST)
end

--- Check if settings/pause menu input was pressed this frame
---@return boolean pressed True if ESCAPE or gamepad START was pressed
function controls.settings_pressed()
	return canvas.is_key_pressed(canvas.keys.ESCAPE)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.START)
end

--- Check if menu up navigation was pressed this frame
---@return boolean pressed True if W, UP arrow, or gamepad DPAD_UP was pressed
function controls.menu_up_pressed()
	return canvas.is_key_pressed(canvas.keys.W)
		or canvas.is_key_pressed(canvas.keys.UP)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.DPAD_UP)
end

--- Check if menu down navigation was pressed this frame
---@return boolean pressed True if S, DOWN arrow, or gamepad DPAD_DOWN was pressed
function controls.menu_down_pressed()
	return canvas.is_key_pressed(canvas.keys.S)
		or canvas.is_key_pressed(canvas.keys.DOWN)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.DPAD_DOWN)
end

--- Check if menu left navigation was pressed this frame
---@return boolean pressed True if A, LEFT arrow, or gamepad DPAD_LEFT was pressed
function controls.menu_left_pressed()
	return canvas.is_key_pressed(canvas.keys.A)
		or canvas.is_key_pressed(canvas.keys.LEFT)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.DPAD_LEFT)
end

--- Check if menu left navigation is currently held
---@return boolean down True if A, LEFT arrow, or gamepad DPAD_LEFT is held
function controls.menu_left_down()
	return canvas.is_key_down(canvas.keys.A)
		or canvas.is_key_down(canvas.keys.LEFT)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_LEFT) > 0
end

--- Check if menu right navigation was pressed this frame
---@return boolean pressed True if D, RIGHT arrow, or gamepad DPAD_RIGHT was pressed
function controls.menu_right_pressed()
	return canvas.is_key_pressed(canvas.keys.D)
		or canvas.is_key_pressed(canvas.keys.RIGHT)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.DPAD_RIGHT)
end

--- Check if menu right navigation is currently held
---@return boolean down True if D, RIGHT arrow, or gamepad DPAD_RIGHT is held
function controls.menu_right_down()
	return canvas.is_key_down(canvas.keys.D)
		or canvas.is_key_down(canvas.keys.RIGHT)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_RIGHT) > 0
end

--- Check if menu confirm input was pressed this frame
---@return boolean pressed True if SPACE, ENTER, or gamepad SOUTH was pressed
function controls.menu_confirm_pressed()
	return canvas.is_key_pressed(canvas.keys.SPACE)
		or canvas.is_key_pressed(canvas.keys.ENTER)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.SOUTH)
end

return controls
