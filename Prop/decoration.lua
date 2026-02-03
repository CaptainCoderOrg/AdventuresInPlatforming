--- Decoration prop - non-interactive visual elements rendered from tilesets
--- Used for props placed in Tiled that don't need collision or interaction.
--- Supports optional helper text that appears when player is nearby.
local canvas = require("canvas")
local config = require("config")
local platform_common = require("platforms/common")
local prop_common = require("Prop/common")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local tile_transform = require("platforms/tile_transform")

return {
    -- Zero-size hitbox means no collision detection (overridden if text is set)
    box = { x = 0, y = 0, w = 0, h = 0 },

    --- Initialize decoration prop with tile render info from Tiled.
    ---@param prop table The prop instance
    ---@param def table The prop definition
    ---@param options table Spawn options containing gid, tile_render_info, width, height, flip flags, text
    on_spawn = function(prop, def, options)
        -- Store rendering info from Tiled
        prop.gid = options.gid
        prop.tile_render_info = options.tile_render_info
        prop.width = options.width
        prop.height = options.height
        prop.flip_h = options.flip_h
        prop.flip_v = options.flip_v

        -- Optional helper text
        if options.text then
            prop.text_display = TextDisplay.new(options.text, { anchor = "top" })
            -- Set a 1x1 box for proximity detection when text is enabled
            prop.box = { x = 0, y = 0, w = 1, h = 1 }
        end
    end,

    --- Update text display visibility based on player proximity
    ---@param prop table The prop instance
    ---@param dt number Delta time in seconds
    ---@param player table The player object
    update = function(prop, dt, player)
        if not prop.text_display then return end
        prop_common.update_text_display(prop, dt, player)
    end,

    --- Render the decoration tile at its position.
    --- Handles both collection tiles (individual images) and image-based tileset tiles.
    ---@param prop table The prop instance
    draw = function(prop)
        local ts = sprites.tile_size
        local render_info = prop.tile_render_info

        if not render_info then return end

        local has_transform = tile_transform.has_transform(prop.flip_h, prop.flip_v)

        if render_info.image then
            -- Collection tile (individual image)
            local scale = config.ui.SCALE
            local height_offset = (render_info.height / platform_common.BASE_TILE - 1) * ts
            local width_scaled = render_info.width * scale
            local height_scaled = render_info.height * scale
            local draw_x = prop.x * ts
            local draw_y = prop.y * ts - height_offset

            if has_transform then
                canvas.save()
                canvas.translate(draw_x, draw_y)
                tile_transform.apply(prop.flip_h, prop.flip_v, width_scaled, height_scaled)
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
            local draw_x = prop.x * ts
            local draw_y = prop.y * ts

            if has_transform then
                canvas.save()
                canvas.translate(draw_x, draw_y)
                tile_transform.apply(prop.flip_h, prop.flip_v, ts, ts)
                sprites.draw_tile(tx, ty, 0, 0, render_info.tileset_image)
                canvas.restore()
            else
                sprites.draw_tile(tx, ty, draw_x, draw_y, render_info.tileset_image)
            end
        end

        -- Draw helper text if present
        if prop.text_display then
            prop.text_display:draw(prop.x, prop.y)
        end
    end,
}
