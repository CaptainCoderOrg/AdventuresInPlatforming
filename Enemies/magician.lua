--- Red Magician enemy: A flying mage that casts homing projectiles at the player.
--- States: idle (float in place), attack (cast spell), fly (reposition),
---         disappear (dodge projectiles via teleport), death
--- Flying enemy (no gravity). Health: 6 HP. Contact damage: 0.5 (0 during fade states).
local magician_common = require("Enemies/magician_common")
local sprites = require("sprites")

return magician_common.create(sprites.enemies.magician)
