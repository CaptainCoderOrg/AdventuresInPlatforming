--- Credits screen with scrolling attributions and animated enemy decorations
--- Sequence: fade to black -> fade in content -> title hold -> scroll to typewriter ->
--- typewriter -> hold -> scroll credits -> fade out
local canvas = require("canvas")
local config = require("config")
local controls = require("controls")
local Animation = require("Animation")
local sprites = require("sprites")
local audio = require("audio")
local music = require("audio/music")

local credits_screen = {}

local STATE = {
    HIDDEN = "hidden",
    FADE_TO_BLACK = "fade_to_black",
    FADE_IN_CONTENT = "fade_in_content",
    HOLD_TITLE = "hold_title",
    SCROLL_TO_TYPEWRITER = "scroll_to_typewriter",
    TYPEWRITER = "typewriter",
    HOLD_TYPEWRITER = "hold_typewriter",
    SCROLL_CREDITS = "scroll_credits",
    FADING_OUT = "fading_out",
}

-- Timing (seconds)
local FADE_TO_BLACK_DURATION = 1
local FADE_IN_CONTENT_DURATION = 1
local FADE_OUT_DURATION = 1
local HOLD_TITLE_DURATION = 1
local SCROLL_TO_TW_SPEED = 15    -- 1x px/s
local SCROLL_TO_TW_DISTANCE = 30 -- 1x px
local TW_CHAR_DELAY = 0.05       -- seconds per character
local HOLD_TW_DURATION = 1
local SCROLL_SPEED = 14           -- 1x px/s

-- Content layout (1x scale coordinates, content Y=0 at top)
local SUBTITLE_LINE_1 = "Made in 37 days for the"
local SUBTITLE_LINE_2 = "Solo Development Marathon Jam #5"
local SUBTITLE_Y_1 = 22
local SUBTITLE_Y_2 = 34
local TYPEWRITER_Y = 56
local TYPEWRITER_TEXT = "Thank you for playing!"

-- Scroll math: screen_y = content_y - scroll_offset
-- Title at content Y=0, screen center at 108 (216/2) => initial offset = -108
local INITIAL_SCROLL = -108
-- Scroll until all content (last at Y=910) is off the top of the screen
local MAX_SCROLL = 940

-- Decoration sprite X positions (1x scale, screen is 384px wide)
local DECO_LEFT_X = 50
local DECO_RIGHT_X = 310

-- How long to display a looping animation before cycling (seconds)
local LOOP_CYCLE_SECS = 2.5

-- Skip hint icon sizes (drawn inside scaled context at 1x coordinates)
local SKIP_ICON_SIZE = 8
local SKIP_KEY_SCALE = 0.125       -- 64px * 0.125 = 8px
local SKIP_BUTTON_SCALE = 0.5      -- 16px * 0.5 = 8px
local SKIP_ICON_SPACING = 4
local SKIP_MARGIN_RIGHT = 10
local SKIP_MARGIN_BOTTOM = 10

