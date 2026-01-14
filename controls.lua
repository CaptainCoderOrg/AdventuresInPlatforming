local canvas = require("canvas")
local controls = {}

function controls.next_projectile_pressed()
	return canvas.is_key_pressed(canvas.keys.DIGIT_0) 
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.SELECT)
end

function controls.throw_pressed()
	return canvas.is_key_pressed(canvas.keys.L)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.NORTH)
end

function controls.hammer_pressed()
	return canvas.is_key_pressed(canvas.keys.I)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.EAST)
end

function controls.block_down()
	return canvas.is_key_down(canvas.keys.U)
		or canvas.get_gamepad_button(1, canvas.buttons.RT) > 0.1
end

function controls.up_down()
	return canvas.is_key_down(canvas.keys.W)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_UP) > 0
end

function controls.down_down()
	return canvas.is_key_down(canvas.keys.S)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_DOWN) > 0
end

-- Camera look controls (right analog stick)
-- X: -1 (left) to +1 (right), Y: -1 (up) to +1 (down)
function controls.get_camera_look_x()
	local right_stick_x = canvas.get_gamepad_axis(1, canvas.axes.RIGHT_STICK_X)
	if math.abs(right_stick_x) < 0.15 then return 0 end
	return right_stick_x
end

function controls.get_camera_look_y()
	local right_stick_y = canvas.get_gamepad_axis(1, canvas.axes.RIGHT_STICK_Y)
	if math.abs(right_stick_y) < 0.15 then return 0 end
	return right_stick_y
end

function controls.jump_pressed()
	return canvas.is_key_pressed(canvas.keys.SPACE)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.SOUTH)
		or canvas.is_mouse_pressed(0)
end

function controls.left_down()
	return canvas.is_key_down(canvas.keys.A)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_LEFT) > 0
end
function controls.right_down()
	return canvas.is_key_down(canvas.keys.D)
		or canvas.get_gamepad_button(1, canvas.buttons.DPAD_RIGHT) > 0
end

function controls.dash_pressed()
	return canvas.is_key_pressed(canvas.keys.SHIFT)
		or canvas.is_key_pressed(canvas.keys.K)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.RB)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.LB)
		or canvas.is_mouse_pressed(2)
end

function controls.attack_pressed()
	return canvas.is_key_pressed(canvas.keys.J)
		or canvas.is_gamepad_button_pressed(1, canvas.buttons.WEST)
end

return controls
