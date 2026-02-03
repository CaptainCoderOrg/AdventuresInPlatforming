--- Registry of stackable items (consumables like keys)
--- These items stack in inventory and are consumed on use
local sprites = require("sprites")
local audio = require("audio")

---@class StackableItemDef
---@field name string Display name
---@field description string|nil Item description
---@field static_sprite string Sprite for inventory display
---@field collect_sfx string|nil Sound effect on collection
---@field max_stack number|nil Maximum stack size (default: 99)

---@type table<string, StackableItemDef>
return {
    dungeon_key = {
        name = "Dungeon Key",
        description = "A key found in the depths beneath the Adept's cottage.",
        static_sprite = sprites.items.dungeon_key,
        collect_sfx = audio.pick_up_key,
        max_stack = 99,
    },
}