-- Sections spaced so title + typewriter are alone on screen before scrolling begins.
-- After SCROLL_TO_TYPEWRITER, visible range top is ~138 at 1x, so Y>=170 is off-screen.
local CREDITS_DATA = {
    { type = "header", y = 170, text = "--- Game Design & Programming ---" },
    { type = "name", y = 190, text = "TheCaptainCoder" },

    { type = "header", y = 260, text = "--- Art ---" },
    { type = "name", y = 280, text = "\"Another Metroidvania Asset Pack\" by O_LOBSTER" },
    { type = "name", y = 294, text = "\"Viking Shieldmaiden\" by DezrasDragons" },
    { type = "name", y = 308, text = "\"Skeleton and Friends\" by patvanmackelberg" },
    { type = "name", y = 322, text = "\"Roguelike/RPG Items\" by Joe Williamson" },
    { type = "name", y = 336, text = "\"Golden UI\"" },
    { type = "name", y = 350, text = "\"Golden UI - Bigger Edition\"" },

    { type = "header", y = 420, text = "--- Audio & Sound Effects ---" },
    { type = "name", y = 440, text = "\"Fantasy Sound Effects Library\"" },
    { type = "name", y = 454, text = "\"Campfire\" by cagankaya" },
    { type = "name", y = 468, text = "\"Key Pickup\"" },
    { type = "name", y = 482, text = "\"Watermelon Splatter\" by duckduckpony" },
    { type = "name", y = 496, text = "\"Sledge Hammer on Mulch\" by FST180081" },
    { type = "name", y = 510, text = "\"Spike Trap\" by Deathscyp" },
    { type = "name", y = 524, text = "\"Stone Slab Impact\" by Scottrex05" },

    { type = "header", y = 600, text = "--- Special Thanks ---" },
    { type = "name", y = 624, text = "iheartfunnyboys" },
    { type = "name", y = 638, text = "Just Covino" },
    { type = "name", y = 652, text = "MooNiZZ" },
    { type = "name", y = 666, text = "KiltedNinja" },
    { type = "name", y = 680, text = "MadChirpy" },
    { type = "name", y = 694, text = "IrishJohn" },
    { type = "name", y = 708, text = "Don Stove" },
    { type = "name", y = 722, text = "Jam" },
    { type = "name", y = 736, text = "The Working Man" },

    { type = "name", y = 790, text = "And a huge thanks to" },
    { type = "dedication", y = 812, text = "The Wonderful Ravenhale" },
    { type = "name", y = 834, text = "for putting up with my obsessions" },

    { type = "name", y = 910, text = "Thank you for playing!" },
}

-- Cached text widths (populated in show() to avoid per-frame get_text_metrics calls)
local cached_title_width = 0
local cached_sub1_width = 0
local cached_sub2_width = 0
local cached_tw_width = 0
local cached_skip_width = 0

local state = STATE.HIDDEN
local fade_progress = 0
local phase_timer = 0
local scroll_offset = INITIAL_SCROLL
local typewriter_index = 0
local typewriter_timer = 0
local on_close_callback = nil

-- Decoration sprites: animated characters flanking the credits
-- Each entry: { y, side, anims={Animation...}, durations={number...}, current, timer }
local deco_sprites = {}

--- Create a decoration sprite entry with multiple cycling animations
---@param y number Content Y position
---@param side string "left" or "right"
---@param flipped number 1 (facing right) or -1 (facing left)
---@param anim_specs table Array of {asset, frames, w, h, ms, row?, loop?}
---@return table Decoration sprite entry
local function create_deco(y, side, flipped, anim_specs)
    local anims = {}
    local durations = {}
    for i, spec in ipairs(anim_specs) do
        local def = Animation.create_definition(spec.asset, spec.frames, {
            ms_per_frame = spec.ms,
            width = spec.w,
            height = spec.h,
            row = spec.row,
            loop = spec.loop or false,
        })
        anims[i] = Animation.new(def, { flipped = flipped })
        local natural_secs = spec.frames * spec.ms / 1000
        if spec.loop then
            durations[i] = math.max(natural_secs * 2, LOOP_CYCLE_SECS)
        else
            durations[i] = math.max(natural_secs, 0.5)
        end
    end
    return {
        y = y,
        side = side,
        anims = anims,
        durations = durations,
        current = 1,
        timer = 0,
    }
end

