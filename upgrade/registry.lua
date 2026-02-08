--- Upgrade tier definitions for equipment enhancement
--- Maps item IDs to arrays of tiered upgrades with costs, materials, and effects.
--- Effect key convention: "_add" suffix = additive (summed), others = absolute override.

local registry = {}

registry.sword = {
    label = "Enchant",
    description = "Enchant shortsword to increase its power.",
    tiers = {
        { gold = 10,  effects = { weapon_damage_add = 0.2 },
          result = "I was able to increase the damage of the shortsword." },
        { gold = 50,  effects = { weapon_damage_add = 0.3 },
          result = "The enchantment grows stronger..." },
        { gold = 100, material = "arcane_shard", effects = { weapon_damage_add = 1.0 },
          result = "A powerful dark energy flows through the blade now." },
    },
}

registry.minor_healing = {
    label = "Study",
    description = "Study with Zabarbra increasing the spell's efficiency.",
    tiers = {
        { gold = 25,  effects = { heal_rate = 1 },
          result = "Now you will heal faster." },
        { gold = 100, effects = { energy_ratio = 1.5 },
          result = "Your energy flows more efficiently now." },
        { gold = 250, material = "arcane_shard", effects = { heal_rate = 1.5, energy_ratio = 1 },
          result = "Life force surges through you with incredible speed." },
    },
}

registry.longsword = {
    label = "Enchant",
    description = "Enchant longsword to increase its power.",
    tiers = {
        { gold = 50,  effects = { weapon_damage_add = 0.5, stamina_cost_add = -0.25 },
          result = "The blade feels lighter and strikes harder." },
        { gold = 200, effects = { weapon_damage_add = 0.5, ms_per_frame = 70 },
          result = "The enchantment quickens the blade's swing." },
        { gold = 500, material = "arcane_shard", effects = { weapon_damage_add = 1.0, stamina_cost_add = -0.25, ms_per_frame = 60 },
          result = "A masterwork edge. Swift, deadly, and effortless." },
    },
}

registry.throwing_axe = {
    label = "Enchant",
    description = "Imbue throwing axes to increase their power.",
    tiers = {
        { gold = 50,  effects = { projectile_damage = 2 },
          result = "The axes strike with renewed vigor." },
        { gold = 150, effects = { recharge = 1.5 },
          result = "The enchantment hastens the axe's return." },
        { gold = 500, material = "arcane_shard", effects = { projectile_damage = 3 },
          result = "Devastatingly heavy. These will crush anything." },
    },
}

registry.shuriken = {
    label = "Enchant",
    description = "Imbue shurikens with arcane power.",
    tiers = {
        { gold = 50,  effects = { max_charges_add = 2, projectile_damage = 3 },
          result = "The shurikens multiply and strike with greater force." },
        { gold = 200, effects = { max_charges_add = 2, energy_cost = 0.5 },
          result = "The summoning requires less energy now." },
        { gold = 500, material = "arcane_shard", effects = { max_charges_add = 2, projectile_damage = 4, energy_cost = 0 },
          result = "Pure arcane energy. Infinite shurikens at no cost." },
    },
}

registry.dash_amulet = {
    label = "Enchant",
    description = "Imbue the Dash Amulet with arcane energy.",
    tiers = {
        { gold = 150, material = "arcane_shard", effects = { dash_invulnerable = true },
          result = "The amulet pulses with a protective aura. You will be invulnerable while dashing." },
    },
}

--- Stable display order for upgrade UI
registry.DISPLAY_ORDER = { "sword", "longsword", "minor_healing", "throwing_axe", "shuriken", "dash_amulet" }

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
