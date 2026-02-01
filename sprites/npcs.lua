--- NPC sprite asset keys.
local canvas = require("canvas")

---@type table<string, string>
local npcs = {}

--- Register an NPC sprite asset (key equals asset name)
---@param name string Asset key and filename (without extension)
local function register(name)
    npcs[name] = name
    canvas.assets.load_image(name, "sprites/npcs/" .. name .. ".png")
end

register("witch_merchant_idle")
register("explorer_idle")
register("adept_reading")

return npcs
