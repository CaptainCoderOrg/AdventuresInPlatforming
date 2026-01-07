local canvas = require("canvas")
local controls = {}

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
