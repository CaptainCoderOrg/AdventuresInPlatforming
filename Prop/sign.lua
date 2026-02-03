--- Sign prop definition - interactive text display triggered by player proximity
local canvas = require("canvas")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")

return {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#FFA500",

    on_spawn = function(prop, def, options)
        prop.text_display = TextDisplay.new(options.text or "", { anchor = "top" })
    end,

    update = common.update_text_display,

    draw = function(prop)
        local tile_size = sprites.tile_size
        local screen_x = prop.x * tile_size
        local screen_y = prop.y * tile_size

        canvas.draw_image(
            sprites.environment.sign,
            screen_x, screen_y,
            tile_size, tile_size
        )

        prop.text_display:draw(prop.x, prop.y)
    end,
}
