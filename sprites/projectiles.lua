local canvas = require("canvas")

--- Projectile sprite asset keys.
---@type table<string, string>
local projectiles = {
	axe = "throwable_axe",
	shuriken = "shuriken",
}

canvas.assets.load_image(projectiles.axe, "sprites/throwables/throwable_axe.png")
canvas.assets.load_image(projectiles.shuriken, "sprites/throwables/shuriken.png")

return projectiles
