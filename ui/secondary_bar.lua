--- Secondary items HUD widget showing equipped secondary abilities
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local weapon_sync = require("player.weapon_sync")
local control_icon = require("ui.control_icon")

---@class secondary_bar
local secondary_bar = {}
secondary_bar.__index = secondary_bar

-- Layout constants (sprite dimensions in 1x scale)
local CONTAINER_WIDTH = 26    -- Width of each slot container
local END_WIDTH = 7           -- Width of left/right end caps
local ICON_SIZE = 16          -- Item icon size
local ICON_OFFSET_X = 5       -- X offset to center 16px icon in 26px container
local ICON_OFFSET_Y = 4       -- Y offset to center 16px icon in 24px container
local SELECTION_ALPHA = 0.1   -- Alpha for selection overlay

-- Control icon layout (for throw indicator on active slot)
local CONTROL_ICON_SIZE = 8   -- Size of control icon in 1x scale
local CONTROL_ICON_OFFSET_X = 16  -- X offset from slot left edge
local CONTROL_ICON_OFFSET_Y = 14  -- Y offset from slot top edge

-- Swap hint layout (shown when multiple secondaries equipped)
local SWAP_HINT_Y = 26        -- Y offset for swap hint text (below containers)
local SWAP_HINT_FONT_SIZE = 7 -- Font size for swap hint text
local SWAP_ICON_SIZE = 10     -- Size of swap control icon
local SWAP_TEXT = "Swap:"
local SWAP_TEXT_WIDTH = nil   -- Lazy-init since font must be loaded first

-- Position constants matching projectile_selector layout
local SELECTOR_X = 8          -- projectile_selector x position
local METER_X = 36            -- Meter offset within selector (1x scale)
local PX_PER_UNIT = 5         -- Pixels per stat point (1x scale)
local CAP_WIDTH = 4           -- Approximate meter cap width (1x scale)
local MARGIN = 8              -- Margin between bars and secondary widget (1x scale)
local TOP_MARGIN = 1          -- Margin from top of HUD bar (1x scale)

--- Creates a new secondary bar widget instance
---@return secondary_bar widget instance
function secondary_bar.create()
    local self = setmetatable({}, secondary_bar)
    return self
end

---@param _ number Delta time in seconds (unused, for API consistency)
---@param __ table Player instance (unused, for API consistency)
---@return nil
function secondary_bar:update(_, __)
end

---@param player table Player instance with active_secondary and equipped_items
---@return nil
function secondary_bar:draw(player)
    local secondaries = weapon_sync.get_equipped_secondaries(player)
    if #secondaries == 0 then return end

    local scale = config.ui.SCALE

    -- Calculate X position: after the resource meters + margin
    local max_stat = math.max(player.max_health, player.max_stamina, player.max_energy)
    local meter_width = max_stat * PX_PER_UNIT
    local selector_width = METER_X + meter_width + CAP_WIDTH
    local draw_x = SELECTOR_X + (selector_width + MARGIN) * scale

    -- Calculate Y position: 5px (base) from top of HUD
    local hud_height = config.ui.HUD_HEIGHT_PX * scale

    canvas.save()
    canvas.translate(draw_x, canvas.get_height() - hud_height + (TOP_MARGIN * scale))
    canvas.scale(scale, scale)

    local x = 0

    -- Draw left end cap
    canvas.draw_image(sprites.ui.secondary_left_end, x, 0)
    x = x + END_WIDTH

    -- Draw each equipped secondary slot
    for _, sec in ipairs(secondaries) do
        -- Draw container background
        canvas.draw_image(sprites.ui.secondary_container, x, 0)

        -- Draw item icon centered in container
        local icon_x = x + ICON_OFFSET_X
        local icon_y = ICON_OFFSET_Y
        if sec.def.static_sprite then
            canvas.draw_image(sec.def.static_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE)
        elseif sec.def.animated_sprite then
            -- For animated sprites, draw only the first frame (16x16)
            canvas.draw_image(sec.def.animated_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE, 0, 0, ICON_SIZE, ICON_SIZE)
        end

        -- Draw selection overlay and throw icon if this is the active secondary
        if sec.id == player.active_secondary then
            canvas.set_global_alpha(SELECTION_ALPHA)
            canvas.draw_image(sprites.ui.secondary_container_selected, x, 0)
            canvas.set_global_alpha(1)

            -- Draw ability control icon in bottom-right
            control_icon.draw("ability", x + CONTROL_ICON_OFFSET_X, CONTROL_ICON_OFFSET_Y, CONTROL_ICON_SIZE)
        end

        x = x + CONTAINER_WIDTH
    end

    -- Draw right end cap
    canvas.draw_image(sprites.ui.secondary_right_end, x, 0)

    -- Draw swap hint if more than 1 secondary equipped
    if #secondaries > 1 then
        canvas.set_font_family("menu_font")
        canvas.set_font_size(SWAP_HINT_FONT_SIZE)
        canvas.set_text_align("left")
        canvas.set_text_baseline("top")
        canvas.set_color("#AAAAAA")
        canvas.draw_text(END_WIDTH, SWAP_HINT_Y, SWAP_TEXT)

        -- Cache text width on first use
        if not SWAP_TEXT_WIDTH then
            SWAP_TEXT_WIDTH = canvas.get_text_width(SWAP_TEXT)
        end
        control_icon.draw("swap_ability", END_WIDTH + SWAP_TEXT_WIDTH + 2, SWAP_HINT_Y - 1, SWAP_ICON_SIZE)
    end

    canvas.restore()
end

return secondary_bar
