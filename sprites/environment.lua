local canvas = require("canvas")

--- Environment sprite asset keys.
---@type table<string, string>
local environment = {
	tilemap = "tilemap",
	ladder_top = "ladder_top",
	ladder_mid = "ladder_mid",
	ladder_bottom = "ladder_bottom",
	sign = "sign",
	bridge_left = "bridge_left",
	bridge_middle = "bridge_middle",
	bridge_right = "bridge_right",
	spikes = "spikes",
	button = "button",
	campfire = "campfire",
	trap_door = "trap_door",
	trap_door_open = "trap_door_open",
	trap_door_reset = "trap_door_reset"
}

canvas.assets.load_image(environment.tilemap, "images/tilemap_packed.png")
canvas.assets.load_image(environment.ladder_top, "sprites/environment/ladder_top.png")
canvas.assets.load_image(environment.ladder_mid, "sprites/environment/ladder_mid.png")
canvas.assets.load_image(environment.ladder_bottom, "sprites/environment/ladder_bottom.png")
canvas.assets.load_image(environment.sign, "sprites/environment/sign.png")
canvas.assets.load_image(environment.bridge_left, "sprites/environment/bridge-left.png")
canvas.assets.load_image(environment.bridge_middle, "sprites/environment/bridge-middle.png")
canvas.assets.load_image(environment.bridge_right, "sprites/environment/bridge-right.png")
canvas.assets.load_image(environment.spikes, "sprites/environment/spikes-retract.png")
canvas.assets.load_image(environment.button, "sprites/environment/button.png")
canvas.assets.load_image(environment.campfire, "sprites/environment/campfire.png")
canvas.assets.load_image(environment.trap_door, "sprites/environment/trap_door.png")
canvas.assets.load_image(environment.trap_door_open, "sprites/environment/trap_door_open.png")
canvas.assets.load_image(environment.trap_door_reset, "sprites/environment/trap_door_reset.png")


return environment
