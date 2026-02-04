--- Boss Health Bar: Sprite-based health display for boss encounters.
--- Shows at top-center of screen with intro animation when a boss fight starts.
--- Configure with set_coordinator() to support different boss types.
local audio = require("audio")
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")

-- Lazy-loaded to avoid circular dependency
local rest_screen = nil

local boss_health_bar = {}

-- Active coordinator (set via set_coordinator)
local coordinator = nil

-- Sprite dimensions (unscaled pixels)
local SPRITE_WIDTH = 160
local SPRITE_HEIGHT = 16
local TOP_MARGIN = 1

-- Health bar rectangle (relative to sprite top-left)
local BAR_X_OFFSET = 6
local BAR_Y_OFFSET = 7
local BAR_WIDTH = 148
local BAR_HEIGHT = 3

-- Animation constants
local FADE_SPEED = 3           -- Bar fade in/out speed (alpha per second)
local HEALTH_LERP_SPEED = 3    -- Drain lerp speed (higher = faster ease-out)
local FILL_UP_SPEED = 1.5      -- Health fills up over ~0.7s (percentage per second)
local TEXT_DISPLAY_TIME = 2.5  -- How long title shows (seconds)
local TEXT_FADE_SPEED = 2      -- Title fade out speed (alpha per second)

-- Widget state
local alpha = 0                -- Bar fade (0-1)
local text_alpha = 0           -- Title/subtitle fade (0-1)
local displayed_health = 0     -- Smoothed health percentage (starts at 0 for fill-up)
local target_health = 0        -- Actual health percentage
local text_timer = 0           -- Countdown for text display
local intro_complete = false   -- Whether fill-up animation finished
local was_active = false       -- Track active state for intro triggers

-- Colors
local BAR_COLOR = "#FF0000"
local BAR_DRAIN_COLOR = "#FF6666"  -- Lighter red for health drain animation

-- Defeated state phases
local DEFEATED_PHASE_NONE = 0
local DEFEATED_PHASE_TITLE_FADE_IN = 1
local DEFEATED_PHASE_TITLE_HOLD = 2
local DEFEATED_PHASE_STAMP = 3
local DEFEATED_PHASE_HOLD = 4
local DEFEATED_PHASE_FADE_OUT = 5

-- Defeated animation constants
local TITLE_FADE_IN_SPEED = 2       -- Title fades in over 0.5s
local TITLE_HOLD_DURATION = 1       -- Hold title for 1s before stamp
local STAMP_DURATION = 0.3          -- Stamp animation duration
local STAMP_START_SCALE = 3         -- Stamp starts 3x size
local STAMP_START_Y_OFFSET = -50    -- Stamp starts 50 units above (in scaled pixels)
local TITLE_DIM_ALPHA = 0.3         -- Title dims to 30% during stamp
local HOLD_DURATION = 2             -- Hold before fade out
local DEFEATED_FADE_SPEED = 1.5     -- Fade out speed

-- Defeated state variables
local defeated_mode = false
local defeated_phase = DEFEATED_PHASE_NONE
local defeated_timer = 0
local title_alpha = 0               -- Title/subtitle alpha (separate from defeated text)
local defeated_alpha = 0            -- "Defeated!" text alpha
local stamp_progress = 0            -- 0 to 1 for stamp animation

--- Draws the boss title and subtitle centered on screen.
--- Used by both normal health bar display and defeated mode.
---@param scale number UI scale factor
---@param center_x number Screen center X
---@param center_y number Screen center Y
local function draw_boss_title(scale, center_x, center_y)
    local boss_name = coordinator.get_boss_name()
    local boss_subtitle = coordinator.get_boss_subtitle()

    canvas.set_font_family("menu_font")
    canvas.set_text_align("center")

    -- Title: orange/gold with black outline
    local title_y = center_y - 10 * scale
    canvas.set_font_size(16 * scale)
    canvas.set_line_width(4 * scale)
    canvas.set_color("#000000")
    canvas.stroke_text(center_x, title_y, boss_name)
    canvas.set_color("#FFB833")
    canvas.draw_text(center_x, title_y, boss_name)

    -- Subtitle: white with black outline
    local subtitle_y = center_y + 14 * scale
    canvas.set_font_size(10 * scale)
    canvas.set_line_width(3 * scale)
    canvas.set_color("#000000")
    canvas.stroke_text(center_x, subtitle_y, boss_subtitle)
    canvas.set_color("#FFFFFF")
    canvas.draw_text(center_x, subtitle_y, boss_subtitle)
end

--- Set the active boss coordinator.
--- Call this when entering a level with a boss, or when a boss encounter starts.
---@param new_coordinator table Coordinator with is_active, get_health_percent, get_boss_name, get_boss_subtitle
function boss_health_bar.set_coordinator(new_coordinator)
    coordinator = new_coordinator
