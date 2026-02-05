--- Split-screen shop UI with camera shift
--- Displays shop items in bottom area while showing map view in top area
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local shop_registry = require("shop/registry")
local transactions = require("shop/transactions")

local shop_screen = {}

-- State machine states
local STATE = {
    HIDDEN = 1,
    FADING_IN = 2,
    OPEN = 3,
    FADING_OUT = 4,
}

-- Layout constants (at 1x scale, scaled by config.ui.SCALE)
local MAP_VIEW_HEIGHT = 48         -- Top area showing game world
local DIALOGUE_AREA_HEIGHT = 168   -- Bottom area for shop
local PLAYER_MARGIN = 8            -- Player's margin from bottom of map view
local FADE_DURATION = 0.3          -- Fade in/out duration in seconds

-- Shop box layout (at 1x scale)
local BOX_MARGIN_X = 32            -- Horizontal margin from screen edges
local BOX_MARGIN_BOTTOM = 16       -- Margin from bottom of screen
local BOX_HEIGHT = 120             -- Shop box height (taller for items)
local TEXT_PADDING_TOP = 10
local TEXT_PADDING_LEFT = 12
local TEXT_PADDING_RIGHT = 12
local LINE_HEIGHT = 12
local ITEM_INDENT = 8
local FONT_SIZE = 8

-- Selection indicator
local SELECTOR_CHAR = ">"
local SELECTOR_OFFSET_X = -10

-- Gold display
local GOLD_LABEL = "Gold: "

-- 9-slice definition (reuse simple_dialogue sprite)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Module state
local state = STATE.HIDDEN
local fade_progress = 0
local current_shop = nil
local selected_item = 1
local player_ref = nil
local camera_ref = nil
local original_viewport_height = nil
local original_camera_y = nil
local target_camera_y = nil
local purchase_message = nil
local purchase_message_timer = 0
local PURCHASE_MESSAGE_DURATION = 1.5

-- Mouse support
local mouse_active = false
local last_mouse_x, last_mouse_y = 0, 0
local item_positions = {}

--- Start a shop with the given shop ID
---@param shop_id string Shop identifier
---@param player table Player instance
---@param camera table Camera instance
function shop_screen.start(shop_id, player, camera)
    local shop = shop_registry.get(shop_id)
    if not shop then
        return
    end

    current_shop = shop
    player_ref = player
    camera_ref = camera
    selected_item = 1
    purchase_message = nil
    purchase_message_timer = 0

    -- Reset mouse state
    mouse_active = false
    item_positions = {}

    -- Save original camera state
    original_viewport_height = camera:get_viewport_height()
    original_camera_y = camera:get_y()

    -- Calculate target camera Y to position player with margin below their feet
    local tile_size = config.ui.TILE  -- base tile size (16px)
    local viewport_tiles = MAP_VIEW_HEIGHT / tile_size  -- 48/16 = 3 tiles
    local margin_tiles = PLAYER_MARGIN / tile_size  -- 8/16 = 0.5 tiles
    -- player.y (feet) should appear with margin_tiles below, accounting for player height
    target_camera_y = player.y - (viewport_tiles - margin_tiles) + 1

    state = STATE.FADING_IN
    fade_progress = 0
end

--- Check if shop screen is currently active
---@return boolean True if shop is visible or transitioning
function shop_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Close the shop
local function close_shop()
    state = STATE.FADING_OUT
    fade_progress = 0
end

--- Process input for shop navigation
function shop_screen.input()
    if state ~= STATE.OPEN then return end

    -- Navigate items
    if controls.menu_up_pressed() then
        mouse_active = false
        if selected_item > 1 then
            selected_item = selected_item - 1
        end
    elseif controls.menu_down_pressed() then
        mouse_active = false
        if current_shop and current_shop.items and selected_item < #current_shop.items then
            selected_item = selected_item + 1
        end
    elseif controls.menu_confirm_pressed() then
        -- Attempt purchase
        if current_shop and current_shop.items and current_shop.items[selected_item] then
            local item = current_shop.items[selected_item]
            local can_buy, reason = transactions.can_purchase(player_ref, item)

            if can_buy then
                local success = transactions.purchase(player_ref, item)
                if success then
                    purchase_message = "Purchased " .. item.name
                else
                    purchase_message = "Purchase failed"
                end
            else
                purchase_message = reason or "Cannot purchase"
            end
            purchase_message_timer = PURCHASE_MESSAGE_DURATION
        end
    elseif controls.menu_back_pressed() then
        -- Close shop
        close_shop()
    end