--- Initialize decoration sprite animations (call once at startup)
function credits_screen.init()
    local e = sprites.enemies
    local p = sprites.player
    local n = sprites.npcs

    deco_sprites = {
        -- Y=170: Game Design header
        create_deco(170, "left", 1, {
            { asset = e.gnomo.sheet, frames = 5, w = 16, h = 16, ms = 150, row = 1, loop = true },
            { asset = e.gnomo.sheet, frames = 6, w = 16, h = 16, ms = 100, row = 3, loop = true },
            { asset = e.gnomo.sheet, frames = 8, w = 16, h = 16, ms = 60, row = 0 },
        }),
        create_deco(170, "right", -1, {
            { asset = e.shieldmaiden.sheet, frames = 4, w = 40, h = 29, ms = 150, row = 2, loop = true },
            { asset = e.shieldmaiden.sheet, frames = 6, w = 40, h = 29, ms = 100, row = 6, loop = true },
            { asset = e.shieldmaiden.sheet, frames = 5, w = 40, h = 29, ms = 60, row = 0 },
            { asset = e.shieldmaiden.sheet, frames = 3, w = 40, h = 29, ms = 100, row = 1 },
        }),

        -- Y=260: Art header
        create_deco(260, "left", 1, {
            { asset = e.zombie.idle, frames = 6, w = 16, h = 16, ms = 200, loop = true },
            { asset = e.zombie.run, frames = 6, w = 16, h = 16, ms = 150, loop = true },
        }),
        create_deco(260, "right", -1, {
            { asset = e.ghost_painting.static, frames = 1, w = 16, h = 24, ms = 80 },
            { asset = e.ghost_painting.fly, frames = 10, w = 16, h = 24, ms = 80, loop = true },
        }),

        -- Y=310: Among art credits
        create_deco(310, "left", 1, {
            { asset = e.ratto.idle, frames = 6, w = 16, h = 8, ms = 200, loop = true },
            { asset = e.ratto.run, frames = 4, w = 16, h = 8, ms = 80, loop = true },
        }),
        create_deco(310, "right", -1, {
            { asset = e.spikeslug.run, frames = 4, w = 16, h = 16, ms = 200, loop = true },
            { asset = e.spikeslug.defense, frames = 6, w = 16, h = 16, ms = 200 },
            { asset = e.spikeslug.stop_defend, frames = 6, w = 16, h = 16, ms = 200 },
        }),

        -- Y=350: Bottom of art section
        create_deco(350, "left", 1, {
            { asset = e.blue_slime.idle, frames = 5, w = 16, h = 16, ms = 150, loop = true },
            { asset = e.blue_slime.jump, frames = 4, w = 16, h = 16, ms = 300 },
        }),
        create_deco(350, "right", -1, {
            { asset = e.red_slime.idle, frames = 5, w = 16, h = 16, ms = 150, loop = true },
            { asset = e.red_slime.jump, frames = 4, w = 16, h = 16, ms = 225 },
        }),

        -- Y=420: Audio header
        create_deco(420, "left", 1, {
            { asset = e.bat_eye.idle, frames = 6, w = 16, h = 16, ms = 80, loop = true },
            { asset = e.bat_eye.alert, frames = 4, w = 16, h = 16, ms = 160 },
            { asset = e.bat_eye.attack, frames = 3, w = 16, h = 16, ms = 80, loop = true },
        }),
        create_deco(420, "right", -1, {
            { asset = e.flaming_skull.float, frames = 8, w = 18, h = 26, ms = 100, loop = true },
        }),

        -- Y=480: Among audio credits
        create_deco(480, "left", 1, {
            { asset = e.worm.run, frames = 5, w = 16, h = 8, ms = 200, loop = true },
        }),
        create_deco(480, "right", -1, {
            { asset = e.magician_purple.sheet, frames = 6, w = 16, h = 16, ms = 120, row = 1, loop = true },
            { asset = e.magician_purple.sheet, frames = 4, w = 16, h = 16, ms = 100, row = 2, loop = true },
            { asset = e.magician_purple.sheet, frames = 11, w = 16, h = 16, ms = 55, row = 0 },
        }),

        -- Y=525: Bottom of audio section
        create_deco(525, "left", 1, {
            { asset = e.magician.sheet, frames = 6, w = 16, h = 16, ms = 120, row = 1, loop = true },
            { asset = e.magician.sheet, frames = 4, w = 16, h = 16, ms = 100, row = 2, loop = true },
            { asset = e.magician.sheet, frames = 11, w = 16, h = 16, ms = 80, row = 0 },
        }),
        create_deco(525, "right", -1, {
            { asset = e.magician_blue.sheet, frames = 6, w = 16, h = 16, ms = 120, row = 1, loop = true },
            { asset = e.magician_blue.sheet, frames = 4, w = 16, h = 16, ms = 100, row = 2, loop = true },
            { asset = e.magician_blue.sheet, frames = 11, w = 16, h = 16, ms = 120, row = 0 },
        }),

        -- Y=600: Special Thanks header
        create_deco(600, "left", 1, {
            { asset = e.guardian.idle, frames = 6, w = 48, h = 32, ms = 150, loop = true },
            { asset = e.guardian.run, frames = 4, w = 48, h = 32, ms = 100, loop = true },
            { asset = e.guardian.attack, frames = 8, w = 48, h = 32, ms = 100 },
            { asset = e.guardian.alert, frames = 4, w = 48, h = 32, ms = 100 },
            { asset = e.guardian.jump, frames = 2, w = 48, h = 32, ms = 100 },
            { asset = e.guardian.land, frames = 7, w = 48, h = 32, ms = 100 },
        }),
        create_deco(600, "right", -1, {
            { asset = n.witch_merchant_idle, frames = 10, w = 32, h = 32, ms = 100, loop = true },
        }),

        -- Y=700: Among Special Thanks
        create_deco(700, "left", 1, {
            { asset = p.idle, frames = 6, w = 16, h = 16, ms = 240, loop = true },
            { asset = p.run, frames = 8, w = 16, h = 16, ms = 80, loop = true },
            { asset = p.jump_up, frames = 3, w = 16, h = 16, ms = 80 },
            { asset = p.fall, frames = 3, w = 16, h = 16, ms = 80, loop = true },
            { asset = p.dash, frames = 4, w = 16, h = 16, ms = 80 },
        }),
        create_deco(700, "right", -1, {
            { asset = n.adept_reading, frames = 6, w = 16, h = 16, ms = 200, loop = true },
        }),

        -- Y=800: Ravenhale section
        create_deco(800, "left", 1, {
            { asset = e.gnomo_boss.green, frames = 5, w = 16, h = 16, ms = 150, row = 1, loop = true },
            { asset = e.gnomo_boss.green, frames = 6, w = 16, h = 16, ms = 100, row = 3, loop = true },
            { asset = e.gnomo_boss.green, frames = 8, w = 16, h = 16, ms = 60, row = 0 },
        }),
        create_deco(800, "right", -1, {
            { asset = e.gnomo_boss.red, frames = 5, w = 16, h = 16, ms = 150, row = 1, loop = true },
            { asset = e.gnomo_boss.red, frames = 6, w = 16, h = 16, ms = 100, row = 3, loop = true },
            { asset = e.gnomo_boss.red, frames = 8, w = 16, h = 16, ms = 60, row = 0 },
        }),
    }
