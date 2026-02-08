--- Blue Magician enemy: A flying mage variant with a 3-bolt spread shot.
--- Fires three non-homing bolts in a fan pattern (+45, 0, -45 degrees).
--- Flying enemy (no gravity). Health: 6 HP. Contact damage: 0.5 (0 during fade states).
local magician_common = require("Enemies/magician_common")
local sprites = require("sprites")

return magician_common.create(sprites.enemies.magician_blue, { spread_shot = true })
