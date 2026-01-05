local canvas = require('canvas')
local controls = {}

function controls.jump_pressed() return canvas.is_key_pressed(canvas.keys.SPACE) or canvas.is_mouse_pressed(0) end
function controls.left_down() return canvas.is_key_down(canvas.keys.A) end
function controls.right_down() return canvas.is_key_down(canvas.keys.D) end
function controls.dash_pressed() return canvas.is_key_pressed(canvas.keys.SHIFT) or canvas.is_key_pressed(canvas.keys.K) or canvas.is_mouse_pressed(2) end
function controls.attack_pressed() return canvas.is_key_pressed(canvas.keys.J) end

return controls