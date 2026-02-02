--- Control sprites for drawing keyboard keys and gamepad buttons
local canvas = require("canvas")
local config = require("config")
local controls_config = require("config/controls")

local controls = {}

-- Sprite base size (all individual sprites are 64x64)
local SPRITE_SIZE = 64

-- Asset path prefix
local KEYBOARD_PATH = "sprites/ui/controls/keyboard/"
local GAMEPAD_PATH = "sprites/ui/controls/gamepad/"

--- Load a keyboard sprite image and return its asset key for later drawing
---@param name string Sprite filename without path or extension (e.g., "keyboard_a")
---@return string asset_key The registered asset key for canvas.draw_image
local function load_key(name)
    local asset_key = "ui_key_" .. name
    canvas.assets.load_image(asset_key, KEYBOARD_PATH .. name .. ".png")
    return asset_key
end

-- Keyboard key sprite mappings: canvas.keys.* -> asset key
-- All sprites loaded upfront at module initialization
local key_sprites = {
    -- Letters A-Z
    [canvas.keys.A] = load_key("keyboard_a"),
    [canvas.keys.B] = load_key("keyboard_b"),
    [canvas.keys.C] = load_key("keyboard_c"),
    [canvas.keys.D] = load_key("keyboard_d"),
    [canvas.keys.E] = load_key("keyboard_e"),
    [canvas.keys.F] = load_key("keyboard_f"),
    [canvas.keys.G] = load_key("keyboard_g"),
    [canvas.keys.H] = load_key("keyboard_h"),
    [canvas.keys.I] = load_key("keyboard_i"),
    [canvas.keys.J] = load_key("keyboard_j"),
    [canvas.keys.K] = load_key("keyboard_k"),
    [canvas.keys.L] = load_key("keyboard_l"),
    [canvas.keys.M] = load_key("keyboard_m"),
    [canvas.keys.N] = load_key("keyboard_n"),
    [canvas.keys.O] = load_key("keyboard_o"),
    [canvas.keys.P] = load_key("keyboard_p"),
    [canvas.keys.Q] = load_key("keyboard_q"),
    [canvas.keys.R] = load_key("keyboard_r"),
    [canvas.keys.S] = load_key("keyboard_s"),
    [canvas.keys.T] = load_key("keyboard_t"),
    [canvas.keys.U] = load_key("keyboard_u"),
    [canvas.keys.V] = load_key("keyboard_v"),
    [canvas.keys.W] = load_key("keyboard_w"),
    [canvas.keys.X] = load_key("keyboard_x"),
    [canvas.keys.Y] = load_key("keyboard_y"),
    [canvas.keys.Z] = load_key("keyboard_z"),

    -- Numbers 0-9
    [canvas.keys.DIGIT_0] = load_key("keyboard_0"),
    [canvas.keys.DIGIT_1] = load_key("keyboard_1"),
    [canvas.keys.DIGIT_2] = load_key("keyboard_2"),
    [canvas.keys.DIGIT_3] = load_key("keyboard_3"),
    [canvas.keys.DIGIT_4] = load_key("keyboard_4"),
    [canvas.keys.DIGIT_5] = load_key("keyboard_5"),
    [canvas.keys.DIGIT_6] = load_key("keyboard_6"),
    [canvas.keys.DIGIT_7] = load_key("keyboard_7"),
    [canvas.keys.DIGIT_8] = load_key("keyboard_8"),
    [canvas.keys.DIGIT_9] = load_key("keyboard_9"),

    -- Function keys
    [canvas.keys.F1] = load_key("keyboard_f1"),
    [canvas.keys.F2] = load_key("keyboard_f2"),
    [canvas.keys.F3] = load_key("keyboard_f3"),
    [canvas.keys.F4] = load_key("keyboard_f4"),
    [canvas.keys.F5] = load_key("keyboard_f5"),
    [canvas.keys.F6] = load_key("keyboard_f6"),
    [canvas.keys.F7] = load_key("keyboard_f7"),
    [canvas.keys.F8] = load_key("keyboard_f8"),
    [canvas.keys.F9] = load_key("keyboard_f9"),
    [canvas.keys.F10] = load_key("keyboard_f10"),
    [canvas.keys.F11] = load_key("keyboard_f11"),
    [canvas.keys.F12] = load_key("keyboard_f12"),

    -- Arrow keys
    [canvas.keys.UP] = load_key("keyboard_arrow_up"),
    [canvas.keys.DOWN] = load_key("keyboard_arrow_down"),
    [canvas.keys.LEFT] = load_key("keyboard_arrow_left"),
    [canvas.keys.RIGHT] = load_key("keyboard_arrow_right"),

    -- Modifier keys
    [canvas.keys.SHIFT] = load_key("keyboard_shift"),
    [canvas.keys.CTRL] = load_key("keyboard_ctrl"),
    [canvas.keys.ALT] = load_key("keyboard_alt"),
    [canvas.keys.TAB] = load_key("keyboard_tab"),
    [canvas.keys.CAPS_LOCK] = load_key("keyboard_capslock"),

    -- Special keys
    [canvas.keys.SPACE] = load_key("keyboard_space"),
    [canvas.keys.ENTER] = load_key("keyboard_enter"),
    [canvas.keys.BACKSPACE] = load_key("keyboard_backspace"),
    [canvas.keys.DELETE] = load_key("keyboard_delete"),
    [canvas.keys.ESCAPE] = load_key("keyboard_escape"),
    [canvas.keys.INSERT] = load_key("keyboard_insert"),
    [canvas.keys.HOME] = load_key("keyboard_home"),
    [canvas.keys.END] = load_key("keyboard_end"),
    [canvas.keys.PAGE_UP] = load_key("keyboard_page_up"),
    [canvas.keys.PAGE_DOWN] = load_key("keyboard_page_down"),

    -- Punctuation
    [canvas.keys.COMMA] = load_key("keyboard_comma"),
    [canvas.keys.PERIOD] = load_key("keyboard_period"),
    [canvas.keys.SLASH] = load_key("keyboard_slash_forward"),
    [canvas.keys.BACKSLASH] = load_key("keyboard_slash_back"),
    [canvas.keys.SEMICOLON] = load_key("keyboard_semicolon"),
    [canvas.keys.QUOTE] = load_key("keyboard_apostrophe"),
    [canvas.keys.BRACKET_LEFT] = load_key("keyboard_bracket_open"),
    [canvas.keys.BRACKET_RIGHT] = load_key("keyboard_bracket_close"),
    [canvas.keys.MINUS] = load_key("keyboard_minus"),
    [canvas.keys.EQUAL] = load_key("keyboard_equals"),
    [canvas.keys.BACKQUOTE] = load_key("keyboard_tilde"),
}