end

--- Show the credits screen (fades to black first, then reveals content)
function credits_screen.show()
    if state ~= STATE.HIDDEN then return end
    state = STATE.FADE_TO_BLACK
    fade_progress = 0
    phase_timer = 0
    scroll_offset = INITIAL_SCROLL
    typewriter_index = 0
    typewriter_timer = 0

    -- Reset all decoration sprite animations and cycling state
    for _, deco in ipairs(deco_sprites) do
        deco.current = 1
        deco.timer = 0
        for _, anim in ipairs(deco.anims) do
            anim:reset()
        end
    end

    -- Fade out whatever music is currently playing over the fade-to-black duration
    music.fade_out(FADE_TO_BLACK_DURATION)

    -- Cache text widths once (avoids per-frame get_text_metrics)
    canvas.set_font_family("menu_font")
    canvas.set_font_size(16)
    cached_title_width = canvas.get_text_metrics("KNIGHTMARE").width
    canvas.set_font_size(6)
    cached_sub1_width = canvas.get_text_metrics(SUBTITLE_LINE_1).width
    cached_sub2_width = canvas.get_text_metrics(SUBTITLE_LINE_2).width
    canvas.set_font_size(7)
    cached_tw_width = canvas.get_text_metrics(TYPEWRITER_TEXT).width
    cached_skip_width = canvas.get_text_metrics("Skip").width
    for _, entry in ipairs(CREDITS_DATA) do
        if entry.type == "header" or entry.type == "dedication" then
            canvas.set_font_size(8)
            entry.cached_width = canvas.get_text_metrics(entry.text).width
        else
            canvas.set_font_size(7)
            entry.cached_width = canvas.get_text_metrics(entry.text).width
        end
    end
end

--- Hide the credits screen with fade-out
function credits_screen.hide()
    if state ~= STATE.HIDDEN and state ~= STATE.FADING_OUT then
        state = STATE.FADING_OUT
        fade_progress = 0
        -- Fade out credits music over the visual fade-out duration
        music.fade_out(FADE_OUT_DURATION)
    end
end

