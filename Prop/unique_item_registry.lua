--- Registry of all unique items and their sprite/animation configurations
--- Animated items have spin_sprite/collected_sprite, static items have static_sprite
local sprites = require("sprites")
local audio = require("audio")

---@type table<string, {name: string, static_sprite: string|nil, spin_sprite: string|nil, collected_sprite: string|nil, spin_frames: number|nil, collected_frames: number|nil, collect_sfx: string|nil}>
return {
    gold_key = {
        name = "Gold Key",
        spin_sprite = sprites.environment.gold_key_spin,
        collected_sprite = sprites.environment.gold_key_collected,
        spin_frames = 8,
        collected_frames = 5,
        collect_sfx = audio.pick_up_key,
    },
    shield = {
        name = "Shield",
        static_sprite = sprites.items.shield,
    },
    dash_amulet = {
        name = "Dash Amulet",
        static_sprite = sprites.items.amulet,
    },
    grip_boots = {
        name = "Grip Boots",
        static_sprite = sprites.items.boots,
    },
    hammer = {
        name = "Hammer",
        static_sprite = sprites.items.hammer,
    },
    jump_ring = {
        name = "Jump Ring",
        static_sprite = sprites.items.jump_ring,
    },
    sword = {
        name = "Sword",
        static_sprite = sprites.items.sword,
    },
    throwing_axe = {
        name = "Throwing Axe",
        static_sprite = sprites.items.axe_icon,
    },
    shuriken = {
        name = "Shuriken",
        static_sprite = sprites.items.shuriken_icon,
    },
}
