local canvas = require("canvas")

--- Projectile sprite asset keys.
---@type table<string, string>
local projectiles = {
	axe = "throwable_axe",
	shuriken = "shuriken",
	axe_icon = "axe_icon",
	shuriken_icon = "shuriken_icon",
}

canvas.assets.load_image(projectiles.axe, "sprites/throwables/throwable_axe.png")
canvas.assets.load_image(projectiles.shuriken, "sprites/throwables/shuriken.png")
canvas.assets.load_image(projectiles.axe_icon, "sprites/throwables/axe_icon.png")
canvas.assets.load_image(projectiles.shuriken_icon, "sprites/throwables/shuriken_icon.png")

return projectiles
