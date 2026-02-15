--- Split-screen upgrade workshop UI with camera shift
--- Displays upgradeable items in bottom area while showing map view in top area
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local upgrade_registry = require("upgrade/registry")
local upgrade_transactions = require("upgrade/transactions")
local unique_item_registry = require("Prop/unique_item_registry")
local stackable_item_registry = require("Prop/stackable_item_registry")

local upgrade_screen = {}

-- State machine states
local STATE = {
    HIDDEN = 1,
    FADING_IN = 2,
    OPEN = 3,
    FADING_OUT = 4,
}

-- Layout constants (at 1x scale, scaled by config.ui.SCALE)
local MAP_VIEW_HEIGHT = 48
local DIALOGUE_AREA_HEIGHT = 168
local PLAYER_MARGIN = 8
local FADE_DURATION = 0.3

-- Box layout (at 1x scale)
local BOX_MARGIN_X = 32
local BOX_MARGIN_BOTTOM = 16
local BOX_HEIGHT = 120
local TEXT_PADDING_TOP = 10
local TEXT_PADDING_LEFT = 12
local TEXT_PADDING_RIGHT = 12
local LINE_HEIGHT = 12
local ITEM_INDENT = 8
local FONT_SIZE = 8

-- Pagination
local ITEMS_PER_PAGE = 4

-- Selection indicator
local SELECTOR_CHAR = ">"
local SELECTOR_OFFSET_X = -10

-- Gold display
local GOLD_LABEL = "Gold: "

-- Typewriter
local TYPEWRITER_SPEED = 30  -- Characters per second

-- Shared icon sizing (used by close hint and page navigation)
local ICON_SIZE = 8
local ICON_SPACING = 4
local KEY_SCALE = 0.125             -- 64px * 0.125 = 8px
local BUTTON_SCALE = 0.5            -- 16px * 0.5 = 8px

-- 9-slice definition (reuse simple_dialogue sprite)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Module state
local state = STATE.HIDDEN
local fade_progress = 0
local selected_item = 1
local current_page = 1
local player_ref = nil
local camera_ref = nil
local original_camera_y = nil
local target_camera_y = nil
local npc_message = nil
local message_reveal = 0
local upgradeable_items = {}

-- Default NPC greeting
local DEFAULT_MESSAGE = "How can I help you?"

-- Mouse support
local mouse_active = false
local last_mouse_x, last_mouse_y = 0, 0
local item_positions = {}
local item_positions_count = 0
for i = 1, ITEMS_PER_PAGE do
    item_positions[i] = { y = 0, x_start = 0, x_end = 0, entry_index = 0 }
end

--- Rebuild the list of upgradeable items from player inventory
local function refresh_items()
    if player_ref then
        upgradeable_items = upgrade_registry.get_upgradeable_items(player_ref)
    else
        upgradeable_items = {}
    end
end

--- Get current fade alpha based on state
---@return number alpha 0.0 to 1.0
local function get_alpha()
    if state == STATE.FADING_IN then return fade_progress end
    if state == STATE.OPEN then return 1 end
    if state == STATE.FADING_OUT then return 1 - fade_progress end
    return 0
end

