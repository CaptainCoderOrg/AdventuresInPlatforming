--- Pickup dialogue for equippable items (weapons, accessories, secondaries, shields)
--- Shows item icon, name, description with "Equip" and "Add to Inventory" options
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")
local simple_dialogue = require("ui/simple_dialogue")
local sprites = require("sprites")
local TextDisplay = require("TextDisplay")
local prop_common = require("Prop.common")
local unique_item_registry = require("Prop.unique_item_registry")
local weapon_sync = require("player.weapon_sync")
local utils = require("ui/utils")

local pickup_dialogue = {}

-- State machine
local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
}

local FADE_DURATION = 0.3

-- Dialogue dimensions (at 1x scale)
local DIALOG_WIDTH = 160
local DIALOG_HEIGHT = 80

-- Layout constants
local ICON_SIZE = 16
local ICON_PADDING = 8
local NAME_Y = ICON_PADDING + 2
local DESC_Y = ICON_PADDING + ICON_SIZE + 4
local BUTTON_Y = 62
local BUTTON_SPACING = 20

-- Number of ability slots for secondary items
local ABILITY_SLOT_COUNT = controls.ABILITY_SLOT_COUNT

-- State
local state = STATE.HIDDEN
local fade_progress = 0
local focused_index = 1  -- 1 = Equip, 2 = Add to Inventory
local current_item_id = nil
local current_player = nil
local on_complete_callback = nil
local is_no_equip = false  -- True for no_equip items (single button mode)
local is_info_only = false  -- True for info-only mode (no inventory add)

-- Input blocking (prevents jump on dialogue close)
local block_input_frames = 0

-- Mouse tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

-- Dialog box instance
local dialog_box = simple_dialogue.create({
    x = 0,
    y = 0,
    width = DIALOG_WIDTH,
    height = DIALOG_HEIGHT,
})

-- Cached button metrics (initialized on first use)
local button_metrics_cached = false
local equip_metrics = nil
local inventory_metrics = nil
local ok_metrics = nil
local button_total_width = nil
local button_start_x = nil
local inventory_start_x = nil
local ok_start_x = nil

-- Reusable tables for word wrapping (avoids per-frame allocation)
local words_cache = {}
local line_words_cache = {}

-- Sprite scales for keybinding icons (sized to match 7px font)
local KEYBOARD_SCALE = 0.125      -- 64px * 0.125 = 8px
local KEYBOARD_WORD_SCALE = 0.15  -- 64px * 0.15 = ~10px for word keys
local GAMEPAD_SCALE = 0.5         -- 16px * 0.5 = 8px
local GAMEPAD_SHOULDER_SCALE = 0.6 -- 16px * 0.6 = ~10px for shoulder buttons
local DESC_FONT_SIZE = 7

--- Get sprite scale for a key code
---@param code number Key code
---@return number Scale multiplier
local function get_key_scale(code)
    if sprites.controls.is_word_key(code) then
        return KEYBOARD_WORD_SCALE
    end
    return KEYBOARD_SCALE
end

--- Get sprite scale for a button code
---@param code number Button code
---@return number Scale multiplier
local function get_button_scale(code)
    if sprites.controls.is_shoulder_button(code) then
        return GAMEPAD_SHOULDER_SCALE
    end
    return GAMEPAD_SCALE
end

--- Get sprite size for keybinding icon
---@param scheme string "keyboard" or "gamepad"
---@param code number Key/button code
---@return number Sprite size in pixels
local function get_sprite_size(scheme, code)
    if scheme == "gamepad" then
        return 16 * get_button_scale(code)
    else
        return 64 * get_key_scale(code)
    end
end

--- Draw a keybinding sprite at the given position
---@param scheme string "keyboard" or "gamepad"
---@param code number Key/button code
---@param x number X position
---@param y number Y position (text baseline)
---@return number Width of drawn sprite
local function draw_keybind_sprite(scheme, code, x, y)
    local sprite_size = get_sprite_size(scheme, code)
    local sprite_y = y - DESC_FONT_SIZE + (DESC_FONT_SIZE - sprite_size) / 2

    if scheme == "gamepad" then
        sprites.controls.draw_button(code, x, sprite_y, get_button_scale(code))
    else
        sprites.controls.draw_key(code, x, sprite_y, get_key_scale(code))
    end

    return sprite_size
end

