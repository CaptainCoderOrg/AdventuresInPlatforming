--- Decoration prop - non-interactive visual elements rendered from tilesets
--- Used for props placed in Tiled that don't need collision or interaction.
local canvas = require("canvas")
local config = require("config")
local common = require("platforms/common")
local sprites = require("sprites")

return {
    -- Zero-size hitbox means no collision detection
    box = { x = 0, y = 0, w = 0, h = 0 },

    --- Initialize decoration prop with tile render info from Tiled.
    ---@param prop table The prop instance
    ---@param def table The prop definition
    ---@param options table Spawn options containing gid, tile_render_info, width, height, flip
    on_spawn = function(prop, def, options)
        -- Store rendering info from Tiled
        prop.gid = options.gid
        prop.tile_render_info = options.tile_render_info
        prop.width = options.width
        prop.height = options.height
        prop.flip = options.flip
    end,

    --- Render the decoration tile at its position.
    --- Handles both collection tiles (individual images) and image-based tileset tiles.
    ---@param prop table The prop instance
    draw = function(prop)
        local ts = sprites.tile_size
        local render_info = prop.tile_render_info

        if not render_info then return end

        if render_info.image then
            -- Collection tile (individual image)
            local scale = config.ui.SCALE
            local height_offset = (render_info.height / common.BASE_TILE - 1) * ts
            local width_scaled = render_info.width * scale
            local height_scaled = render_info.height * scale
            local draw_x = prop.x * ts
            local draw_y = prop.y * ts - height_offset

            if prop.flip then
                -- Flip horizontally by scaling -1 and offsetting
                canvas.save()
                canvas.translate(draw_x + width_scaled, draw_y)
                canvas.scale(-1, 1)
                canvas.draw_image(render_info.image, 0, 0, width_scaled, height_scaled)
                canvas.restore()
            else
                canvas.draw_image(render_info.image, draw_x, draw_y, width_scaled, height_scaled)
            end
        elseif render_info.tileset_image then
            -- Image-based tileset tile
            local local_id = prop.gid - render_info.firstgid
            local tx = local_id % render_info.columns
            local ty = math.floor(local_id / render_info.columns)

            if prop.flip then
                canvas.save()
                canvas.translate(prop.x * ts + ts, prop.y * ts)
                canvas.scale(-1, 1)
                sprites.draw_tile(tx, ty, 0, 0, render_info.tileset_image)
                canvas.restore()
            else
                sprites.draw_tile(tx, ty, prop.x * ts, prop.y * ts, render_info.tileset_image)
            end
        end
    end,
}
