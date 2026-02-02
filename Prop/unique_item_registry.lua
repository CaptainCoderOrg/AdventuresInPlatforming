--- Registry of all unique items and their sprite/animation configurations
--- Animated items have animated_sprite/collected_sprite, static items have static_sprite
--- Equipment types: "shield", "weapon", "secondary", "accessory", "no_equip"
--- Only 1 shield, weapon, or secondary can be equipped at a time. Any number of accessories allowed.
local sprites = require("sprites")
local audio = require("audio")

---@class UniqueItemDef
---@field name string Display name
---@field description string|nil Item description (supports {action} keybinding placeholders)
---@field type string|nil Equipment type: "shield", "weapon", "secondary", "accessory", "no_equip"
---@field stats table|nil Weapon combat stats: damage, stamina_cost, attack_type, hitbox, ms_per_frame, animation, active_frames, can_hit_buttons
---@field static_sprite string|nil Sprite for non-animated items
---@field animated_sprite string|nil Sprite sheet for animated items
---@field collected_sprite string|nil Animation played when collected
---@field animated_frames number|nil Frame count for animated sprite
---@field collected_frames number|nil Frame count for collected animation
---@field collect_sfx string|nil Sound effect on collection

---@type table<string, UniqueItemDef>
return {
    gold_key = {
        name = "Gold Key",
        description = "Opens golden locks.",
        type = "no_equip",
        animated_sprite = sprites.environment.gold_key_spin,
        collected_sprite = sprites.environment.gold_key_collected,
        animated_frames = 8,
        collected_frames = 5,
        collect_sfx = audio.pick_up_key,
    },
    shield = {
        name = "Shield",
        description = "Block incoming attacks using {block}. Blocking drains stamina preventing damage. A perfectly timed block will use no stamina.",
        type = "shield",
        static_sprite = sprites.items.shield,
    },
    dash_amulet = {
        name = "Dash Amulet",
        description = "Grants the ability to dash through the air using {dash}.",
        type = "accessory",
        static_sprite = sprites.items.amulet,
    },
    grip_boots = {
        name = "Grip Boots",
        description = "Cling to walls and slide down slowly. Press {jump} while sliding to perform a wall jump.",
        type = "accessory",
        static_sprite = sprites.items.boots,
    },
    hammer = {
        name = "Sledge Hammer",
        description = "A slow but heavy weapon that can smash buttons and enemies.",
        type = "weapon",
        static_sprite = sprites.items.hammer,
        stats = {
            damage = 5,
            stamina_cost = 5,
            attack_type = "heavy",
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            active_frames = { min = 3, max = 4 },
            can_hit_buttons = true,
        },
    },
    jump_ring = {
        name = "Jump Ring",
        description = "Grants the ability to jump mid air pressing {jump}.",
        type = "accessory",
        static_sprite = sprites.items.jump_ring,
    },
    sword = {
        name = "Shortsword",
        description = "A fast lightweight blade that uses little stamina but has a short reach.",
        type = "weapon",
        animated_sprite = sprites.items.sword,
        animated_frames = 12,
        stats = {
            damage = 1,
            stamina_cost = 1.5,
            attack_type = "combo",
            animation = "short",
            hitbox = { width = 0.7, height = 1.1, y_offset = -0.1 },
            ms_per_frame = 60,
        },
    },
    longsword = {
        name = "Longsword",
        description = "The blade of choice for most fighters. Slower than shortsword and uses more stamina but deals more damage and has a longer reach.",
        type = "weapon",
        static_sprite = sprites.items.longsword,
        stats = {
            damage = 2,
            stamina_cost = 2.5,
            attack_type = "combo",
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            ms_per_frame = 80,
        },
    },
    elven_blade = {
        name = "Elven Blade",
        description = "The fine craftsmanship of this blade makes it incredibly light. It is faster and uses less stamina while being just as deadly as a longsword.",
        type = "weapon",
        static_sprite = sprites.items.elven_blade,
        stats = {
            damage = 2,
            stamina_cost = 1.5,
            attack_type = "combo",
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            ms_per_frame = 70,
        },
    },
    great_sword = {
        name = "Greatsword",
        description = "A massive two-handed sword with devastating power. Slower than a longsword but has a greater reach.",
        type = "weapon",
        static_sprite = sprites.items.great_sword,
        stats = {
            damage = 5,
            stamina_cost = 4,
            attack_type = "combo",
            animation = "wide",
            hitbox = { width = 1.7, height = 1.2, y_offset = -0.15 },
            ms_per_frame = 90,
        },
    },
    throwing_axe = {
        name = "Throwing Axe",
        description = "A simple projectile that can be thrown.",
        type = "secondary",
        static_sprite = sprites.items.axe_icon,
    },
    shuriken = {
        name = "Summon Shuriken",
        description = "Spend energy to summon a magic shuriken.",
        type = "secondary",
        static_sprite = sprites.items.shuriken_icon,
    },
}
