--- Purple Magician enemy: A flying mage variant with a 3-bolt burst shot.
--- Plays attack animation 3 times, each firing a non-homing bolt at the player's current position.
--- Flying enemy (no gravity). Health: 6 HP. Contact damage: 0.5 (0 during fade states).
local magician_common = require("Enemies/magician_common")
local sprites = require("sprites")

return magician_common.create(sprites.enemies.magician_purple, { burst_shot = true })
