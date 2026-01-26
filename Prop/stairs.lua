--- Stairs prop definition - Level transition point with player climb animation
local sprites = require("sprites")
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")

local VARIANT_CONFIG = {
    up = {
        animation = Animation.create_definition(sprites.environment.stairs_up, 1, {
            ms_per_frame = 1000,
            width = 32,
            height = 32,
            loop = false
        }),
        prompt = "Climb\n{move_up}"
    },
    down = {
        animation = Animation.create_definition(sprites.environment.stairs_down, 1, {
            ms_per_frame = 1000,
            width = 32,
            height = 32,
            loop = false
        }),
        prompt = "Descend\n{move_up}"
    }
}

return {
    box = { x = 0.5, y = 1, w = 1, h = 1 },
    debug_color = "#8B4513",

    --- Handle player interaction - set stairs target and transition to climb state
    ---@param prop table The stairs prop instance
    ---@param player table The player instance
    ---@return table|nil Interaction result with player state transition
    interact = function(prop, player)
        player.stairs_target = {
            level_id = prop.target_level_id,
            spawn_symbol = prop.target_spawn_symbol,
            stair_x = prop.x,
            stair_y = prop.y,
            variant = prop.variant
        }
        player.stairs_transition_ready = false
        return { player_state = "stairs_" .. prop.variant }
    end,

    ---@param prop table The prop instance being spawned
    ---@param _def table The stairs definition (unused)
    ---@param options table Spawn options (variant, target_level, target_spawn)
    on_spawn = function(prop, _def, options)
        prop.variant = options.variant or "up"
        prop.target_level_id = options.target_level
        prop.target_spawn_symbol = options.target_spawn

        local config = VARIANT_CONFIG[prop.variant]
        prop.animation = Animation.new(config.animation)
        prop.text_display = TextDisplay.new(config.prompt, { anchor = "top" })
    end,

    --- Update text display visibility based on player proximity
    ---@param prop table Stairs prop instance
    ---@param dt number Delta time in seconds
    ---@param player table Player instance for proximity check
    update = function(prop, dt, player)
        local is_active = common.player_touching(prop, player)
        prop.text_display:update(dt, is_active)
    end,

    --- Draw stairs animation and text display
    ---@param prop table Stairs prop instance
    draw = function(prop)
        common.draw(prop)
        prop.text_display:draw(prop.x, prop.y, 2)  -- 2 tiles wide (32px sprite)
    end,
}
