--- Campfire prop definition - Rest point with text prompt
local sprites = require("sprites")
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")

local CAMPFIRE = Animation.create_definition(sprites.environment.campfire, 5, {
    ms_per_frame = 160,
    width = 16,
    height = 80,
    loop = true
})

return {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#FFA500",

    ---@param prop table The prop instance being spawned
    ---@param def table The campfire definition (unused)
    ---@param options table Spawn options (may contain name)
    on_spawn = function(prop, def, options)
        prop.animation = Animation.new(CAMPFIRE)
        prop.text_display = TextDisplay.new("Rest\n{move_down} + {attack}", { anchor = "top" })
        -- Copy name from level symbol definition for save slot display
        prop.name = options and options.name or nil
    end,

    --- Update text display visibility based on player proximity
    ---@param prop table Campfire prop instance
    ---@param dt number Delta time in seconds
    ---@param player table Player instance for proximity check
    update = function(prop, dt, player)
        local is_active = common.player_touching(prop, player)
        prop.text_display:update(dt, is_active)
    end,

    --- Draw campfire animation and text display
    ---@param prop table Campfire prop instance
    draw = function(prop)
        common.draw(prop)
        prop.text_display:draw(prop.x, prop.y)
    end,
}