--- Clamp selected_item and derive current_page
local function clamp_selection()
    if #upgradeable_items == 0 then
        selected_item = 1
        current_page = 1
        return
    end
    selected_item = math.max(1, math.min(selected_item, #upgradeable_items))
    current_page = math.ceil(selected_item / ITEMS_PER_PAGE)
end

--- Attempt to purchase the upgrade at the given index
---@param index number Index into upgradeable_items
local function try_purchase(index)
    local entry = upgradeable_items[index]
    if not entry then return end

    local can_buy, reason = upgrade_transactions.can_purchase(player_ref, entry.id)
    if can_buy then
        local success, result = upgrade_transactions.purchase(player_ref, entry.id)
        if success then
            npc_message = result
            message_reveal = 0
            refresh_items()
            clamp_selection()
        end
    else
        npc_message = reason or "Cannot upgrade"
        message_reveal = 0
    end
end

--- Roman numeral helper (1-9)
---@param n number Integer 1-9
---@return string Roman numeral
local ROMAN_NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX" }
local function to_roman(n)
    return ROMAN_NUMERALS[n] or tostring(n)
end

--- Draw close hint with ESC/B icon at bottom-right of box (call inside scaled context)
---@param box_x number Box X position (1x scale)
---@param box_w number Box width (1x scale)
---@param box_y number Box Y position (1x scale)
---@param box_h number Box height (1x scale)
local function draw_close_hint(box_x, box_w, box_y, box_h)
    canvas.set_color("#666666")
    canvas.set_text_align("right")
    local hint_text = "Close"
    local hint_x = box_x + box_w - TEXT_PADDING_RIGHT + 3
    local hint_y = box_y + box_h - 6
    canvas.draw_text(hint_x, hint_y, hint_text)

    local text_w = canvas.get_text_width(hint_text)
    local icon_x = hint_x - text_w - ICON_SPACING - ICON_SIZE
    local icon_y = hint_y - FONT_SIZE + (FONT_SIZE - ICON_SIZE) / 2
    local mode = controls.get_last_input_device()
    if mode == "gamepad" then
        sprites.controls.draw_button(canvas.buttons.EAST, icon_x, icon_y, BUTTON_SCALE)
    else
        sprites.controls.draw_key(canvas.keys.ESCAPE, icon_x, icon_y, KEY_SCALE)
    end
    canvas.set_text_align("left")
end

--- Start the upgrade screen
---@param player table Player instance
---@param camera table Camera instance
---@param restore_camera_y number|nil Original camera Y to restore on close (skips fade-in when provided)
function upgrade_screen.start(player, camera, restore_camera_y)
    player_ref = player
    camera_ref = camera
    selected_item = 1
    current_page = 1
    npc_message = DEFAULT_MESSAGE
    message_reveal = #DEFAULT_MESSAGE

    -- Reset mouse state
    mouse_active = false
    item_positions_count = 0

    -- Calculate target camera Y (same formula as dialogue/shop screens)
    local tile_size = config.ui.TILE
    local viewport_tiles = MAP_VIEW_HEIGHT / tile_size
    local margin_tiles = PLAYER_MARGIN / tile_size
    target_camera_y = player.y - (viewport_tiles - margin_tiles) + 1

    refresh_items()

    if restore_camera_y then
        -- Coming from another overlay: camera is already positioned, skip transition
        original_camera_y = restore_camera_y
        state = STATE.OPEN
        fade_progress = 1
    else
        original_camera_y = camera:get_y()
        state = STATE.FADING_IN
        fade_progress = 0
    end
end

--- Check if upgrade screen is currently active
---@return boolean True if visible or transitioning
function upgrade_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Close the upgrade screen
local function close_screen()
    state = STATE.FADING_OUT
    fade_progress = 0
end

--- Process input for upgrade navigation
function upgrade_screen.input()
    if state ~= STATE.OPEN then return end

    local total_pages = math.ceil(#upgradeable_items / ITEMS_PER_PAGE)

    -- Navigate items
    if controls.menu_up_pressed() then
        mouse_active = false
        if selected_item > 1 then
            selected_item = selected_item - 1
            clamp_selection()
        end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        if selected_item < #upgradeable_items then
            selected_item = selected_item + 1
            clamp_selection()
        end
    elseif controls.menu_left_pressed() then
        mouse_active = false
        if current_page > 1 then
            current_page = current_page - 1
            selected_item = (current_page - 1) * ITEMS_PER_PAGE + 1
        end
    elseif controls.menu_right_pressed() then
        mouse_active = false
        if current_page < total_pages then
            current_page = current_page + 1
            selected_item = (current_page - 1) * ITEMS_PER_PAGE + 1
        end
    elseif controls.menu_confirm_pressed() then
        try_purchase(selected_item)
    elseif controls.menu_back_pressed() then
        close_screen()
    end
end

--- Update upgrade screen state
---@param dt number Delta time in seconds
function upgrade_screen.update(dt)
    if state == STATE.HIDDEN then return end

    -- Typewriter reveal
    if npc_message and message_reveal < #npc_message then
        message_reveal = math.min(message_reveal + TYPEWRITER_SPEED * dt, #npc_message)
    end

    -- Mouse hover detection (only when OPEN)
    if state == STATE.OPEN then
        local mx, my = canvas.get_mouse_x(), canvas.get_mouse_y()

        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x, last_mouse_y = mx, my
        end

        if mouse_active and item_positions_count > 0 then
            local half_line = (LINE_HEIGHT * config.ui.SCALE) / 2
            for i = 1, item_positions_count do
                local pos = item_positions[i]
                if mx >= pos.x_start and mx <= pos.x_end and
                   my >= pos.y - half_line and my <= pos.y + half_line then
                    selected_item = pos.entry_index

                    if canvas.is_mouse_pressed(0) then
                        try_purchase(selected_item)
                    end
                    break
                end
            end
        end
    end

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
        if camera_ref and target_camera_y then
            local t = fade_progress
            local new_y = original_camera_y + (target_camera_y - original_camera_y) * t
            camera_ref:set_y(new_y)
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
            if camera_ref then
                camera_ref:set_y(original_camera_y)
            end
            player_ref = nil
            camera_ref = nil
            upgradeable_items = {}
        else
            if camera_ref and target_camera_y then
                local t = 1 - fade_progress
                local new_y = original_camera_y + (target_camera_y - original_camera_y) * t
                camera_ref:set_y(new_y)
            end
        end
    end
end

--- Draw the upgrade screen overlay
function upgrade_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()
    local alpha = get_alpha()

    local map_view_height = MAP_VIEW_HEIGHT * scale
    local dialogue_area_y = map_view_height

    canvas.set_global_alpha(alpha)

    -- Draw black overlay over bottom area
    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, dialogue_area_y, screen_w, screen_h - dialogue_area_y)

    if alpha > 0 then
        canvas.save()
        canvas.scale(scale, scale)

        local base_w = screen_w / scale
        local base_h = screen_h / scale
        local box_x = BOX_MARGIN_X
        local box_w = base_w - BOX_MARGIN_X * 2
        local box_y = base_h - BOX_MARGIN_BOTTOM - BOX_HEIGHT
        local box_h = BOX_HEIGHT

        nine_slice.draw(slice, box_x, box_y, box_w, box_h)

        canvas.set_font_family("menu_font")
        canvas.set_font_size(FONT_SIZE)
        canvas.set_text_baseline("bottom")

        if #upgradeable_items > 0 then
            local text_x = box_x + TEXT_PADDING_LEFT
            local text_y = box_y + TEXT_PADDING_TOP

            -- Draw title
            canvas.set_color("#FFCC00")
            canvas.draw_text(text_x, text_y + FONT_SIZE, "Zabarbra's Brewtique")

            -- Draw gold amount
            local gold_text = GOLD_LABEL .. tostring(player_ref and player_ref.gold or 0)
            canvas.set_color("#FFD700")
            canvas.set_text_align("right")
            canvas.draw_text(box_x + box_w - TEXT_PADDING_RIGHT, text_y + FONT_SIZE, gold_text)
            canvas.set_text_align("left")

            -- Draw NPC message (typewriter reveal)
            if npc_message then
                local visible = string.sub(npc_message, 1, math.floor(message_reveal))
                canvas.set_color("#AAAAAA")
                canvas.draw_text(text_x, text_y + LINE_HEIGHT + FONT_SIZE, "\"" .. visible .. "\"")
            end

            -- Draw items (below NPC message area, with page support)
            item_positions_count = 0
            local item_y = text_y + LINE_HEIGHT * 2
            local scroll_offset = (current_page - 1) * ITEMS_PER_PAGE
            local visible_count = math.min(#upgradeable_items - scroll_offset, ITEMS_PER_PAGE)
            local total_pages = math.ceil(#upgradeable_items / ITEMS_PER_PAGE)

            for i = 1, visible_count do
                local entry_index = i + scroll_offset
                local entry = upgradeable_items[entry_index]
                local draw_y = item_y + FONT_SIZE
                local item_x = text_x + ITEM_INDENT

                item_positions_count = i
                local pos = item_positions[i]
                pos.y = draw_y * scale
                pos.x_start = (item_x + SELECTOR_OFFSET_X) * scale
                pos.x_end = (box_x + box_w - TEXT_PADDING_RIGHT) * scale
                pos.entry_index = entry_index

                local item_def = unique_item_registry[entry.id]
                local item_name = item_def and item_def.name or entry.id
                local upgrade_def = entry.def
                local current_tier = (player_ref.upgrade_tiers and player_ref.upgrade_tiers[entry.id]) or 0
                local max_tier = #upgrade_def.tiers
                local is_maxed = current_tier >= max_tier

                local can_buy = upgrade_transactions.can_purchase(player_ref, entry.id)

                -- Draw selection indicator
                if entry_index == selected_item then
                    canvas.set_color("#FFCC00")
                    canvas.draw_text(item_x + SELECTOR_OFFSET_X, draw_y, SELECTOR_CHAR)
                end

                -- Build label: "Enchant Shortsword (I/III)"
                local tier_text = to_roman(current_tier) .. "/" .. to_roman(max_tier)
                local label = upgrade_def.label .. " " .. item_name .. " (" .. tier_text .. ")"

                -- Color based on purchase state
                if is_maxed then
                    canvas.set_color("#888888")
                elseif not can_buy then
                    canvas.set_color("#AA5555")
                elseif entry_index == selected_item then
                    canvas.set_color("#FFFFFF")
                else
                    canvas.set_color("#CCCCCC")
                end

                canvas.draw_text(item_x, draw_y, label)

                -- Draw price
                local price_text
                if is_maxed then
                    price_text = "MAXED"
                else
                    local next_tier = upgrade_def.tiers[current_tier + 1]
                    if next_tier.material and next_tier.gold > 0 then
                        local mat_def = stackable_item_registry[next_tier.material]
                        local mat_name = mat_def and mat_def.name or next_tier.material
                        price_text = tostring(next_tier.gold) .. "g + " .. mat_name
                    elseif next_tier.material then
                        local mat_def = stackable_item_registry[next_tier.material]
                        price_text = mat_def and mat_def.name or next_tier.material
                    else
                        price_text = tostring(next_tier.gold) .. "g"
                    end
                end
                canvas.set_text_align("right")
                canvas.draw_text(box_x + box_w - TEXT_PADDING_RIGHT, draw_y, price_text)
                canvas.set_text_align("left")

                item_y = item_y + LINE_HEIGHT
            end

            -- Page indicator row (on the 5th item row)
            if total_pages > 1 then
                local page_y = item_y + FONT_SIZE
                local left_x = text_x + ITEM_INDENT
                local page_text = "Page " .. current_page .. " / " .. total_pages
                canvas.set_color("#AAAAAA")
                canvas.draw_text(left_x, page_y, page_text)

                -- Draw left/right navigation icons
                local text_w = canvas.get_text_width(page_text)
                local icon_size = ICON_SIZE
                local icon_y = page_y - FONT_SIZE + (FONT_SIZE - icon_size) / 2
                local mode = controls.get_last_input_device()
                if current_page > 1 then
                    local icon_x = left_x - ICON_SPACING - icon_size
                    if mode == "gamepad" then
                        sprites.controls.draw_button(canvas.buttons.DPAD_LEFT, icon_x, icon_y, BUTTON_SCALE)
                    else
                        sprites.controls.draw_key(canvas.keys.LEFT, icon_x, icon_y, KEY_SCALE)
                    end
                end
                if current_page < total_pages then
                    local icon_x = left_x + text_w + ICON_SPACING
                    if mode == "gamepad" then
                        sprites.controls.draw_button(canvas.buttons.DPAD_RIGHT, icon_x, icon_y, BUTTON_SCALE)
                    else
                        sprites.controls.draw_key(canvas.keys.RIGHT, icon_x, icon_y, KEY_SCALE)
                    end
                end
            end

            -- Draw selected item description and material requirement
            if upgradeable_items[selected_item] then
                local entry = upgradeable_items[selected_item]
                local current_tier = (player_ref.upgrade_tiers and player_ref.upgrade_tiers[entry.id]) or 0
                local is_maxed = current_tier >= #entry.def.tiers

                if not is_maxed then
                    local next_tier = entry.def.tiers[current_tier + 1]
                    local desc = entry.def.description
                    local desc_y = box_y + box_h - TEXT_PADDING_TOP - LINE_HEIGHT + 2

                    if next_tier.material then
                        -- Draw description in gray, then "Requires: " in green, cost in gold
                        canvas.set_color("#AAAAAA")
                        canvas.draw_text(text_x, desc_y, desc)
                        local desc_w = canvas.get_text_width(desc)

                        local req_text = " Requires: "
                        canvas.set_color("#558855")
                        canvas.draw_text(text_x + desc_w, desc_y, req_text)
                        local req_w = canvas.get_text_width(req_text)

                        local mat_def = stackable_item_registry[next_tier.material]
                        local mat_name = mat_def and mat_def.name or next_tier.material
                        local cost_text = mat_name
                        if next_tier.gold > 0 then
                            cost_text = tostring(next_tier.gold) .. "g + " .. mat_name
                        end
                        canvas.set_color("#CC9933")
                        canvas.draw_text(text_x + desc_w + req_w, desc_y, cost_text)
                    else
                        canvas.set_color("#AAAAAA")
                        canvas.draw_text(text_x, desc_y, desc)
                    end
                end
            end
        else
            -- No upgradeable items
            canvas.set_color("#AAAAAA")
            canvas.set_text_align("center")
            canvas.draw_text(box_x + box_w / 2, box_y + box_h / 2, "You have nothing I can work with.")
            canvas.set_text_align("left")
        end

        draw_close_hint(box_x, box_w, box_y, box_h)
        canvas.restore()
    end

    canvas.set_global_alpha(1)
    canvas.set_text_baseline("alphabetic")
end

--- Get the camera Y offset for world rendering during upgrade screen
---@return number offset_y Y offset in pixels (0 when not active)
function upgrade_screen.get_camera_offset_y()
    if state == STATE.HIDDEN then return 0 end
    return DIALOGUE_AREA_HEIGHT * config.ui.SCALE * get_alpha()
end

return upgrade_screen
