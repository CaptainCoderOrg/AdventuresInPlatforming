--- Item sprite asset keys.
--- Returns a table mapping item names to canvas asset keys.
local canvas = require("canvas")

-- Asset key to path mapping (items in sprites/items/, throwables in sprites/throwables/)
local asset_paths = {
    item_shield = "sprites/items/shield.png",
    item_amulet = "sprites/items/amulet.png",
    item_boots = "sprites/items/boots.png",
    item_hammer = "sprites/items/hammer.png",
    item_jump_ring = "sprites/items/jump_ring.png",
    item_sword = "sprites/items/sword.png",
    item_longsword = "sprites/items/longsword.png",
    item_elven_blade = "sprites/items/elven_blade.png",
    item_great_sword = "sprites/items/great_sword.png",
    item_axe_icon = "sprites/throwables/axe_icon.png",
    item_shuriken_icon = "sprites/throwables/shuriken_icon.png",
    item_brass_key = "sprites/items/brass-key.png",
    item_old_key = "sprites/items/old-key.png",
}

for key, path in pairs(asset_paths) do
    canvas.assets.load_image(key, path)
end

--- Map of item names to loaded canvas asset keys
---@type table<string, string>
return {
    shield = "item_shield",
    amulet = "item_amulet",
    boots = "item_boots",
    hammer = "item_hammer",
    jump_ring = "item_jump_ring",
    sword = "item_sword",
    longsword = "item_longsword",
    elven_blade = "item_elven_blade",
    great_sword = "item_great_sword",
    axe_icon = "item_axe_icon",
    shuriken_icon = "item_shuriken_icon",
    brass_key = "item_brass_key",
    old_key = "item_old_key",
}
