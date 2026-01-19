--- Campfire prop definition - Stateless animated decoration
local sprites = require("sprites")
local Animation = require("Animation")
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
    on_spawn = function(prop)
        prop.animation = Animation.new(CAMPFIRE)
    end,

    draw = common.draw
}
