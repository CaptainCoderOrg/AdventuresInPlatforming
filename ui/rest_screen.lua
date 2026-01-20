--- Rest screen overlay with circular viewport effect around campfire
local canvas = require("canvas")
local controls = require("controls")
local button = require("ui/button")
local utils = require("ui/utils")
local config = require("config")

local rest_screen = {}

local STATE = {
    HIDDEN = "hidden",
    FADING_IN = "fading_in",
    OPEN = "open",
    FADING_OUT = "fading_out",
    RELOADING = "reloading",
    FADING_BACK_IN = "fading_back_in",
}

-- Timing configuration (seconds)
local FADE_IN_DURATION = 0.5
local FADE_OUT_DURATION = 0.3
local RELOAD_PAUSE = 0.1
local FADE_BACK_IN_DURATION = 0.4

-- Visual configuration
local CIRCLE_RADIUS = 40      -- Base radius in pixels (before scale)
local PULSE_SPEED = 2         -- Pulses per second
local PULSE_AMOUNT = 0.08     -- 8% radius variation
local CIRCLE_EDGE_PADDING = 8 -- pixels from screen edge (configurable)

--- Apply ease-out curve to interpolation value
--- Uses quadratic ease-out: 1 - (1 - t)^2
---@param t number Linear interpolation value (0-1)
---@return number Eased interpolation value
local function ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

local state = STATE.HIDDEN
local fade_progress = 0
local elapsed_time = 0

-- Campfire position in world coordinates (tiles)
local campfire_x = 0
local campfire_y = 0

-- Camera reference (set when showing)
local camera_ref = nil

local continue_callback = nil

-- Circle lerp state (screen pixels)
local circle_start_x = 0
local circle_start_y = 0
local circle_target_x = 0
local circle_target_y = 0
local circle_lerp_t = 0  -- 0 = at campfire, 1 = at bottom-left
local CIRCLE_LERP_DURATION = 0.3  -- seconds to move circle

-- Original camera position (tiles) - saved on enter, restored on exit
local original_camera_x = 0
local original_camera_y = 0

-- Last known good camera position (saved every frame from main.lua)
local last_camera_x = 0
local last_camera_y = 0

local continue_button = nil

-- Layout constants (at 1x scale)
local BUTTON_WIDTH = 70
local BUTTON_HEIGHT = 12

-- Mouse input tracking
local mouse_active = true
local last_mouse_x = 0
local last_mouse_y = 0

--- Initialize rest screen components (creates continue button)
---@return nil
function rest_screen.init()
    continue_button = button.create({
        x = 0, y = 0,
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        label = "Continue",
        text_only = true,
        on_click = function()
            if state == STATE.OPEN then
                rest_screen.trigger_continue()
            end
        end
    })
end

--- Trigger the fade out and continue sequence
---@return nil
function rest_screen.trigger_continue()
    state = STATE.FADING_OUT
    fade_progress = 0
end

--- Save camera position every frame (called from main.lua before player:update)
--- This ensures we capture the camera position before anything can modify it
---@param x number Camera X position in tiles
---@param y number Camera Y position in tiles
function rest_screen.save_camera_position(x, y)
    last_camera_x = x
    last_camera_y = y
end

--- Show the rest screen centered on a campfire
---@param world_x number Campfire center X in tile coordinates
---@param world_y number Campfire center Y in tile coordinates
---@param camera table Camera instance for position calculation
function rest_screen.show(world_x, world_y, camera)
    if state == STATE.HIDDEN then
        campfire_x = world_x
        campfire_y = world_y
        camera_ref = camera
        state = STATE.FADING_IN
        fade_progress = 0
        elapsed_time = 0

        -- Use the last known good camera position (saved in main.lua before player:update)
        -- This ensures we capture the position before anything can modify it
        original_camera_x = last_camera_x
        original_camera_y = last_camera_y

        -- Initialize circle lerp: start at campfire, target bottom-left
        local sprites = require("sprites")
        local scaled_radius = CIRCLE_RADIUS * config.ui.SCALE

        -- Starting position (campfire screen coords)
        circle_start_x = (world_x - camera:get_x()) * sprites.tile_size
        circle_start_y = (world_y - camera:get_y()) * sprites.tile_size

        -- Target position: bottom-left with padding (circle center offset by radius)
        circle_target_x = CIRCLE_EDGE_PADDING + scaled_radius
        circle_target_y = canvas.get_height() - CIRCLE_EDGE_PADDING - scaled_radius

        circle_lerp_t = 0  -- Start at campfire position
        mouse_active = true
    end
