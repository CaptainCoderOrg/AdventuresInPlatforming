--- Registry of all unique items and their sprite/animation configurations
--- Animated items have animated_sprite/collected_sprite, static items have static_sprite
--- Equipment types: "weapon", "secondary", "accessory", "no_equip", "usable"
--- Only 1 weapon can be equipped at a time. Any number of accessories allowed.
local sprites = require("sprites")
local audio = require("audio")

---@class UniqueItemDef
---@field name string Display name
---@field description string|nil Item description (supports {action} keybinding placeholders)
---@field type string|nil Equipment type: "weapon", "secondary", "accessory", "no_equip", "usable"
---@field stats table|nil Weapon combat stats: damage, stamina_cost, hitbox, ms_per_frame, animation, active_frames, can_hit_buttons
---@field static_sprite string|nil Sprite for non-animated items
---@field animated_sprite string|nil Sprite sheet for animated items
---@field collected_sprite string|nil Animation played when collected
---@field animated_frames number|nil Frame count for animated sprite
---@field collected_frames number|nil Frame count for collected animation
---@field collect_sfx string|nil Sound effect on collection
---@field max_charges number|nil Max charges for charge-based secondaries (nil = unlimited)
---@field recharge number|nil Seconds per charge to recharge (required if max_charges is set)

---@type table<string, UniqueItemDef>
return {
    gold_key = {
        name = "Gold Key",
        description = "A beautiful golden key.",
        type = "no_equip",
        animated_sprite = sprites.environment.gold_key_spin,
        collected_sprite = sprites.environment.gold_key_collected,
        animated_frames = 8,
        collected_frames = 5,
        collect_sfx = audio.pick_up_key,
    },
    old_key = {
        name = "Old Key",
        description = "A weathered iron key.",
        type = "no_equip",
        static_sprite = sprites.items.old_key,
        collect_sfx = audio.pick_up_key,
    },
    shield = {
        name = "Shield",
        description = "Block incoming attacks. Blocking drains stamina preventing damage. A perfectly timed block will use no stamina. Assign to an ability slot to use.",
        type = "secondary",
        static_sprite = sprites.items.shield,
    },
    dash_amulet = {
        name = "Dash Amulet",
        description = "Grants the ability to dash through the air. Assign to an ability slot to use.",
        type = "secondary",
        static_sprite = sprites.items.amulet,
        max_charges = 1,
        recharge = 1,
    },
    grip_boots = {
        name = "Grip Boots",
        description = "Cling to walls and slide down slowly. Press {jump} while sliding to perform a wall jump.",
        type = "accessory",
        static_sprite = sprites.items.boots,
    },
    hammer = {
        name = "Sledge Hammer",
        description = "A heavy hammer that can smash buttons and enemies. Assign to an ability slot to use.",
        type = "secondary",
        static_sprite = sprites.items.hammer,
        stats = {
            damage = 5,
            stamina_cost = 8,
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            active_frames = { min = 3, max = 4 },
            can_hit_buttons = true,
        },
    },
    jump_ring = {
        name = "Jump Ring",
        description = "Grants the ability to jump midair: {jump} + {jump}.",
        type = "accessory",
        static_sprite = sprites.items.jump_ring,
    },
    sword = {
        name = "Shortsword",
        description = "A fast lightweight blade that uses little stamina but deals little damage. Press {attack} to attack.",
        type = "weapon",
        animated_sprite = sprites.items.sword,
        animated_frames = 12,
        stats = {
            damage = 1,
            stamina_cost = 1.5,
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            ms_per_frame = 60,
        },
    },
    longsword = {
        name = "Longsword",
        description = "The blade of choice for most fighters. Slower than shortsword and uses more stamina but deals more damage. Press {swap_weapon} to swap between equipped weapons.",
        type = "weapon",
        static_sprite = sprites.items.longsword,
        stats = {
            damage = 2.5,
            stamina_cost = 2.5,
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
            damage = 2.5,
            stamina_cost = 1.5,
            hitbox = { width = 1.2, height = 1.1, y_offset = -0.1 },
            ms_per_frame = 60,
        },
    },
    great_sword = {
        name = "Greatsword",
        description = "A massive two-handed sword with devastating power. Slower than a longsword but has a greater reach.",
        type = "weapon",
        static_sprite = sprites.items.great_sword,
        stats = {
            damage = 5,
            stamina_cost = 5,
            animation = "wide",
            hitbox = { width = 1.7, height = 1.2, y_offset = -0.15 },
            ms_per_frame = 90,
        },
    },
    throwing_axe = {
        name = "Throwing Axe",
        description = "A simple projectile that can be thrown. Assign to an ability slot, then press the slot's key to throw.",
        type = "secondary",
        static_sprite = sprites.items.axe_icon,
        max_charges = 2,
        recharge = 2,
    },
    shuriken = {
        name = "Summon Shuriken",
        description = "Spend energy to summon a magic shuriken. Assign to an ability slot to use.",
        type = "secondary",
        static_sprite = sprites.items.shuriken_icon,
        max_charges = 2,
        recharge = 5,
    },
    crystal_ball = {
        name = "Crystal Ball",
        description = "A mysterious orb that radiates magical energy.",
        type = "no_equip",
        static_sprite = sprites.items.crystal_ball,
        collect_sfx = audio.pick_up_key,
    },
    adept_key = {
        name = "Adept's Key",
        description = "A key given by the adept. Opens the chest behind him.",
        type = "no_equip",
        static_sprite = sprites.items.adept_key,
        collect_sfx = audio.pick_up_key,
    },
    adept_apology = {
        name = "Adept's Apology",
        description = "A letter containing an apology to the gnomos.",
        type = "no_equip",
        static_sprite = sprites.items.adept_apology,
        collect_sfx = audio.pick_up_key,
    },
    orb_of_teleportation = {
        name = "Orb of Teleportation",
        description = "A crystal ball imbued with magic allowing the user to teleport between previously visited campfires. Use at a campfire to fast travel.",
        type = "usable",
        static_sprite = sprites.items.orb_of_teleportation,
    },
    minor_healing = {
        name = "Minor Healing",
        description = "Hold the assigned ability key to slowly convert energy into health.",
        type = "secondary",
        static_sprite = sprites.items.minor_healing,
    },
}
