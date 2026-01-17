local canvas = require("canvas")

--- Effect sprite asset keys.
---@type table<string, string>
local effects = {
	hit = "effect_hit",
	shuriken_hit = "shuriken_hit",
}

canvas.assets.load_image(effects.hit, "sprites/effects/hit.png")
canvas.assets.load_image(effects.shuriken_hit, "sprites/effects/shuriken_hit.png")

return effects
