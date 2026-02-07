--- Purple Magician enemy: A flying mage variant with green projectiles.
--- Identical behavior to red magician. Uses magician_purple sprite sheet.
--- Flying enemy (no gravity). Health: 6 HP. No contact damage.
local magician_common = require("Enemies/magician_common")
local sprites = require("sprites")

return magician_common.create(sprites.enemies.magician_purple)
