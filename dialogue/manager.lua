--- Dialogue state tracking and condition evaluation
--- Flags are stored directly on the player object for persistence
local journal_toast = require("ui/journal_toast")

local manager = {}

-- Reference to current player for flag storage
local player_ref = nil

--- Set the player reference for flag storage
---@param player table Player instance
function manager.set_player(player)
    player_ref = player
    -- Ensure dialogue_flags table exists on player
    if player_ref and not player_ref.dialogue_flags then
        player_ref.dialogue_flags = {}
    end
end

--- Set a dialogue flag
---@param flag_name string Name of the flag to set
---@param value boolean|nil Value to set (defaults to true)
function manager.set_flag(flag_name, value)
    if not player_ref then return end
    if not player_ref.dialogue_flags then
        player_ref.dialogue_flags = {}
    end
    if value == nil then value = true end
    player_ref.dialogue_flags[flag_name] = value
end

--- Get a dialogue flag value
---@param flag_name string Name of the flag to check
---@return boolean True if flag is set
function manager.get_flag(flag_name)
    if not player_ref or not player_ref.dialogue_flags then
        return false
    end
    return player_ref.dialogue_flags[flag_name] == true
end

--- Clear a dialogue flag
---@param flag_name string Name of the flag to clear
function manager.clear_flag(flag_name)
    if not player_ref or not player_ref.dialogue_flags then return end
    player_ref.dialogue_flags[flag_name] = nil
end

--- Evaluate a condition string
--- Supports: flag_name (true if set), not_flag_name (true if not set),
--- has_item_item_id (true if player has item), has_gold_amount (true if player has gold)
---@param condition string|nil Condition string to evaluate
---@param player table Player instance for item/gold checks
---@return boolean True if condition passes (nil condition always passes)
function manager.evaluate_condition(condition, player)
    if not condition then return true end

    -- Check for "not_" prefix (negation)
    if condition:sub(1, 4) == "not_" then
        local inner_condition = condition:sub(5)
        return not manager.evaluate_condition(inner_condition, player)
    end

    -- Check for "has_item_" prefix
    if condition:sub(1, 9) == "has_item_" then
        local item_id = condition:sub(10)
        if player and player.unique_items then
            for _, item in ipairs(player.unique_items) do
                if item == item_id then
                    return true
                end
            end
        end
        return false
    end

    -- Check for "has_gold_" prefix
    if condition:sub(1, 9) == "has_gold_" then
        local amount = tonumber(condition:sub(10))
        if amount and player and player.gold then
            return player.gold >= amount
        end
        return false
    end

    -- Check for "defeated_boss_" prefix
    if condition:sub(1, 14) == "defeated_boss_" then
        local boss_id = condition:sub(15)
        if player and player.defeated_bosses then
            return player.defeated_bosses[boss_id] == true
        end
        return false
    end

    -- Default: check as dialogue flag
    return manager.get_flag(condition)
end

--- Filter options based on conditions
--- Supports multiple conditions: condition, condition2, condition3, etc. (all must pass)
---@param options table Array of dialogue options
---@param player table Player instance
---@return table Filtered options that pass their conditions
function manager.filter_options(options, player)
    local filtered = {}
    for _, option in ipairs(options) do
        local passes = true
        -- Check primary condition
        if not manager.evaluate_condition(option.condition, player) then
            passes = false
        end
        -- Check additional conditions (condition2, condition3, etc.)
        local i = 2
        while passes and option["condition" .. i] do
            if not manager.evaluate_condition(option["condition" .. i], player) then
                passes = false
            end
            i = i + 1
        end
        if passes then
            table.insert(filtered, option)
        end
    end
    return filtered
end

--- Execute actions from a dialogue node
--- Actions: set_flag_X, clear_flag_X, give_gold_X, take_gold_X,
--- give_item_X, take_item_X, journal_add_X, journal_complete_X
---@param actions table|nil Array of action strings
---@param player table Player instance
function manager.execute_actions(actions, player)
    if not actions then return end

    for _, action in ipairs(actions) do
        if action:sub(1, 9) == "set_flag_" then
            local flag_name = action:sub(10)
            manager.set_flag(flag_name)
        elseif action:sub(1, 11) == "clear_flag_" then
            local flag_name = action:sub(12)
            manager.clear_flag(flag_name)
        elseif action:sub(1, 10) == "give_gold_" then
            local amount = tonumber(action:sub(11))
            if amount and player then
                player.gold = (player.gold or 0) + amount
            end
        elseif action:sub(1, 10) == "take_gold_" then
            local amount = tonumber(action:sub(11))
            if amount and player then
                player.gold = math.max(0, (player.gold or 0) - amount)
            end
        elseif action:sub(1, 10) == "give_item_" then
            local item_id = action:sub(11)
            if player and player.unique_items then
                local already_has = false
                for _, item in ipairs(player.unique_items) do
                    if item == item_id then
                        already_has = true
                        break
                    end
                end
                if not already_has then
                    table.insert(player.unique_items, item_id)
                end
            end
        elseif action:sub(1, 10) == "take_item_" then
            local item_id = action:sub(11)
            if player and player.unique_items then
                for i, item in ipairs(player.unique_items) do
                    if item == item_id then
                        table.remove(player.unique_items, i)
                        if player.equipped_items then
                            player.equipped_items[item_id] = nil
                        end
                        break
                    end
                end
            end
        elseif action:sub(1, 12) == "journal_add_" then
            local entry_id = action:sub(13)
            if player then
                player.journal = player.journal or {}
                if not player.journal[entry_id] then
                    player.journal[entry_id] = "active"
                    journal_toast.push(entry_id)
                end
            end
        elseif action:sub(1, 17) == "journal_complete_" then
            local entry_id = action:sub(18)
            if player then
                player.journal = player.journal or {}
                player.journal[entry_id] = "complete"
            end
        end
    end
end

return manager