end

--- Get the current coordinator (for cleanup checks).
---@return table|nil Current coordinator or nil
function boss_health_bar.get_coordinator()
    return coordinator
end

--- Show the defeated state with stamp animation.
--- Called when the boss is defeated to display "Defeated!" stamping down over the title.
function boss_health_bar.show_defeated()
    defeated_mode = true
    defeated_phase = DEFEATED_PHASE_TITLE_FADE_IN
    defeated_timer = 0
    title_alpha = 0
    defeated_alpha = 0
    stamp_progress = 0
end

--- Check if the defeated animation is complete.
---@return boolean True if defeated animation finished (text faded out)
function boss_health_bar.is_defeated_complete()
    return defeated_mode and defeated_phase == DEFEATED_PHASE_FADE_OUT and defeated_alpha <= 0
end

--- Update the boss health bar state.
---@param dt number Delta time in seconds
function boss_health_bar.update(dt)
    -- Handle defeated mode separately (no coordinator needed after defeat)
    if defeated_mode then
        if defeated_phase == DEFEATED_PHASE_TITLE_FADE_IN then
            -- Phase 1: Title/subtitle fades in
            title_alpha = math.min(1, title_alpha + TITLE_FADE_IN_SPEED * dt)
            if title_alpha >= 1 then
                defeated_phase = DEFEATED_PHASE_TITLE_HOLD
                defeated_timer = 0
            end
        elseif defeated_phase == DEFEATED_PHASE_TITLE_HOLD then
            -- Phase 2: Hold title visible before stamp
            defeated_timer = defeated_timer + dt
            if defeated_timer >= TITLE_HOLD_DURATION then
                defeated_phase = DEFEATED_PHASE_STAMP
                defeated_timer = 0
                audio.play_defeated_stamp()
            end
        elseif defeated_phase == DEFEATED_PHASE_STAMP then
            -- Phase 3: "Defeated!" stamps down while title dims to 30%
            defeated_timer = defeated_timer + dt
            stamp_progress = math.min(1, defeated_timer / STAMP_DURATION)
            defeated_alpha = stamp_progress  -- Fade in as it stamps
            -- Lerp title from 1.0 to TITLE_DIM_ALPHA
            title_alpha = 1 - (1 - TITLE_DIM_ALPHA) * stamp_progress
            if stamp_progress >= 1 then
                defeated_phase = DEFEATED_PHASE_HOLD
                defeated_timer = 0
            end
        elseif defeated_phase == DEFEATED_PHASE_HOLD then
            -- Phase 4: Hold for a moment
            defeated_timer = defeated_timer + dt
            if defeated_timer >= HOLD_DURATION then
                defeated_phase = DEFEATED_PHASE_FADE_OUT
            end
        elseif defeated_phase == DEFEATED_PHASE_FADE_OUT then
            -- Phase 5: Everything fades out (title at 30% disappears first)
            title_alpha = math.max(0, title_alpha - DEFEATED_FADE_SPEED * dt)
            defeated_alpha = math.max(0, defeated_alpha - DEFEATED_FADE_SPEED * dt)
        end
        return
    end

    if not coordinator then
        -- No coordinator set, fade out if visible
        if alpha > 0 then
            alpha = math.max(0, alpha - FADE_SPEED * dt)
        end
        return
    end

    local is_active = coordinator.is_active()

    -- Fade bar in/out
    if is_active then
        alpha = math.min(1, alpha + FADE_SPEED * dt)
    else
        alpha = math.max(0, alpha - FADE_SPEED * dt)
    end

    -- Reset to intro state when encounter starts
    if is_active and not was_active then
        displayed_health = 0
        intro_complete = false
        text_timer = TEXT_DISPLAY_TIME
        text_alpha = 1
    end
    was_active = is_active

    if not is_active then return end

    -- Get actual health percentage
    target_health = coordinator.get_health_percent()

    -- Intro phase: fill health bar from 0 to full
    if not intro_complete then
        displayed_health = displayed_health + FILL_UP_SPEED * dt
        if displayed_health >= 1 then
            displayed_health = 1
            intro_complete = true
        end
    else
        -- Normal phase: lerp displayed health toward actual (ease-out effect)
        local diff = target_health - displayed_health
        displayed_health = displayed_health + diff * math.min(1, HEALTH_LERP_SPEED * dt)
    end

    -- Text fade timer
    if text_timer > 0 then
        text_timer = text_timer - dt
    elseif text_alpha > 0 then
        text_alpha = math.max(0, text_alpha - TEXT_FADE_SPEED * dt)
    end
end

