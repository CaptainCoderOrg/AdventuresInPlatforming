local canvas = require("canvas")

--- Environment sprite asset keys.
---@type table<string, string>
local environment = {
	tilemap = "tilemap",
	ladder_top = "ladder_top",
	ladder_mid = "ladder_mid",
	ladder_bottom = "ladder_bottom",
}

canvas.assets.load_image(environment.tilemap, "images/tilemap_packed.png")
canvas.assets.load_image(environment.ladder_top, "sprites/environment/ladder_top.png")
canvas.assets.load_image(environment.ladder_mid, "sprites/environment/ladder_mid.png")
canvas.assets.load_image(environment.ladder_bottom, "sprites/environment/ladder_bottom.png")

return environment