end

--- Set the continue callback function (reloads level from checkpoint)
---@param fn function Function to call when continuing
function rest_screen.set_continue_callback(fn)
    continue_callback = fn
end

--- Check if rest screen is blocking game input
---@return boolean is_active True if rest screen is visible or animating
function rest_screen.is_active()
    return state ~= STATE.HIDDEN
end

--- Get the original camera position from when rest screen was opened
---@return number x Camera X position in tiles
---@return number y Camera Y position in tiles
function rest_screen.get_original_camera_pos()
    return original_camera_x, original_camera_y
end

--- Check if the circle should be visible (during fade in/out or when open)
---@return boolean True if circle is visible
local function is_circle_visible()
    return state == STATE.FADING_IN or state == STATE.OPEN or state == STATE.FADING_OUT
end

--- Get the current camera offset to keep campfire centered in circle
---@return number offset_x Camera X offset in pixels
---@return number offset_y Camera Y offset in pixels
function rest_screen.get_camera_offset()
    if not is_circle_visible() then
        return 0, 0
    end

    local t = ease_out(circle_lerp_t)
    local offset_x = (circle_target_x - circle_start_x) * t
    local offset_y = (circle_target_y - circle_start_y) * t

    return offset_x, offset_y
end

--- Process rest screen input
function rest_screen.input()
    if state ~= STATE.OPEN then return end

    if controls.menu_confirm_pressed() then
        rest_screen.trigger_continue()
    end
end

--- Advance fade animations and handle state transitions
---@param dt number Delta time in seconds
function rest_screen.update(dt)
    if state == STATE.HIDDEN then return end

    elapsed_time = elapsed_time + dt

    if state == STATE.FADING_IN then
        fade_progress = fade_progress + dt / FADE_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.OPEN
        end
        -- Move circle toward bottom-left
        circle_lerp_t = math.min(circle_lerp_t + dt / CIRCLE_LERP_DURATION, 1)
    elseif state == STATE.FADING_OUT then
        fade_progress = fade_progress + dt / FADE_OUT_DURATION
        if fade_progress >= 1 then
            fade_progress = 0
            state = STATE.RELOADING
        end
        -- Move circle back toward campfire
        circle_lerp_t = math.max(circle_lerp_t - dt / CIRCLE_LERP_DURATION, 0)
    elseif state == STATE.RELOADING then
        fade_progress = fade_progress + dt / RELOAD_PAUSE
        if fade_progress >= 1 then
            -- Call continue callback
            if continue_callback then
                continue_callback()
            end
            state = STATE.FADING_BACK_IN
            fade_progress = 0
        end
    elseif state == STATE.FADING_BACK_IN then
        fade_progress = fade_progress + dt / FADE_BACK_IN_DURATION
        if fade_progress >= 1 then
            fade_progress = 1
            state = STATE.HIDDEN
        end
    end

    -- Update button hover states when menu is open
    if state == STATE.OPEN then
        local scale = config.ui.SCALE
        local screen_w = canvas.get_width()
        local screen_h = canvas.get_height()

        -- Re-enable mouse input if mouse has moved
        local mx = canvas.get_mouse_x()
        local my = canvas.get_mouse_y()
        if mx ~= last_mouse_x or my ~= last_mouse_y then
            mouse_active = true
            last_mouse_x = mx
            last_mouse_y = my
        end

        -- Update button position
        local center_x = screen_w / (2 * scale)
        local center_y = screen_h / (2 * scale)
        continue_button.x = center_x - BUTTON_WIDTH / 2
        continue_button.y = center_y - BUTTON_HEIGHT / 2 + 30  -- Below center

        -- Handle mouse hover
        if mouse_active then
            local local_mx = mx / scale
            local local_my = my / scale
            continue_button:update(local_mx, local_my)
        end
    end
end

