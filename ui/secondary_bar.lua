--- Secondary abilities HUD widget showing 4 fixed ability slots
local canvas = require("canvas")
local sprites = require("sprites")
local config = require("config")
local weapon_sync = require("player.weapon_sync")
local control_icon = require("ui.control_icon")
local unique_item_registry = require("Prop.unique_item_registry")

---@class secondary_bar
local secondary_bar = {}
secondary_bar.__index = secondary_bar

-- Layout constants (sprite dimensions in 1x scale)
local SLOT_COUNT = 4
local CONTAINER_WIDTH = 26    -- Width of each slot container
local END_WIDTH = 7           -- Width of left/right end caps
local ICON_SIZE = 16          -- Item icon size
local ICON_OFFSET_X = 5       -- X offset to center 16px icon in 26px container
local ICON_OFFSET_Y = 4       -- Y offset to center 16px icon in 24px container

-- Control icon layout (keybind label per slot)
local CONTROL_ICON_SIZE = 8   -- Size of control icon in 1x scale
local CONTROL_ICON_OFFSET_X = 16  -- X offset from slot left edge
local CONTROL_ICON_OFFSET_Y = 14  -- Y offset from slot top edge

-- Charge display constants
local CHARGE_FONT_SIZE = 7
local CHARGE_TEXT_X = 1         -- X offset from icon left for charge count
local CHARGE_TEXT_Y = 0         -- Y offset from icon top for charge count
local DEPLETED_ALPHA = 0.3     -- Alpha for greyed-out depleted icons
local RECHARGE_LINE_WIDTH = 1  -- Width of recharge progress outline
local EMPTY_SLOT_ALPHA = 0.3   -- Alpha for empty slot containers
-- Pre-computed digit strings to avoid per-frame tostring() allocation
local DIGIT_STR = { [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }

-- Ability action IDs per slot (for keybind display)
local ABILITY_ACTION_IDS = { "ability_1", "ability_2", "ability_3", "ability_4" }

-- Position constants matching projectile_selector layout
local SELECTOR_X = 8          -- projectile_selector x position
local METER_X = 36            -- Meter offset within selector (1x scale)
local PX_PER_UNIT = 5         -- Pixels per stat point (1x scale)
local CAP_WIDTH = 4           -- Approximate meter cap width (1x scale)
local MARGIN = 8              -- Margin between bars and secondary widget (1x scale)
local TOP_MARGIN = 1          -- Margin from top of HUD bar (1x scale)

--- Draws a clockwise recharge progress outline around a 16x16 icon area.
--- Progress 0.0 = nothing drawn, 1.0 = full perimeter drawn.
---@param ix number Icon X position
---@param iy number Icon Y position
---@param progress number Progress fraction 0.0-1.0
local function draw_recharge_outline(ix, iy, progress)
    if progress <= 0 then return end
    local s = ICON_SIZE
    local total = s * 4
    local drawn = progress * total

    canvas.set_color("#FF3333")
    canvas.set_line_width(RECHARGE_LINE_WIDTH)
    canvas.begin_path()
    canvas.move_to(ix, iy)

    if drawn <= s then
        canvas.line_to(ix + drawn, iy)
    else
        canvas.line_to(ix + s, iy)
    end
    if drawn > s then
        local seg = math.min(drawn - s, s)
        canvas.line_to(ix + s, iy + seg)
    end
    if drawn > s * 2 then
        local seg = math.min(drawn - s * 2, s)
        canvas.line_to(ix + s - seg, iy + s)
    end
    if drawn > s * 3 then
        local seg = math.min(drawn - s * 3, s)
        canvas.line_to(ix, iy + s - seg)
    end

    canvas.stroke()
end

--- Creates a new secondary bar widget instance
---@return secondary_bar widget instance
function secondary_bar.create()
    local self = setmetatable({}, secondary_bar)
    return self
end

---@param _dt number Delta time in seconds (unused, for API consistency)
---@param _player table Player instance (unused, for API consistency)
---@return nil
function secondary_bar:update(_dt, _player)
end

---@param player table Player instance with ability_slots and equipped_items
---@return nil
function secondary_bar:draw(player)
    if not player.ability_slots then return end

    local scale = config.ui.SCALE

    -- Calculate X position: after the resource meters + margin
    local max_stat = math.max(player.max_health, player.max_stamina, player.max_energy)
    local meter_width = max_stat * PX_PER_UNIT
    local selector_width = METER_X + meter_width + CAP_WIDTH
    local draw_x = SELECTOR_X + (selector_width + MARGIN) * scale

    local hud_height = config.ui.HUD_HEIGHT_PX * scale

    canvas.save()
    canvas.translate(draw_x, canvas.get_height() - hud_height + (TOP_MARGIN * scale))
    canvas.scale(scale, scale)

    local x = 0

    -- Draw left end cap
    canvas.draw_image(sprites.ui.secondary_left_end, x, 0)
    x = x + END_WIDTH

    -- Draw 4 fixed ability slots
    for slot = 1, SLOT_COUNT do
        local item_id = player.ability_slots[slot]
        local item_def = item_id and unique_item_registry[item_id]

        -- Draw container background (dimmed if empty)
        if not item_def then
            canvas.set_global_alpha(EMPTY_SLOT_ALPHA)
        end
        canvas.draw_image(sprites.ui.secondary_container, x, 0)
        if not item_def then
            canvas.set_global_alpha(1)
        end

        if item_def then
            local icon_x = x + ICON_OFFSET_X
            local icon_y = ICON_OFFSET_Y

            -- Check charge info
            local available, max_charges, recharge_progress = weapon_sync.get_charge_info(item_id, player)
            local is_charge_based = max_charges > 0
            local depleted = is_charge_based and available == 0

            if depleted then
                canvas.set_global_alpha(DEPLETED_ALPHA)
            end

            if item_def.static_sprite then
                canvas.draw_image(item_def.static_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE)
            elseif item_def.animated_sprite then
                canvas.draw_image(item_def.animated_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE, 0, 0, ICON_SIZE, ICON_SIZE)
            end

            if depleted then
                canvas.set_global_alpha(1)
            end

            -- Draw charge count and recharge outline for charge-based secondaries
            if is_charge_based then
                canvas.set_font_family("menu_font")
                canvas.set_font_size(CHARGE_FONT_SIZE)
                canvas.set_text_align("left")
                canvas.set_text_baseline("top")
                if available > 0 then
                    canvas.set_color("#FFFFFF")
                else
                    canvas.set_color("#FF3333")
                end
                canvas.draw_text(icon_x + CHARGE_TEXT_X, icon_y + CHARGE_TEXT_Y, DIGIT_STR[available] or tostring(available))

                if recharge_progress > 0 then
                    draw_recharge_outline(icon_x, icon_y, recharge_progress)
                end
            end
        end

        -- Draw keybind label for this slot
        control_icon.draw(ABILITY_ACTION_IDS[slot], x + CONTROL_ICON_OFFSET_X, CONTROL_ICON_OFFSET_Y, CONTROL_ICON_SIZE)

        x = x + CONTAINER_WIDTH
    end

    -- Draw right end cap
    canvas.draw_image(sprites.ui.secondary_right_end, x, 0)

    canvas.restore()
end

return secondary_bar
