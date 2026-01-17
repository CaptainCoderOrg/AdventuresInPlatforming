--- Interactive sign system for displaying text prompts when player is nearby
local canvas = require("canvas")
local sprites = require("sprites")
local controls = require("controls")
local config = require("config")
local state = require("Sign/state")

local Sign = {}

local FONT_SIZE = 9 * config.ui.SCALE
local TEXT_PADDING = 2 * config.ui.SCALE
local FADE_DURATION = 0.25  -- seconds to fade in/out

--- Check if player is touching a sign (overlapping bounding boxes)
---@param sign table Sign instance
---@param player table Player instance
---@return boolean True if player overlaps sign tile
local function player_touching(sign, player)
    local px, py = player.x + player.box.x, player.y + player.box.y
    local pw, ph = player.box.w, player.box.h
    local sx, sy = sign.x, sign.y
    local sw, sh = 1, 1  -- sign is 1x1 tile

    return px < sx + sw and px + pw > sx and
           py < sy + sh and py + ph > sy
end

--- Replace {action_id} placeholders with bound key/button names
---@param text string Text with placeholders like {jump}
---@return string Text with placeholders replaced by control names
local function substitute_variables(text)
    local scheme = controls.get_last_input_device()
    return text:gsub("{(%w+)}", function(action_id)
        return controls.get_binding_name(scheme, action_id)
    end)
end

--- Create a new sign at the specified position
---@param x number X position in tile coordinates
---@param y number Y position in tile coordinates
---@param text string Display text (can include {action_id} variables)
---@return table Sign instance
function Sign.new(x, y, text)
    local self = {
        id = "sign_" .. state.next_id,
        x = x,
        y = y,
        text = text,
        is_active = false,
        alpha = 0,
    }
    state.next_id = state.next_id + 1
    state.all[self] = true
    return self
end

--- Update all signs (checks player proximity and fades text)
---@param dt number Delta time in seconds
---@param player table Player instance
function Sign.update(dt, player)
    for sign in pairs(state.all) do
        sign.is_active = player_touching(sign, player)

        -- Fade alpha toward target
        local target = sign.is_active and 1 or 0
        local fade_rate = dt / FADE_DURATION
        if sign.alpha < target then
            sign.alpha = math.min(sign.alpha + fade_rate, 1)
        elseif sign.alpha > target then
            sign.alpha = math.max(sign.alpha - fade_rate, 0)
        end
    end
end

--- Draw all signs and their text popups.
--- Active signs also render their text bubble above the sprite.
function Sign.draw()
    local tile_size = sprites.tile_size

    for sign in pairs(state.all) do
        -- Draw sign sprite
        local screen_x = sign.x * tile_size
        local screen_y = sign.y * tile_size
        canvas.draw_image(
            sprites.environment.sign,
            screen_x, screen_y,
            tile_size, tile_size
        )

        -- Draw debug box
        if config.bounding_boxes then
            canvas.set_color("#FFA500")
            canvas.draw_rect(screen_x, screen_y, tile_size, tile_size)
        end

        -- Draw text popup with fade
        if sign.alpha > 0 then
            local display_text = substitute_variables(sign.text)

            canvas.set_font_family("menu_font")
            canvas.set_font_size(FONT_SIZE)
            canvas.set_text_baseline("bottom")
            canvas.set_text_align("center")

            -- Measure text for background box
            local text_width = canvas.get_text_width(display_text)
            local text_height = FONT_SIZE
            local box_width = text_width + TEXT_PADDING * 2
            local box_height = text_height + TEXT_PADDING * 2

            -- Position centered above sign
            local text_x = screen_x + tile_size / 2
            local text_y = screen_y

            canvas.set_global_alpha(sign.alpha)

            -- Draw semi-transparent background
            canvas.set_color("#00000099")
            canvas.fill_rect(
                text_x - box_width / 2,
                text_y - box_height,
                box_width,
                box_height
            )

            canvas.set_color("#ffffffee")
            canvas.draw_text(text_x, text_y - TEXT_PADDING, display_text, {})

            -- Restore canvas defaults to prevent affecting subsequent draw calls
            canvas.set_global_alpha(1)
            canvas.set_text_align("left")
            canvas.set_text_baseline("alphabetic")
        end
    end
end

--- Remove a specific sign from the active set.
---@param sign table Sign instance to remove
function Sign.remove(sign)
    state.all[sign] = nil
end

--- Remove all signs and reset ID counter.
--- Call before loading a new level to prevent stale signs.
function Sign.clear()
    state.all = {}
    state.next_id = 1
end

return Sign