--- Draw the rest screen overlay
function rest_screen.draw()
    if state == STATE.HIDDEN then return end

    local scale = config.ui.SCALE
    local screen_w = canvas.get_width()
    local screen_h = canvas.get_height()

    -- Calculate circle position using eased lerp progress
    local t = ease_out(circle_lerp_t)
    local screen_x = circle_start_x + (circle_target_x - circle_start_x) * t
    local screen_y = circle_start_y + (circle_target_y - circle_start_y) * t

    -- Pulsing radius
    local pulse = math.sin(elapsed_time * PULSE_SPEED * math.pi * 2) * PULSE_AMOUNT
    local radius = CIRCLE_RADIUS * scale * (1 + pulse)

    -- Calculate overlay alpha based on state
    local overlay_alpha = 0
    local content_alpha = 0
    local hole_radius = radius  -- Radius of the visible area

    if state == STATE.FADING_IN then
        overlay_alpha = fade_progress
        content_alpha = fade_progress
    elseif state == STATE.OPEN then
        overlay_alpha = 1
        content_alpha = 1
    elseif state == STATE.FADING_OUT then
        -- Reverse of fade in: overlay fades out, hole stays full
        overlay_alpha = 1 - fade_progress
        content_alpha = 1 - fade_progress
    elseif state == STATE.RELOADING then
        overlay_alpha = 0
        content_alpha = 0
    elseif state == STATE.FADING_BACK_IN then
        overlay_alpha = 0
        content_alpha = 0
    end

    canvas.set_global_alpha(overlay_alpha)

    -- Create the circular viewport effect using clip with evenodd
    -- This clips to the area OUTSIDE the circle, then fills with black
    if hole_radius > 1 then
        -- Save state before clipping
        canvas.save()

        -- Create a compound path: outer rectangle + inner circle
        -- With evenodd clip, this creates a "donut" clipping region
        canvas.begin_path()
        canvas.rect(0, 0, screen_w, screen_h)
        canvas.arc(screen_x, screen_y, hole_radius, 0, math.pi * 2)
        canvas.clip("evenodd")

        -- Fill the clipped area (everything except the circle) with black
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)

        -- Restore to remove the clip
        canvas.restore()

        -- Draw soft edge vignette around the hole (darkens the edges of visible area)
        local gradient = canvas.create_radial_gradient(
            screen_x, screen_y, hole_radius * 0.5,  -- Inner edge (fully transparent)
            screen_x, screen_y, hole_radius         -- Outer edge (semi-transparent)
        )
        gradient:add_color_stop(0, "rgba(0,0,0,0)")
        gradient:add_color_stop(0.7, "rgba(0,0,0,0.3)")
        gradient:add_color_stop(1, "rgba(0,0,0,0.7)")
        canvas.set_fill_style(gradient)
        canvas.begin_path()
        canvas.arc(screen_x, screen_y, hole_radius, 0, math.pi * 2)
        canvas.fill()

        -- Draw pulsing glow ring around the viewport edge
        local glow_alpha = 0.4 + pulse * 0.2
        local glow_inner = hole_radius * 0.85
        local glow_outer = hole_radius * 1.2

        -- Warm glow gradient (orange/yellow)
        local glow_gradient = canvas.create_radial_gradient(
            screen_x, screen_y, glow_inner,
            screen_x, screen_y, glow_outer
        )
        glow_gradient:add_color_stop(0, "rgba(255,180,50,0)")
        glow_gradient:add_color_stop(0.4, string.format("rgba(255,150,40,%.2f)", glow_alpha * 0.5))
        glow_gradient:add_color_stop(1, "rgba(255,80,20,0)")

        canvas.set_fill_style(glow_gradient)
        canvas.begin_path()
        canvas.arc(screen_x, screen_y, glow_outer, 0, math.pi * 2)
        canvas.fill()
    else
        -- Full black when hole is closed
        canvas.set_fill_style("#000000")
        canvas.fill_rect(0, 0, screen_w, screen_h)
    end

    -- Draw content (button) only during fading_in and open states
    if content_alpha > 0 then
        canvas.set_global_alpha(content_alpha)

        canvas.save()
        canvas.scale(scale, scale)

        local center_x = screen_w / (2 * scale)
        local center_y = screen_h / (2 * scale)

        -- Update button position
        continue_button.x = center_x - BUTTON_WIDTH / 2
        continue_button.y = center_y - BUTTON_HEIGHT / 2 + 30

        -- Draw button (always focused since it's the only option)
        continue_button:draw(true)

        canvas.restore()
    end

    canvas.set_global_alpha(1)
end

return rest_screen
