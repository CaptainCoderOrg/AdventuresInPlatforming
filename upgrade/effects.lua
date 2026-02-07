--- Centralized stat lookups for upgrade effects
--- Game systems call these instead of reading hardcoded values.
--- Additive effects ("_add" suffix) are summed across purchased tiers.
--- Override effects use the latest purchased tier's value.

local upgrade_registry = require("upgrade/registry")

local effects = {}

--- Collect all effects from purchased tiers for an item
---@param player table Player instance
---@param item_id string Item identifier
---@return table Map of effect_key -> value (additive keys summed, overrides use latest)
local function collect_effects(player, item_id)
    local result = {}
    if not player.upgrade_tiers then return result end
    local tier_num = player.upgrade_tiers[item_id] or 0
    if tier_num == 0 then return result end

    local def = upgrade_registry.get(item_id)
    if not def then return result end

    for i = 1, math.min(tier_num, #def.tiers) do
        local tier = def.tiers[i]
        if tier.effects then
            for key, value in pairs(tier.effects) do
                if key:sub(-4) == "_add" then
                    result[key] = (result[key] or 0) + value
                else
                    result[key] = value
                end
            end
        end
    end
    return result
end

--- Get effective weapon damage (base + additive bonuses from upgrades)
---@param player table Player instance
---@param weapon_id string Weapon item ID
---@param base_damage number Base damage from weapon stats
---@return number Effective damage
function effects.get_weapon_damage(player, weapon_id, base_damage)
    local fx = collect_effects(player, weapon_id)
    return base_damage + (fx.weapon_damage_add or 0)
end

--- Get effective heal rate (override from upgrades, or default)
---@param player table Player instance
---@return number Heal rate multiplier
function effects.get_heal_rate(player)
    local fx = collect_effects(player, "minor_healing")
    return fx.heal_rate or 0.5
end

--- Get effective energy ratio (override from upgrades, or default 1:1)
---@param player table Player instance
---@return number Energy-to-health ratio
function effects.get_energy_ratio(player)
    local fx = collect_effects(player, "minor_healing")
    return fx.energy_ratio or 2
end

--- Get effective projectile damage (override from upgrades, or base)
---@param player table Player instance
---@param item_id string Secondary item ID
---@param base_damage number Base projectile damage
---@return number Effective damage
function effects.get_projectile_damage(player, item_id, base_damage)
    local fx = collect_effects(player, item_id)
    return fx.projectile_damage or base_damage
end

--- Get effective recharge time (override from upgrades, or base)
---@param player table Player instance
---@param item_id string Secondary item ID
---@param base_recharge number Base recharge time in seconds
---@return number Effective recharge time
function effects.get_recharge(player, item_id, base_recharge)
    local fx = collect_effects(player, item_id)
    return fx.recharge or base_recharge
end

return effects