--- Check if credits screen is blocking game input
---@return boolean
function credits_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Set callback for when credits screen closes
---@param fn function Callback function
function credits_screen.set_on_close(fn)
    on_close_callback = fn
end

--- Process credits screen input
function credits_screen.input()
    if state ~= STATE.HIDDEN and state ~= STATE.FADE_TO_BLACK
       and state ~= STATE.FADE_IN_CONTENT and state ~= STATE.FADING_OUT then
        if controls.menu_back_pressed() then
            credits_screen.hide()
        end
    end
end

--- Update state machine, scroll, typewriter, and decoration animations
---@param dt number Delta time in seconds
function credits_screen.update(dt)
    if state == STATE.HIDDEN then return end

    -- Advance decoration sprite animations and handle cycling
    for _, deco in ipairs(deco_sprites) do
        deco.anims[deco.current]:play(dt)
        deco.timer = deco.timer + dt
        if deco.timer >= deco.durations[deco.current] then
            deco.current = deco.current % #deco.anims + 1
            deco.anims[deco.current]:reset()
            deco.timer = 0
        end
    end

    if state == STATE.FADE_TO_BLACK then
        fade_progress = fade_progress + dt / FADE_TO_BLACK_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.FADE_IN_CONTENT
            -- Start credits music (play cancels fade_out and crossfades in)
            audio.play_music(audio.credits)
        end

    elseif state == STATE.FADE_IN_CONTENT then
        fade_progress = fade_progress + dt / FADE_IN_CONTENT_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HOLD_TITLE
            phase_timer = 0
        end

    elseif state == STATE.HOLD_TITLE then
        phase_timer = phase_timer + dt
        if phase_timer >= HOLD_TITLE_DURATION then
            state = STATE.SCROLL_TO_TYPEWRITER
        end

    elseif state == STATE.SCROLL_TO_TYPEWRITER then
        scroll_offset = scroll_offset + SCROLL_TO_TW_SPEED * dt
        if scroll_offset >= INITIAL_SCROLL + SCROLL_TO_TW_DISTANCE then
            scroll_offset = INITIAL_SCROLL + SCROLL_TO_TW_DISTANCE
            state = STATE.TYPEWRITER
            typewriter_timer = 0
        end

    elseif state == STATE.TYPEWRITER then
        typewriter_timer = typewriter_timer + dt
        typewriter_index = math.min(
            math.floor(typewriter_timer / TW_CHAR_DELAY),
            #TYPEWRITER_TEXT
        )
        if typewriter_index >= #TYPEWRITER_TEXT then
            state = STATE.HOLD_TYPEWRITER
            phase_timer = 0
        end

    elseif state == STATE.HOLD_TYPEWRITER then
        phase_timer = phase_timer + dt
        if phase_timer >= HOLD_TW_DURATION then
            state = STATE.SCROLL_CREDITS
        end

    elseif state == STATE.SCROLL_CREDITS then
        scroll_offset = scroll_offset + SCROLL_SPEED * dt
        if scroll_offset >= MAX_SCROLL then
            scroll_offset = MAX_SCROLL
            state = STATE.FADING_OUT
            fade_progress = 0
            music.fade_out(FADE_OUT_DURATION)
        end

    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
            if on_close_callback then
                on_close_callback()
            end
        end
    end
end