--- Get the width of a word, accounting for keybinding placeholders
---@param word string Word possibly containing {action} placeholders
---@param scheme string "keyboard" or "gamepad"
---@return number Width in pixels
local function get_word_width(word, scheme)
    local segments = TextDisplay.parse_segments(word)
    local total_width = 0

    for _, segment in ipairs(segments) do
        if segment.type == "text" then
            total_width = total_width + canvas.get_text_width(segment.value)
        elseif segment.type == "color_start" or segment.type == "color_end" then
            -- Color tags have no width
        else
            local seg_scheme, code = TextDisplay.resolve_segment(segment, scheme)
            if seg_scheme and code then
                total_width = total_width + get_sprite_size(seg_scheme, code)
            end
        end
    end

    return total_width
end

--- Draw a word with keybinding sprite support
---@param word string Word possibly containing {action} placeholders
---@param scheme string "keyboard" or "gamepad"
---@param x number X position
---@param y number Y position (baseline)
---@param text_color string Default text color
---@return number Width drawn
local function draw_word(word, scheme, x, y, text_color)
    local segments = TextDisplay.parse_segments(word)
    local current_x = x

    for _, segment in ipairs(segments) do
        if segment.type == "color_start" then
            canvas.set_color(segment.value)
        elseif segment.type == "color_end" then
            canvas.set_color(text_color)
        elseif segment.type == "text" then
            canvas.set_color(text_color)
            canvas.draw_text(current_x, y, segment.value)
            current_x = current_x + canvas.get_text_width(segment.value)
        else
            local seg_scheme, code = TextDisplay.resolve_segment(segment, scheme)
            if seg_scheme and code then
                current_x = current_x + draw_keybind_sprite(seg_scheme, code, current_x, y)
            end
        end
    end

    return current_x - x
end

--- Draw a line of words with spacing and keybinding support
---@param words table Array of words to draw
---@param scheme string "keyboard" or "gamepad"
---@param x number Starting X position
---@param y number Y position (baseline)
---@param text_color string Default text color
---@param space_width number Width of space character
local function draw_word_line(words, scheme, x, y, text_color, space_width)
    local draw_x = x
    for i, word in ipairs(words) do
        if i > 1 then
            canvas.set_color(text_color)
            canvas.draw_text(draw_x, y, " ")
            draw_x = draw_x + space_width
        end
        draw_x = draw_x + draw_word(word, scheme, draw_x, y, text_color)
    end
end

--- Ensure button metrics are cached (called once on first use)
local function ensure_button_metrics()
    if button_metrics_cached then return end
    canvas.set_font_family("menu_font")
    canvas.set_font_size(7)
    equip_metrics = canvas.get_text_metrics("Equip")
    inventory_metrics = canvas.get_text_metrics("Add to Inventory")
    ok_metrics = canvas.get_text_metrics("OK")
    button_total_width = equip_metrics.width + BUTTON_SPACING + inventory_metrics.width
    button_start_x = (DIALOG_WIDTH - button_total_width) / 2
    inventory_start_x = button_start_x + equip_metrics.width + BUTTON_SPACING
    ok_start_x = (DIALOG_WIDTH - ok_metrics.width) / 2
    button_metrics_cached = true
end

--- Get the item definition for the current item (checks unique then stackable registries)
---@return table|nil item_def
local function get_item_def()
    if not current_item_id then return nil end
    return prop_common.get_item_def(current_item_id)
end

--- Equip the current item to the player
--- Handles exclusive types (shields), secondary limits, and active weapon/secondary tracking
---@param player table Player instance
---@param item_id string Item to equip
local function equip_item(player, item_id)
    local item_def = unique_item_registry[item_id]
    if not item_def then return end

    -- Ensure equipped_items table exists
    if not player.equipped_items then
        player.equipped_items = {}
    end

    local item_type = item_def.type

    -- For secondaries, assign to first empty ability slot
    if item_type == "secondary" then
        if not player.ability_slots then
            player.ability_slots = { nil, nil, nil, nil, nil, nil }
        end
        local assigned = false
        for i = 1, ABILITY_SLOT_COUNT do
            if not player.ability_slots[i] then
                player.ability_slots[i] = item_id
                assigned = true
                break
            end
        end
        if not assigned then
            -- All ability slots full, just add to inventory without equipping
            return
        end
    end

    -- Equip the item
    player.equipped_items[item_id] = true

    -- Set as active weapon for first of type
    if item_type == "weapon" then
        player.active_weapon = item_id
    end

    -- Sync player ability flags
    weapon_sync.sync(player)
end