--- Draw the "Defeated!" stamp text with scale and position animation.
---@param scale number UI scale factor
---@param center_x number Screen center X
---@param center_y number Screen center Y
local function draw_defeated_stamp(scale, center_x, center_y)
    if defeated_alpha <= 0 then return end

    -- Calculate stamp animation: starts large and above, ends at normal size on top of title
    -- Use ease-out for the stamp effect (fast at start, slows at end)
    local ease_t = 1 - (1 - stamp_progress) * (1 - stamp_progress)
    local current_scale = STAMP_START_SCALE + (1 - STAMP_START_SCALE) * ease_t
    local y_offset = STAMP_START_Y_OFFSET * (1 - ease_t) * scale

    -- Final position is centered on the title/subtitle area (center_y)
    local defeated_y = center_y + y_offset
    local font_size = 32 * scale * current_scale  -- 2x larger base size

    canvas.set_global_alpha(defeated_alpha)
    canvas.set_font_family("menu_font")
    canvas.set_text_align("center")
    canvas.set_font_size(font_size)
    canvas.set_line_width(6 * scale * current_scale)  -- Thicker outline for larger text
    canvas.set_color("#000000")
    canvas.stroke_text(center_x, defeated_y, "Defeated!")
    canvas.set_color("#FF0000")
    canvas.draw_text(center_x, defeated_y, "Defeated!")
end

--- Draw the boss health bar.
function boss_health_bar.draw()
    -- Defeated mode: title fades in, "Defeated!" stamps down, then all fades out
    if defeated_mode then
        if title_alpha <= 0 and defeated_alpha <= 0 then return end
        if not coordinator then return end
        -- Don't draw over pause/rest screen
        rest_screen = rest_screen or require("ui/rest_screen")
        if rest_screen.is_active() then return end

        local scale = config.ui.SCALE
        local center_x = config.ui.canvas_width / 2
        local center_y = config.ui.canvas_height / 2

        canvas.save()

        -- Draw title/subtitle at its own alpha
        if title_alpha > 0 then
            canvas.set_global_alpha(title_alpha)
            draw_boss_title(scale, center_x, center_y)
        end

        -- Draw "Defeated!" stamp (handles its own alpha)
        draw_defeated_stamp(scale, center_x, center_y)

        canvas.restore()
        return
    end

    if alpha <= 0 or not coordinator then return end

    local scale = config.ui.SCALE
    local screen_width = config.ui.canvas_width

    -- Calculate scaled dimensions
    local sprite_w = SPRITE_WIDTH * scale
    local sprite_h = SPRITE_HEIGHT * scale
    local top_margin = TOP_MARGIN * scale

    -- Center horizontally
    local sprite_x = math.floor((screen_width - sprite_w) / 2)
    local sprite_y = top_margin

    canvas.save()
    canvas.set_global_alpha(alpha)

    -- Calculate health bar position (relative to sprite)
    local bar_x = sprite_x + BAR_X_OFFSET * scale
    local bar_y = sprite_y + BAR_Y_OFFSET * scale
    local bar_w = BAR_WIDTH * scale
    local bar_h = BAR_HEIGHT * scale

    -- Calculate fill widths
    local target_fill = target_health
    if not intro_complete then
        target_fill = displayed_health  -- During intro, target = displayed
    end
    local target_width = bar_w * target_fill
    local displayed_width = bar_w * displayed_health

    -- Draw target health at full opacity (under sprite)
    if target_width > 0 then
        canvas.set_color(BAR_COLOR)
        canvas.fill_rect(bar_x, bar_y, target_width, bar_h)
    end

    -- Draw drain portion in lighter color (when displayed > target)
    if displayed_width > target_width then
        canvas.set_color(BAR_DRAIN_COLOR)
        canvas.fill_rect(bar_x + target_width, bar_y, displayed_width - target_width, bar_h)
    end

    -- Draw sprite frame on top of health bar
    canvas.draw_image(sprites.ui.boss_health_bar, sprite_x, sprite_y, sprite_w, sprite_h)

    -- Draw title/subtitle text centered on screen (not over pause screen)
    if text_alpha > 0 then
        rest_screen = rest_screen or require("ui/rest_screen")
        if not rest_screen.is_active() then
            canvas.set_global_alpha(alpha * text_alpha)
            local center_x = screen_width / 2
            local center_y = config.ui.canvas_height / 2
            draw_boss_title(scale, center_x, center_y)
            canvas.set_global_alpha(alpha)
        end
    end

    canvas.restore()
end

--- Reset the boss health bar state (call on level cleanup).
function boss_health_bar.reset()
    alpha = 0
    text_alpha = 0
    displayed_health = 0
    target_health = 0
    text_timer = 0
    intro_complete = false
    was_active = false
    defeated_mode = false
    defeated_phase = DEFEATED_PHASE_NONE
    defeated_timer = 0
    title_alpha = 0
    defeated_alpha = 0
    stamp_progress = 0
end

return boss_health_bar