--- Draw the credits screen
function credits_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Two-phase fade: black background fades in first, then content fades in on top
    local bg_alpha = 1
    local content_alpha = 1
    if state == STATE.FADE_TO_BLACK then
        bg_alpha = fade_progress
        content_alpha = 0
    elseif state == STATE.FADE_IN_CONTENT then
        bg_alpha = 1
        content_alpha = fade_progress
    elseif state == STATE.FADING_OUT then
        bg_alpha = 1
        content_alpha = 1 - fade_progress
    end

    -- Black background
    canvas.set_global_alpha(bg_alpha)
    canvas.set_fill_style("#000000")
    canvas.fill_rect(0, 0, screen_w, screen_h)

    -- Skip content drawing during fade-to-black phase
    if content_alpha <= 0 then
        canvas.set_global_alpha(1)
        return
    end

    canvas.set_global_alpha(content_alpha)

    -- Draw text in scaled context
    canvas.save()
    canvas.scale(scale, scale)

    local center_x = screen_w / (2 * scale)
    local h_1x = screen_h / scale

    canvas.set_font_family("menu_font")
    canvas.set_text_baseline("middle")

    -- Title "KNIGHTMARE" (content Y=0)
    local title_sy = 0 - scroll_offset
    canvas.set_font_size(16)
    local title_x = center_x - cached_title_width / 2

    canvas.set_color("#000000")
    canvas.draw_text(title_x + 1, title_sy + 1, "KNIGHTMARE")
    canvas.set_color("#FFFF00")
    canvas.draw_text(title_x, title_sy, "KNIGHTMARE")

    -- Subtitle lines
    canvas.set_font_size(6)
    canvas.set_color("#AAAAAA")
    canvas.draw_text(center_x - cached_sub1_width / 2, SUBTITLE_Y_1 - scroll_offset, SUBTITLE_LINE_1)
    canvas.draw_text(center_x - cached_sub2_width / 2, SUBTITLE_Y_2 - scroll_offset, SUBTITLE_LINE_2)

    -- Typewriter text (visible once typing starts, persists through all later phases)
    if typewriter_index > 0 then
        canvas.set_font_size(7)
        local tw_x = center_x - cached_tw_width / 2
        local tw_sy = TYPEWRITER_Y - scroll_offset
        -- Draw full string once typewriter finishes to avoid per-frame string.sub
        if typewriter_index >= #TYPEWRITER_TEXT then
            canvas.set_color("#FFFFFF")
            canvas.draw_text(tw_x, tw_sy, TYPEWRITER_TEXT)
        else
            canvas.set_color("#FFFFFF")
            canvas.draw_text(tw_x, tw_sy, string.sub(TYPEWRITER_TEXT, 1, typewriter_index))
        end
    end

    -- Draw credits entries (using cached widths from show())
    for _, entry in ipairs(CREDITS_DATA) do
        local sy = entry.y - scroll_offset

        -- Cull off-screen entries
        if sy > -20 and sy < h_1x + 20 then
            if entry.type == "header" then
                canvas.set_font_size(8)
                canvas.set_color("#FFFF00")
                canvas.draw_text(center_x - entry.cached_width / 2, sy, entry.text)

            elseif entry.type == "dedication" then
                canvas.set_font_size(8)
                canvas.set_color("#FFFF00")
                canvas.draw_text(center_x - entry.cached_width / 2, sy, entry.text)

            elseif entry.type == "name" then
                canvas.set_font_size(7)
                canvas.set_color("#FFFFFF")
                canvas.draw_text(center_x - entry.cached_width / 2, sy, entry.text)
            end
        end
    end

    -- Skip hint in bottom-right (only during skippable phases)
    if state == STATE.SCROLL_CREDITS then
        canvas.set_font_size(7)
        canvas.set_text_baseline("middle")
        canvas.set_text_align("right")
        canvas.set_color("#666666")

        local skip_text = "Skip"
        local skip_x = screen_w / scale - SKIP_MARGIN_RIGHT
        local skip_y = screen_h / scale - SKIP_MARGIN_BOTTOM

        canvas.draw_text(skip_x, skip_y, skip_text)

        local icon_x = skip_x - cached_skip_width - SKIP_ICON_SPACING - SKIP_ICON_SIZE
        local icon_y = skip_y - SKIP_ICON_SIZE / 2
        local mode = controls.get_last_input_device()
        if mode == "gamepad" then
            sprites.controls.draw_button(canvas.buttons.EAST, icon_x, icon_y, SKIP_BUTTON_SCALE)
        else
            sprites.controls.draw_key(canvas.keys.ESCAPE, icon_x, icon_y, SKIP_KEY_SCALE)
        end
        canvas.set_text_align("left")
    end

    canvas.restore()

    -- Draw decoration sprites outside scaled context (Animation:draw handles its own scaling)
    for _, deco in ipairs(deco_sprites) do
        local sy = deco.y - scroll_offset
        if sy > -50 and sy < h_1x + 50 then
            local x = deco.side == "left" and DECO_LEFT_X or DECO_RIGHT_X
            deco.anims[deco.current]:draw(x * scale, sy * scale)
        end
    end

    canvas.set_global_alpha(1)
end

return credits_screen
