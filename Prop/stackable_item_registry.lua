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
---@field first_collect {flag: string, journal: string}|nil First-time collection config (sets flag and adds journal entry)

---@type table<string, StackableItemDef>
return {
    dungeon_key = {
        name = "Dungeon Key",
        description = "A key found in the depths beneath the Adept's cottage.",
        static_sprite = sprites.items.dungeon_key,
        collect_sfx = audio.pick_up_key,
        max_stack = 99,
    },
    brass_key = {
        name = "Brass Key",
        description = "An ornate brass key.",
        static_sprite = sprites.items.brass_key,
        collect_sfx = audio.pick_up_key,
        max_stack = 99,
    },
    arcane_shard = {
        name = "Arcane Shard",
        description = "A crystallized fragment of pure magical energy. Maybe Zabarbra can do something with this.",
        static_sprite = sprites.items.arcane_shard,
        collect_sfx = audio.pick_up_key,
        max_stack = 99,
        first_collect = {
            flag = "found_arcane_shard",
            journal = "arcane_shard_quest",
        },
    },
}
