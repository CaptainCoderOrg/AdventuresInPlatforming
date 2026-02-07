--- Group config prop - invisible configurator that applies actions to prop groups
--- Place one in Tiled with target_group, target_action, and config properties.
--- After all props spawn, apply_group_configs() runs the action and removes these.

local definition = {
    box = { x = 0, y = 0, w = 0, h = 0 },

    ---@param prop table The prop instance
    ---@param def table The prop definition
    ---@param options table Tiled spawn options (target_group, target_action, plus config keys)
    on_spawn = function(prop, def, options)
        prop.target_group = options.target_group
        prop.target_action = options.target_action

        -- Collect all extra options as action config (exclude spawn metadata)
        local skip = {
            type = true, x = true, y = true, id = true, flip = true,
            group = true, group_id = true, reset = true, map = true,
            tiled_x = true, tiled_y = true, tiled_id = true,
            target_group = true, target_action = true,
            should_spawn = true,
        }
        local config = {}
        for k, v in pairs(options) do
            if not skip[k] then
                config[k] = v
            end
        end
        prop.action_config = config
    end,
}

return definition