-- Mouse button sprite mappings (loaded upfront)
local mouse_sprites = {
    [controls_config.MOUSE_LEFT] = load_key("mouse_left"),
    [controls_config.MOUSE_RIGHT] = load_key("mouse_right"),
    -- MOUSE_MIDDLE has no sprite, will use text fallback
}

-- Gamepad sprite asset keys and files
local GAMEPAD_TILE = 16
local gamepad_assets = {
    face = "ui_gamepad_face",
    dpad = "ui_gamepad_dpad",
    shoulder = "ui_gamepad_shoulder",
    select_start = "ui_gamepad_select_start",
}

-- Load gamepad sprite assets upfront
canvas.assets.load_image(gamepad_assets.face, GAMEPAD_PATH .. "north_east_south_west.png")
canvas.assets.load_image(gamepad_assets.dpad, GAMEPAD_PATH .. "dpad_up_right_down_left.png")
canvas.assets.load_image(gamepad_assets.shoulder, GAMEPAD_PATH .. "lb_rb_lt_rt.png")
canvas.assets.load_image(gamepad_assets.select_start, GAMEPAD_PATH .. "select_start.png")

-- Gamepad button sprite mappings: canvas.buttons.* -> { asset, index }
-- Each gamepad file is a horizontal strip of 16x16 sprites
local button_sprites = {
    -- Face buttons (north_east_south_west.png): Y, B, A, X
    [canvas.buttons.NORTH] = { asset = gamepad_assets.face, index = 0 },
    [canvas.buttons.EAST] = { asset = gamepad_assets.face, index = 1 },
    [canvas.buttons.SOUTH] = { asset = gamepad_assets.face, index = 2 },
    [canvas.buttons.WEST] = { asset = gamepad_assets.face, index = 3 },

    -- D-pad (dpad_up_right_down_left.png)
    [canvas.buttons.DPAD_UP] = { asset = gamepad_assets.dpad, index = 0 },
    [canvas.buttons.DPAD_RIGHT] = { asset = gamepad_assets.dpad, index = 1 },
    [canvas.buttons.DPAD_DOWN] = { asset = gamepad_assets.dpad, index = 2 },
    [canvas.buttons.DPAD_LEFT] = { asset = gamepad_assets.dpad, index = 3 },

    -- Shoulder/trigger buttons (lb_rb_lt_rt.png)
    [canvas.buttons.LB] = { asset = gamepad_assets.shoulder, index = 0 },
    [canvas.buttons.RB] = { asset = gamepad_assets.shoulder, index = 1 },
    [canvas.buttons.LT] = { asset = gamepad_assets.shoulder, index = 2 },
    [canvas.buttons.RT] = { asset = gamepad_assets.shoulder, index = 3 },

    -- Select/Start (select_start.png)
    [canvas.buttons.SELECT] = { asset = gamepad_assets.select_start, index = 0 },
    [canvas.buttons.START] = { asset = gamepad_assets.select_start, index = 1 },
}

