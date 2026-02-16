--- Upgrade tier definitions for equipment enhancement
--- Maps item IDs to arrays of tiered upgrades with costs, materials, and effects.
--- Effect key convention: "_add" suffix = additive (summed), others = absolute override.

local registry = {}

registry.sword = {
    label = "Enchant",
    description = "Enchant shortsword to increase its power.",
    tiers = {
        { gold = 7,   effects = { weapon_damage_add = 0.2 },
          result = "I was able to increase the damage of the shortsword." },
        { gold = 10,  effects = { weapon_damage_add = 0.3 },
          result = "The enchantment grows stronger..." },
        { gold = 35, material = "arcane_shard", effects = { weapon_damage_add = 0.5, stamina_cost = 0.5 },
          result = "A powerful dark energy flows through the blade now." },
    },
}

registry.minor_healing = {
    label = "Study",
    description = "Study with Zabarbra increasing the spell's efficiency.",
    tiers = {
        { gold = 18,  effects = { heal_rate = 1 },
          result = "Now you will heal faster." },
        { gold = 25,  effects = { energy_ratio = 1.5 },
          result = "Your energy flows more efficiently now." },
        { gold = 70, material = "arcane_shard", effects = { heal_rate = 3, energy_ratio = 1 },
          result = "Life force surges through you with incredible speed." },
    },
}

registry.longsword = {
    label = "Enchant",
    description = "Enchant longsword to increase its power.",
    tiers = {
        { gold = 35,  effects = { weapon_damage_add = 0.5, stamina_cost_add = -0.25 },
          result = "The blade feels lighter and strikes harder." },
        { gold = 75, effects = { weapon_damage_add = 0.5, ms_per_frame = 70 },
          result = "The enchantment quickens the blade's swing." },
        { gold = 100, material = "arcane_shard", effects = { weapon_damage_add = 1.0, stamina_cost_add = -0.25, ms_per_frame = 60 },
          result = "A masterwork edge. Swift, deadly, and effortless." },
    },
}

registry.throwing_axe = {
    label = "Enchant",
    description = "Imbue throwing axes to increase their power.",
    tiers = {
        { gold = 35,  effects = { recharge = 1.5, max_charges_add = 1 },
          result = "The enchantment hastens the axe's return." },
        { gold = 35, effects = { projectile_damage = 2, max_charges_add = 1, double_projectile = true },
          result = "The axes strike with renewed vigor." },
        { gold = 100, material = "arcane_shard", effects = { recharge = 1, max_charges_add = 1 },
          result = "The axes return almost instantly." },
    },
}

registry.shuriken = {
    label = "Study",
    description = "Imbue shurikens with arcane power.",
    tiers = {
        { gold = 35,  effects = { max_charges_add = 1, projectile_damage = 2.5 },
          result = "The shurikens strike with greater force." },
        { gold = 75, effects = { max_charges_add = 1, projectile_damage = 3, double_projectile = true },
          result = "The shurikens multiply and strike with greater force." },
        { gold = 100, material = "arcane_shard", effects = { max_charges_add = 1, projectile_damage = 3.5, penta_projectile = true },
          result = "Pure arcane energy. A storm of shurikens at your command." },
    },
}

registry.grip_boots = {
    label = "Enchant",
    description = "Enchant the Grip Boots with arcane energy.",
    tiers = {
        { gold = 35,  effects = { stamina_cost_add = -0.5 },
          result = "The boots grip tighter. Wall jumping requires less effort." },
        { gold = 75, effects = { wall_slide_delay = 1 },
          result = "The enchantment lets you cling to walls longer before sliding." },
        { gold = 100, material = "arcane_shard", effects = { stamina_cost = 0, wall_slide_delay = 2 },
          result = "You can hang on walls effortlessly for an extended time." },
    },
}

registry.hammer = {
    label = "Enchant",
    description = "Enchant the hammer to increase its power.",
    tiers = {
        { gold = 35,  effects = { weapon_damage_add = 5 },
          result = "The hammer strikes with greater force." },
        { gold = 75, effects = { stamina_cost_add = -4 },
          result = "The enchantment makes the hammer feel lighter." },
        { gold = 100, material = "arcane_shard", effects = { ms_per_frame = 112 },
          result = "The hammer swings with blinding speed." },
    },
}

registry.great_sword = {
    label = "Enchant",
    description = "Enchant greatsword to increase its power.",
    tiers = {
        { gold = 53,  effects = { weapon_damage_add = 1.5 },
          result = "The blade's edge gleams with arcane sharpness." },
        { gold = 120, effects = { weapon_damage_add = 1, stamina_cost_add = -1, ms_per_frame = 80 },
          result = "The blade strikes harder and feels lighter in your hands." },
        { gold = 100, material = "arcane_shard", effects = { weapon_damage_add = 2.5, stamina_cost_add = -1, ms_per_frame = 70 },
          result = "An unstoppable force. Each swing devastates with minimal effort." },
    },
}

registry.dash_amulet = {
    label = "Enchant",
    description = "Imbue the Dash Amulet with arcane energy.",
    tiers = {
        { gold = 35,  effects = { stamina_cost_add = -2 },
          result = "The amulet feels lighter. Dashing requires less effort." },
        { gold = 75, effects = { max_charges_add = 1 },
          result = "The amulet hums with energy. You can now dash twice before recharging." },
        { gold = 100, material = "arcane_shard", effects = { dash_invulnerable = true },
          result = "The amulet pulses with a protective aura. You will be invulnerable while dashing." },
    },
}

--- Stable display order for upgrade UI
registry.DISPLAY_ORDER = { "sword", "longsword", "minor_healing", "throwing_axe", "shuriken", "hammer", "great_sword", "grip_boots", "dash_amulet" }

-- Lookup set built from DISPLAY_ORDER (prevents get() from returning non-upgrade keys)
local VALID_ITEMS = {}
for _, id in ipairs(registry.DISPLAY_ORDER) do
    VALID_ITEMS[id] = true
end

--- Get upgrade definition for an item
---@param item_id string Item identifier
---@return table|nil Upgrade definition or nil if no upgrades exist
function registry.get(item_id)
    if VALID_ITEMS[item_id] then
        return registry[item_id]
    end
    return nil
end

--- Get list of upgradeable items the player owns
---@param player table Player instance
---@return table Array of {id, def} pairs for items with available upgrades
function registry.get_upgradeable_items(player)
    local items = {}
    for _, item_id in ipairs(registry.DISPLAY_ORDER) do
        local def = registry.get(item_id)
        if def then
            -- Check if player owns this item
            local owns = false
            if player.unique_items then
                for _, uid in ipairs(player.unique_items) do
                    if uid == item_id then
                        owns = true
                        break
                    end
                end
            end
            if player.equipped_items and player.equipped_items[item_id] then
                owns = true
            end
            if owns then
                items[#items + 1] = { id = item_id, def = def }
            end
        end
    end
    return items
end

return registry