--- Show the pickup dialogue for an item
---@param item_id string The item ID to show
---@param player table The player instance
---@param on_complete function|nil Callback when dialogue closes (receives equip boolean)
---@param options table|nil Optional settings: { info_only = true } shows item info with OK button only
function pickup_dialogue.show(item_id, player, on_complete, options)
    if state ~= STATE.HIDDEN then return end

    current_item_id = item_id
    current_player = player
    on_complete_callback = on_complete
    focused_index = 1
    mouse_active = true
    state = STATE.FADING_IN
    fade_progress = 0

    is_info_only = options and options.info_only or false

    -- Check if this is a no_equip item or info-only (single button mode)
    local item_def = prop_common.get_item_def(item_id)
    is_no_equip = is_info_only or (item_def and item_def.type == "no_equip")
end

--- Check if the dialogue is active (not hidden)
---@return boolean is_active
function pickup_dialogue.is_active()
    return state ~= STATE.HIDDEN
end

--- Check if player input should be blocked (dialogue just closed)
---@return boolean should_block
function pickup_dialogue.should_block_input()
    return block_input_frames > 0
end

--- Close the dialogue and trigger the callback
---@param equip boolean Whether the player chose to equip
local function close_dialogue(equip)
    state = STATE.FADING_OUT
    fade_progress = 0

    if not is_info_only and current_player and current_item_id then
        -- Add to inventory (unique_items)
        table.insert(current_player.unique_items, current_item_id)

        -- Equip if chosen
        if equip then
            equip_item(current_player, current_item_id)
        end
    end
end

--- Process input for the dialogue
function pickup_dialogue.input()
    if state ~= STATE.OPEN then return end

    -- For no_equip items, only confirm is needed
    if is_no_equip then
        if controls.menu_confirm_pressed() then
            close_dialogue(false)
        end
        return
    end

    -- Left/Right to switch selection
    if controls.menu_left_pressed() then
        mouse_active = false
        focused_index = 1
    elseif controls.menu_right_pressed() then
        mouse_active = false
        focused_index = 2
    end

    -- Confirm to select
    if controls.menu_confirm_pressed() then
        close_dialogue(focused_index == 1)
    end

    -- Note: ESC does NOT close dialogue - player must choose an option
end

--- Update the dialogue animations and mouse input
---@param dt number Delta time in seconds
function pickup_dialogue.update(dt)
    -- Decrement input block counter (runs even when hidden)
    if block_input_frames > 0 then
        block_input_frames = block_input_frames - 1
    end

    if state == STATE.HIDDEN then return end

    local speed = dt / FADE_DURATION

    if state == STATE.FADING_IN then
        fade_progress = math.min(1, fade_progress + speed)
        if fade_progress >= 1 then
            state = STATE.OPEN
        end
    elseif state == STATE.FADING_OUT then
        fade_progress = math.max(0, fade_progress - speed)
        if fade_progress <= 0 then
            state = STATE.HIDDEN
            -- Block player input for 2 frames to prevent jump on close
            block_input_frames = 2
            -- Trigger callback after fully closed
            if on_complete_callback then
                on_complete_callback()
                on_complete_callback = nil
            end
            current_item_id = nil
            current_player = nil
        end
    end

    -- Mouse hover handling
    if state == STATE.OPEN then
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local screen_h = canvas.get_height()

        local menu_x = (screen_w - DIALOG_WIDTH * scale) / 2
        local menu_y = (screen_h - DIALOG_HEIGHT * scale) / 2

        local local_mx = (canvas.get_mouse_x() - menu_x) / scale
        local local_my = (canvas.get_mouse_y() - menu_y) / scale

        -- Re-enable mouse input if mouse has moved
        local raw_mx = canvas.get_mouse_x()
        local raw_my = canvas.get_mouse_y()
        if raw_mx ~= last_mouse_x or raw_my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x = raw_mx
            last_mouse_y = raw_my
        end

        if mouse_active then
            ensure_button_metrics()
            local button_height = 10

            if is_no_equip then
                -- Check OK button hover (single centered button)
                if local_mx >= ok_start_x and local_mx <= ok_start_x + ok_metrics.width and
                   local_my >= BUTTON_Y and local_my <= BUTTON_Y + button_height then
                    if canvas.is_mouse_pressed(0) then
                        close_dialogue(false)
                    end
                end
            else
                -- Check Equip button hover
                if local_mx >= button_start_x and local_mx <= button_start_x + equip_metrics.width and
                   local_my >= BUTTON_Y and local_my <= BUTTON_Y + button_height then
                    focused_index = 1
                    if canvas.is_mouse_pressed(0) then
                        close_dialogue(true)
                    end
                end

                -- Check Inventory button hover
                if local_mx >= inventory_start_x and local_mx <= inventory_start_x + inventory_metrics.width and
                   local_my >= BUTTON_Y and local_my <= BUTTON_Y + button_height then
                    focused_index = 2
                    if canvas.is_mouse_pressed(0) then
                        close_dialogue(false)
                    end
                end
            end
        end
    end