-- Keys with word labels that need larger scaling to be readable
local word_keys = {
    [canvas.keys.SPACE] = true,
    [canvas.keys.SHIFT] = true,
    [canvas.keys.CTRL] = true,
    [canvas.keys.ALT] = true,
    [canvas.keys.TAB] = true,
    [canvas.keys.ENTER] = true,
    [canvas.keys.BACKSPACE] = true,
    [canvas.keys.DELETE] = true,
    [canvas.keys.ESCAPE] = true,
    [canvas.keys.INSERT] = true,
    [canvas.keys.HOME] = true,
    [canvas.keys.END] = true,
    [canvas.keys.PAGE_UP] = true,
    [canvas.keys.PAGE_DOWN] = true,
    [canvas.keys.CAPS_LOCK] = true,
}

-- Text rendering settings for fallback
local FONT_SIZE = 9 * config.ui.SCALE
local TEXT_PADDING = 2 * config.ui.SCALE

--- Draw text fallback for unknown keys or keys without sprites
---@param text string Text to display
---@param x number Screen X position
---@param y number Screen Y position
---@param scale number|nil Scale multiplier (default 1)
local function draw_text_fallback(text, x, y, scale)
    scale = scale or 1
    local font_size = FONT_SIZE * scale
    local padding = TEXT_PADDING * scale

    canvas.set_font_family("menu_font")
    canvas.set_font_size(font_size)
    canvas.set_text_baseline("top")
    canvas.set_text_align("left")

    local text_width = canvas.get_text_width(text)
    local box_width = text_width + padding * 2
    local box_height = font_size + padding * 2

    canvas.set_color("#3a3a5c")
    canvas.fill_rect(x, y, box_width, box_height)

    canvas.set_color("#6a6a8c")
    canvas.draw_rect(x, y, box_width, box_height)

    canvas.set_color("#ffffff")
    canvas.draw_text(x + padding, y + padding, text, {})

    -- Restore default alignment to avoid affecting subsequent draw calls
    canvas.set_text_align("left")
    canvas.set_text_baseline("alphabetic")
end

--- Draw a keyboard key sprite
---@param code number|string Canvas key code or mouse button code
---@param x number Screen X position
---@param y number Screen Y position
---@param scale number|nil Scale multiplier (default 1, which draws at 64x64)
function controls.draw_key(code, x, y, scale)
    scale = scale or 1
    local draw_size = SPRITE_SIZE * scale

    -- Check for mouse button
    if controls_config.is_mouse_button(code) then
        local asset_key = mouse_sprites[code]
        if asset_key then
            canvas.draw_image(asset_key, x, y, draw_size, draw_size)
        else
            -- Mouse middle or unknown mouse button
            local name = controls_config.get_key_name(code)
            draw_text_fallback(name, x, y, scale)
        end
        return
    end

    -- Check for keyboard key
    local asset_key = key_sprites[code]
    if asset_key then
        canvas.draw_image(asset_key, x, y, draw_size, draw_size)
    else
        -- Unknown key, use text fallback
        local name = controls_config.get_key_name(code)
        draw_text_fallback(name, x, y, scale)
    end
