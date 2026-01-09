local canvas = require('canvas')
local config = require('config')
local debug = {}

function debug.draw(player)
    if not config.debug then return end
    local h = canvas.get_height()
    local w = canvas.get_width()

    canvas.set_font_size(24)
    local FPS = string.format("FPS: %.0f", 1/canvas.get_delta())
    local metrics = canvas.get_text_metrics(FPS)
    local text_height = metrics.actual_bounding_box_ascent + metrics.actual_bounding_box_descent
    canvas.set_text_baseline("top")

    canvas.set_color("#00000051")
    canvas.fill_rect(w - metrics.width - 4, h - text_height*2, metrics.width + 4, text_height*2)
    canvas.set_color("#dede2bff")
    canvas.draw_text(w - metrics.width - 4, h - text_height*2, FPS)


    local GROUNDED = "is_grounded: " .. tostring(player.is_grounded)
    local POS = string.format("POS: %f.2, %f.2", player.x, player.y)
    local CAN_CLIMB = "can_climb: " .. tostring(player.can_climb) .. " is_climbing: " .. tostring(player.is_climbing)
    local PLAYER_STATE = "state: " .. player.state.name
    canvas.draw_text(0, 0, GROUNDED)
    canvas.draw_text(0, 24, POS)
    canvas.draw_text(0, 48, CAN_CLIMB)
    canvas.draw_text(0, 72, PLAYER_STATE)

end

return debug
