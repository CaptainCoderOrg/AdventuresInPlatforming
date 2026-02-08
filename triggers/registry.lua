--- Trigger Registry: Static mapping of trigger names to handler functions.
--- Canvas requires static analysis for bundling, so we can't dynamically require paths.
--- Convention: trigger name uses dots matching module.function (e.g., "Module.on_start" -> module.on_start)

local gnomo = require("Enemies/Bosses/gnomo")
local valkyrie = require("Enemies/Bosses/valkyrie")

return {
    ["Enemies.Bosses.gnomo.on_start"] = gnomo.on_start,
    ["Enemies.Bosses.valkyrie.on_start"] = valkyrie.on_start,
}