end

--- Draw a gamepad button sprite
---@param code number Canvas button code
---@param x number Screen X position
---@param y number Screen Y position
---@param scale number|nil Scale multiplier (default uses config.ui.SCALE for 16px base)
function controls.draw_button(code, x, y, scale)
    scale = scale or config.ui.SCALE
    local draw_size = GAMEPAD_TILE * scale

    local sprite_info = button_sprites[code]
    if sprite_info then
        canvas.draw_image(
            sprite_info.asset,
            x, y, draw_size, draw_size,
            sprite_info.index * GAMEPAD_TILE, 0, GAMEPAD_TILE, GAMEPAD_TILE
        )
    else
        -- Unknown button, use text fallback
        local name = controls_config.get_button_name(code)
        draw_text_fallback(name, x, y, scale / config.ui.SCALE)
    end
end

--- Draw the control sprite for an action, auto-detecting the current input device
--- Note: Uses lazy require to avoid circular dependency with controls module at load time
---@param action_id string Action identifier (e.g., "jump", "attack")
---@param x number Screen X position
---@param y number Screen Y position
---@param scale number|nil Scale multiplier
function controls.draw_action(action_id, x, y, scale)
    local controls_module = require("controls")
    local scheme = controls_module.get_binding_scheme()
    local code = controls_module.get_binding(scheme, action_id)

    if not code then return end

    if scheme == "keyboard" then
        controls.draw_key(code, x, y, scale)
    else
        controls.draw_button(code, x, y, scale)
    end
end

--- Get the size of a keyboard key sprite
---@param code number|string Canvas key code or mouse button code
---@param scale number|nil Scale multiplier (default 1)
---@return number width Width in pixels
---@return number height Height in pixels
function controls.get_key_size(code, scale)
    scale = scale or 1

    -- Check if we have a sprite for this key
    if controls_config.is_mouse_button(code) then
        if mouse_sprites[code] then
            return SPRITE_SIZE * scale, SPRITE_SIZE * scale
        end
    elseif key_sprites[code] then
        return SPRITE_SIZE * scale, SPRITE_SIZE * scale
    end

    -- Unknown key, estimate from text
    local name = controls_config.get_key_name(code)
    canvas.set_font_family("menu_font")
    canvas.set_font_size(FONT_SIZE * scale)
    local text_width = canvas.get_text_width(name)
    local padding = TEXT_PADDING * scale
    return text_width + padding * 2, FONT_SIZE * scale + padding * 2
end

--- Get the size of a gamepad button sprite
---@param code number Canvas button code
---@param scale number|nil Scale multiplier (default uses config.ui.SCALE)
---@return number width Width in pixels
---@return number height Height in pixels
function controls.get_button_size(code, scale)
    scale = scale or config.ui.SCALE

    -- All gamepad buttons are 16x16 base tiles
    if button_sprites[code] then
        return GAMEPAD_TILE * scale, GAMEPAD_TILE * scale
    end

    -- Unknown button, estimate from text
    local name = controls_config.get_button_name(code)
    canvas.set_font_family("menu_font")
    canvas.set_font_size(FONT_SIZE * (scale / config.ui.SCALE))
    local text_width = canvas.get_text_width(name)
    local padding = TEXT_PADDING * (scale / config.ui.SCALE)
    return text_width + padding * 2, FONT_SIZE * (scale / config.ui.SCALE) + padding * 2
end

--- Check if a key code is a word-based key (needs larger scaling for readability)
---@param code number Canvas key code
---@return boolean is_word True if key has a word label
function controls.is_word_key(code)
    return word_keys[code] == true
end

--- Check if a button code is a shoulder/trigger button (needs larger scaling)
---@param code number Canvas button code
---@return boolean is_shoulder True if button is LB, RB, LT, or RT
function controls.is_shoulder_button(code)
    return code == canvas.buttons.LB or
           code == canvas.buttons.RB or
           code == canvas.buttons.LT or
           code == canvas.buttons.RT
end

return controls
