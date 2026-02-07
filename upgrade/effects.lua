--- Centralized stat lookups for upgrade effects
--- Game systems call these instead of reading hardcoded values.
--- Additive effects ("_add" suffix) are summed across purchased tiers.
--- Override effects use the latest purchased tier's value.

local upgrade_registry = require("upgrade/registry")

local effects = {}

-- Shared tables to avoid per-call allocation in collect_effects()
local _empty = {}
local _result = {}

--- Collect all effects from purchased tiers for an item
---@param player table Player instance
---@param item_id string Item identifier
---@return table Map of effect_key -> value (additive keys summed, overrides use latest)
local function collect_effects(player, item_id)
    if not player.upgrade_tiers then return _empty end
    local tier_num = player.upgrade_tiers[item_id] or 0
    if tier_num == 0 then return _empty end

    local def = upgrade_registry.get(item_id)
    if not def then return _empty end

    for k in pairs(_result) do _result[k] = nil end

    for i = 1, math.min(tier_num, #def.tiers) do
        local tier = def.tiers[i]
        if tier.effects then
            for key, value in pairs(tier.effects) do
                if key:sub(-4) == "_add" then
                    _result[key] = (_result[key] or 0) + value
                else
                    _result[key] = value
                end
            end
        end
    end
    return _result
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

--- Get effective heal rate and energy ratio in a single lookup
---@param player table Player instance
---@return number heal_rate HP per second
---@return number energy_ratio Energy cost per HP healed
function effects.get_heal_params(player)
    local fx = collect_effects(player, "minor_healing")
    return fx.heal_rate or 0.5, fx.energy_ratio or 2
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
---@return number Effective recharge time in seconds
function effects.get_recharge(player, item_id, base_recharge)
    local fx = collect_effects(player, item_id)
    return fx.recharge or base_recharge
end

return effects