end

--- Update shop screen state
---@param dt number Delta time in seconds
function shop_screen.update(dt)
    if state == STATE.HIDDEN then return end

    -- Update purchase message timer
    if purchase_message_timer > 0 then
        purchase_message_timer = purchase_message_timer - dt
        if purchase_message_timer <= 0 then
            purchase_message = nil
        end
    end

    -- Mouse hover detection (only when OPEN)
    if state == STATE.OPEN then
        local mx, my = canvas.get_mouse_x(), canvas.get_mouse_y()

        -- Detect mouse movement to enable mouse mode
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x, last_mouse_y = mx, my
        end

        -- Mouse hover over items
        if mouse_active and #item_positions > 0 then
            local half_line = (LINE_HEIGHT * config.ui.SCALE) / 2
            for i, pos in ipairs(item_positions) do
                if mx >= pos.x_start and mx <= pos.x_end and
                   my >= pos.y - half_line and my <= pos.y + half_line then
                    selected_item = i

                    -- Click to attempt purchase
                    if canvas.is_mouse_pressed(0) then
                        if current_shop and current_shop.items and current_shop.items[selected_item] then
                            local item = current_shop.items[selected_item]
                            local can_buy, reason = transactions.can_purchase(player_ref, item)

                            if can_buy then
                                local success = transactions.purchase(player_ref, item)
                                if success then
                                    purchase_message = "Purchased " .. item.name
                                else
                                    purchase_message = "Purchase failed"
                                end
                            else
                                purchase_message = reason or "Cannot purchase"
                            end
                            purchase_message_timer = PURCHASE_MESSAGE_DURATION
                        end
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
        -- Update camera during fade
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
            -- Restore camera
            if camera_ref then
                camera_ref:set_y(original_camera_y)
            end
            -- Clean up
            current_shop = nil
            player_ref = nil
            camera_ref = nil
        else
            -- Restore camera during fade out
            if camera_ref and target_camera_y then
                local t = 1 - fade_progress
                local new_y = original_camera_y + (target_camera_y - original_camera_y) * t
                camera_ref:set_y(new_y)
            end
        end
    end
end

