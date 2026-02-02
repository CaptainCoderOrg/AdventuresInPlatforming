--- Shared utility for drawing control icons in HUD widgets
local control_sprites = require("sprites.controls")
local controls_module = require("controls")

local control_icon = {}

--- Draw a control icon at the given position with specified size.
--- Handles keyboard vs gamepad with appropriate scaling for consistent size.
---@param action_id string Action identifier (e.g., "attack", "swap_weapon", "ability")
---@param x number X position in 1x scale
---@param y number Y position in 1x scale
---@param size number Target icon size in 1x scale
function control_icon.draw(action_id, x, y, size)
    local scheme = controls_module.get_binding_scheme()
    local code = controls_module.get_binding(scheme, action_id)
    if not code then return end

    -- Scale to get target size in 1x coordinates
    -- Keyboard sprites are 64x64 base, gamepad are 16x16 base
    if scheme == "keyboard" then
        control_sprites.draw_key(code, x, y, size / 64)
    else
        control_sprites.draw_button(code, x, y, size / 16)
    end
end

return control_icon
