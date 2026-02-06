--- Toast notification for new journal entries
--- Shows a small popup in the bottom-right during gameplay
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local utils = require("ui/utils")
local config = require("config")
local entries_registry = require("journal/entries")

local journal_toast = {}

-- 9-slice definition (same as simple_dialogue)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Layout (at 1x scale, rendered with canvas.scale)
local TOAST_WIDTH = 160
local TOAST_HEIGHT = 32
local MARGIN = 8
local TEXT_PADDING_LEFT = 10
local TEXT_PADDING_TOP = 7
local LINE_HEIGHT = 8
local FONT_SIZE = 8

-- Timing (seconds)
local FADE_IN_DURATION = 0.3
local VISIBLE_DURATION = 2.5
local FADE_OUT_DURATION = 0.5

-- State machine
local STATE = { HIDDEN = 1, FADING_IN = 2, VISIBLE = 3, FADING_OUT = 4 }
local state = STATE.HIDDEN
local timer = 0
local current_entry_id = nil

-- Queue for multiple entries
local pending = {}

--- Start showing the next entry from the queue
local function show_next()
    if #pending == 0 then
        state = STATE.HIDDEN
        current_entry_id = nil
        return
    end
    current_entry_id = table.remove(pending, 1)
    state = STATE.FADING_IN
    timer = 0
end

--- Add an entry to the toast queue; if hidden, start showing immediately
---@param entry_id string Journal entry ID
function journal_toast.push(entry_id)
    if not entries_registry[entry_id] then return end
    table.insert(pending, entry_id)
    if state == STATE.HIDDEN then
        show_next()
    end
end

--- Advance toast state machine (pauses when blocked by overlay screens)
---@param dt number Delta time in seconds
---@param paused boolean If true, timer does not advance (overlay screen is active)
function journal_toast.update(dt, paused)
    if state == STATE.HIDDEN then return end
    if paused then return end

    timer = timer + dt

    if state == STATE.FADING_IN then
        if timer >= FADE_IN_DURATION then
            state = STATE.VISIBLE
            timer = 0
        end
    elseif state == STATE.VISIBLE then
        if timer >= VISIBLE_DURATION then
            state = STATE.FADING_OUT
            timer = 0
        end
    elseif state == STATE.FADING_OUT then
        if timer >= FADE_OUT_DURATION then
            show_next()
        end
    end
end

--- Render the toast notification
function journal_toast.draw()
    if state == STATE.HIDDEN or not current_entry_id then return end

    local entry = entries_registry[current_entry_id]
    if not entry then return end

    local alpha = 1
    if state == STATE.FADING_IN then
        alpha = timer / FADE_IN_DURATION
    elseif state == STATE.FADING_OUT then
        alpha = 1 - timer / FADE_OUT_DURATION
    end

    local scale = config.ui.SCALE
    local hud_height = config.ui.HUD_HEIGHT_PX
    local screen_w = config.ui.canvas_width / scale
    local screen_h = config.ui.canvas_height / scale

    local x = screen_w - TOAST_WIDTH - MARGIN
    local y = screen_h - hud_height - TOAST_HEIGHT - MARGIN

    canvas.save()
    canvas.set_global_alpha(alpha)
    canvas.scale(scale, scale)

    nine_slice.draw(slice, x, y, TOAST_WIDTH, TOAST_HEIGHT)

    canvas.set_font_family("menu_font")
    canvas.set_font_size(FONT_SIZE)
    canvas.set_text_baseline("top")
    canvas.set_text_align("left")

    utils.draw_outlined_text("New Journal Entry", x + TEXT_PADDING_LEFT, y + TEXT_PADDING_TOP, "#FFFFFF")
    utils.draw_outlined_text(entry.title, x + TEXT_PADDING_LEFT, y + TEXT_PADDING_TOP + LINE_HEIGHT, "#FFD700")

    canvas.restore()
    canvas.set_global_alpha(1)
end

return journal_toast