end

--- Draw the pickup dialogue
function pickup_dialogue.draw()
    if state == STATE.HIDDEN then return end

    local item_def = get_item_def()
    if not item_def then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    local menu_x = (screen_w - DIALOG_WIDTH * scale) / 2
    local menu_y = (screen_h - DIALOG_HEIGHT * scale) / 2

    -- Calculate alpha based on fade state
    local alpha = (state == STATE.FADING_IN or state == STATE.FADING_OUT) and fade_progress or 1

    -- Draw background overlay
    canvas.set_global_alpha(alpha)
    canvas.set_color("#00000080")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Apply canvas transform for pixel-perfect scaling
    canvas.save()
    canvas.translate(menu_x, menu_y)
    canvas.scale(scale, scale)

    -- Draw dialogue box
    simple_dialogue.draw(dialog_box)

    -- Draw item icon
    local icon_x = ICON_PADDING
    local icon_y = ICON_PADDING
    if item_def.static_sprite then
        canvas.draw_image(item_def.static_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE)
    elseif item_def.animated_sprite then
        -- Draw first frame of animated sprite
        canvas.draw_image(item_def.animated_sprite, icon_x, icon_y, ICON_SIZE, ICON_SIZE,
            0, 0, ICON_SIZE, ICON_SIZE)
    end

    -- Draw item name (yellow, beside icon)
    canvas.set_font_family("menu_font")
    canvas.set_font_size(8)
    canvas.set_text_baseline("top")
    canvas.set_text_align("left")
    utils.draw_outlined_text(item_def.name, ICON_PADDING + ICON_SIZE + 4, NAME_Y, "#FFFF00")

    -- Draw description (gray, wrapped, with keybinding support)
    canvas.set_font_size(DESC_FONT_SIZE)
    canvas.set_text_baseline("bottom")
    local desc = item_def.description or ""
    local desc_x = ICON_PADDING
    local desc_max_width = DIALOG_WIDTH - ICON_PADDING * 2
    local scheme = controls.get_binding_scheme()
    local text_color = "#AAAAAA"

    -- Clear and reuse cached tables
    for i = 1, #words_cache do words_cache[i] = nil end
    for word in desc:gmatch("%S+") do
        words_cache[#words_cache + 1] = word
    end

    for i = 1, #line_words_cache do line_words_cache[i] = nil end
    local line_width = 0
    local space_width = canvas.get_text_width(" ")
    local line_y = DESC_Y
    local LINE_HEIGHT = 8

    for _, word in ipairs(words_cache) do
        local word_width = get_word_width(word, scheme)
        local test_width = line_width + (line_width > 0 and space_width or 0) + word_width

        if test_width > desc_max_width and line_width > 0 then
            draw_word_line(line_words_cache, scheme, desc_x, line_y + DESC_FONT_SIZE, text_color, space_width)
            line_y = line_y + LINE_HEIGHT
            for i = 1, #line_words_cache do line_words_cache[i] = nil end
            line_words_cache[1] = word
            line_width = word_width
        else
            line_words_cache[#line_words_cache + 1] = word
            line_width = test_width
        end
    end

    if #line_words_cache > 0 then
        draw_word_line(line_words_cache, scheme, desc_x, line_y + DESC_FONT_SIZE, text_color, space_width)
    end

    -- Draw buttons
    canvas.set_font_size(7)
    canvas.set_text_baseline("top")
    ensure_button_metrics()

    if is_no_equip then
        -- Single centered OK button for no_equip items
        utils.draw_outlined_text("OK", ok_start_x, BUTTON_Y, "#FFFF00")
    else
        -- Draw Equip button
        local equip_color = focused_index == 1 and "#FFFF00" or "#FFFFFF"
        utils.draw_outlined_text("Equip", button_start_x, BUTTON_Y, equip_color)

        -- Draw separator
        canvas.set_color("#888888")
        canvas.draw_text(button_start_x + equip_metrics.width + 4, BUTTON_Y, "|")

        -- Draw Inventory button
        local inventory_color = focused_index == 2 and "#FFFF00" or "#FFFFFF"
        utils.draw_outlined_text("Add to Inventory", inventory_start_x, BUTTON_Y, inventory_color)
    end

    canvas.restore()
    canvas.set_global_alpha(1)
end

return pickup_dialogue