--- Draw the shop screen overlay
function shop_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Calculate alpha based on state
    local alpha = 0
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.OPEN then
        alpha = 1
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    -- Calculate dialogue area position (bottom portion of screen)
    local map_view_height = MAP_VIEW_HEIGHT * scale
    local dialogue_area_y = map_view_height

    canvas.set_global_alpha(alpha)

    -- Draw black overlay over shop area
    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, dialogue_area_y, screen_w, screen_h - dialogue_area_y)

    -- Draw shop box if we have content
    if current_shop and alpha > 0 then
        canvas.save()
        canvas.scale(scale, scale)

        -- Calculate box dimensions (at 1x scale)
        local base_w = screen_w / scale
        local base_h = screen_h / scale
        local box_x = BOX_MARGIN_X
        local box_w = base_w - BOX_MARGIN_X * 2
        local box_y = base_h - BOX_MARGIN_BOTTOM - BOX_HEIGHT
        local box_h = BOX_HEIGHT

        -- Draw 9-slice background
        nine_slice.draw(slice, box_x, box_y, box_w, box_h)

        -- Set up text rendering
        canvas.set_font_family("menu_font")
        canvas.set_font_size(FONT_SIZE)
        canvas.set_text_baseline("bottom")

        local text_x = box_x + TEXT_PADDING_LEFT
        local text_y = box_y + TEXT_PADDING_TOP

        -- Draw shop name/greeting
        canvas.set_color("#FFCC00")
        canvas.draw_text(text_x, text_y + FONT_SIZE, current_shop.name or "Shop")

        -- Draw gold amount
        local gold_text = GOLD_LABEL .. tostring(player_ref and player_ref.gold or 0)
        canvas.set_color("#FFD700")
        canvas.set_text_align("right")
        canvas.draw_text(box_x + box_w - TEXT_PADDING_RIGHT, text_y + FONT_SIZE, gold_text)
        canvas.set_text_align("left")

        -- Draw items
        item_positions = {}
        local item_y = text_y + LINE_HEIGHT * 2

        if current_shop.items then
            for i, item in ipairs(current_shop.items) do
                local draw_y = item_y + FONT_SIZE
                local item_x = text_x + ITEM_INDENT

                -- Store item position in screen coordinates for mouse detection
                item_positions[i] = {
                    y = draw_y * scale,
                    x_start = (item_x + SELECTOR_OFFSET_X) * scale,
                    x_end = (box_x + box_w - TEXT_PADDING_RIGHT) * scale,
                }

                -- Check if item can be purchased
                local can_buy, reason = transactions.can_purchase(player_ref, item)

                -- Draw selection indicator
                if i == selected_item then
                    canvas.set_color("#FFCC00")
                    canvas.draw_text(item_x + SELECTOR_OFFSET_X, draw_y, SELECTOR_CHAR)
                end

                -- Draw item name with appropriate color
                if not can_buy then
                    if reason == "Already owned" or reason == "Max owned" then
                        canvas.set_color("#888888")
                    else
                        canvas.set_color("#AA5555")
                    end
                elseif i == selected_item then
                    canvas.set_color("#FFFFFF")
                else
                    canvas.set_color("#CCCCCC")
                end

                canvas.draw_text(item_x, draw_y, item.name or "???")

                -- Draw price
                local price_text = tostring(item.price) .. "g"
                if not can_buy and reason == "Already owned" then
                    price_text = "OWNED"
                elseif not can_buy and reason == "Max owned" then
                    price_text = "MAX"
                end
                canvas.set_text_align("right")
                canvas.draw_text(box_x + box_w - TEXT_PADDING_RIGHT, draw_y, price_text)
                canvas.set_text_align("left")

                item_y = item_y + LINE_HEIGHT
            end
        end

        -- Draw selected item description
        if current_shop.items and current_shop.items[selected_item] then
            local desc = current_shop.items[selected_item].description
            if desc then
                canvas.set_color("#AAAAAA")
                local desc_y = box_y + box_h - TEXT_PADDING_TOP
                canvas.draw_text(text_x, desc_y, desc)
            end
        end

        -- Draw purchase message
        if purchase_message then
            local msg_alpha = math.min(1, purchase_message_timer / 0.5)
            canvas.set_global_alpha(alpha * msg_alpha)
            canvas.set_color("#00FF00")
            canvas.set_text_align("center")
            canvas.draw_text(box_x + box_w / 2, box_y + box_h / 2, purchase_message)
            canvas.set_text_align("left")
            canvas.set_global_alpha(alpha)
        end

        -- Draw exit hint
        canvas.set_color("#666666")
        canvas.draw_text(text_x, box_y + box_h - 4, "Press {menu} to close")

        canvas.restore()
    end

    canvas.set_global_alpha(1)
    canvas.set_text_baseline("alphabetic")
end

--- Get the camera Y offset for world rendering during shop
---@return number offset_y Y offset in pixels (0 when not active)
function shop_screen.get_camera_offset_y()
    if state == STATE.HIDDEN then return 0 end

    local scale = config.ui.SCALE
    local dialogue_area_height = DIALOGUE_AREA_HEIGHT * scale

    local alpha = 0
    if state == STATE.FADING_IN then
        alpha = fade_progress
    elseif state == STATE.OPEN then
        alpha = 1
    elseif state == STATE.FADING_OUT then
        alpha = 1 - fade_progress
    end

    return dialogue_area_height * alpha
end

return shop_screen
