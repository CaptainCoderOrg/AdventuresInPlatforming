--- Boss block prop - dynamic wall that fades between solid and passable states.
--- Coordinator activates/deactivates blocks during the boss encounter.
--- When solid: full alpha with collision. When faded: alpha 0.5, no collision.
local canvas = require("canvas")
local config = require("config")
local Prop = require("Prop")
local sprites = require("sprites")
local tile_transform = require("platforms/tile_transform")
local world = require("world")

local FADE_DURATION = 0.5  -- Alpha transition time in seconds

--- Update fade progress toward a target alpha value.
---@param prop table Boss block prop instance
---@param dt number Delta time in seconds
---@param target_alpha number Target alpha value (0, 0.5, or 1)
---@param next_state string State to transition to when fade completes
local function update_fade(prop, dt, target_alpha, next_state)
    prop.fade_timer = prop.fade_timer + dt

    local alpha_distance = math.abs(target_alpha - prop.fade_start_alpha)
    local duration = FADE_DURATION * alpha_distance  -- Scale duration by how far we need to go

    if duration <= 0 or prop.fade_timer >= duration then
        prop.fade_alpha = target_alpha
        Prop.set_state(prop, next_state)
    else
        local progress = prop.fade_timer / duration
        prop.fade_alpha = prop.fade_start_alpha + (target_alpha - prop.fade_start_alpha) * progress
    end
end

--- Draw the block tile with current alpha.
---@param prop table Boss block prop instance
local function draw_block(prop)
    local alpha = prop.fade_alpha or 0
    if alpha <= 0 then return end

    local render_info = prop.tile_render_info
    if not render_info then return end

    local ts = sprites.tile_size
    local has_transform = tile_transform.has_transform(prop.flip_h, prop.flip_v)

    canvas.set_global_alpha(alpha)

    if render_info.image then
        local scale = config.ui.SCALE
        local width_scaled = render_info.width * scale
        local height_scaled = render_info.height * scale
        local draw_x = prop.x * ts
        local draw_y = prop.y * ts

        if has_transform then
            canvas.save()
            canvas.translate(draw_x, draw_y)
            tile_transform.apply(prop.flip_h, prop.flip_v, width_scaled, height_scaled)
            canvas.draw_image(render_info.image, 0, 0, width_scaled, height_scaled)
            canvas.restore()
        else
            canvas.draw_image(render_info.image, draw_x, draw_y, width_scaled, height_scaled)
        end
    elseif render_info.tileset_image then
        local local_id = prop.gid - render_info.firstgid
        local tx = local_id % render_info.columns
        local ty = math.floor(local_id / render_info.columns)
        local draw_x = prop.x * ts
        local draw_y = prop.y * ts

        if has_transform then
            canvas.save()
            canvas.translate(draw_x, draw_y)
            tile_transform.apply(prop.flip_h, prop.flip_v, ts, ts)
            sprites.draw_tile(tx, ty, 0, 0, render_info.tileset_image)
            canvas.restore()
        else
            sprites.draw_tile(tx, ty, draw_x, draw_y, render_info.tileset_image)
        end
    end

    canvas.set_global_alpha(1)
end

local definition = {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#00FFFF",
    initial_state = "faded",

    ---@param prop table The prop instance being spawned
    ---@param _def table The prop definition (unused)
    ---@param options table Spawn options containing gid, tile_render_info, flip flags
    on_spawn = function(prop, _def, options)
        prop.gid = options.gid
        prop.tile_render_info = options.tile_render_info
        prop.width = options.width
        prop.height = options.height
        prop.flip_h = options.flip_h
        prop.flip_v = options.flip_v
        prop.fade_alpha = 0.2
        prop.fade_timer = 0
        prop.fade_start_alpha = 0.2
    end,

    states = {
        --- Hidden state - no collider, fully transparent
        hidden = {
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                prop.fade_alpha = 0
            end
        },

        --- Appearing state - collider added immediately, alpha fades to 1
        appearing = {
            start = function(prop)
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
                prop.fade_timer = 0
                prop.fade_start_alpha = prop.fade_alpha
            end,
            update = function(prop, dt)
                update_fade(prop, dt, 1, "visible")
            end,
            draw = draw_block
        },

        --- Visible state - full alpha, collider active
        visible = {
            start = function(prop)
                prop.fade_alpha = 1
                if not prop.collider_shape then
                    prop.collider_shape = world.add_collider(prop)
                end
            end,
            draw = draw_block
        },

        --- Disappearing state - collider removed immediately, alpha fades to 0.5
        disappearing = {
            start = function(prop)
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
                prop.fade_timer = 0
                prop.fade_start_alpha = prop.fade_alpha
            end,
            update = function(prop, dt)
                update_fade(prop, dt, 0.2, "faded")
            end,
            draw = draw_block
        },

        --- Faded state - alpha 0.5, no collider (visible but passable)
        faded = {
            start = function(prop)
                prop.fade_alpha = 0.2
                if prop.collider_shape then
                    world.remove_collider(prop)
                    prop.collider_shape = nil
                end
            end,
            draw = draw_block
        }
    }
}

--- Activate block (called by coordinator) - make solid with fade-in
---@param prop table Boss block prop instance
function definition.activate(prop)
    if prop.state_name ~= "visible" and prop.state_name ~= "appearing" then
        Prop.set_state(prop, "appearing")
    end
end

--- Deactivate block (called by coordinator) - make passable with fade-out
---@param prop table Boss block prop instance
function definition.deactivate(prop)
    if prop.state_name ~= "faded" and prop.state_name ~= "disappearing" and prop.state_name ~= "hidden" then
        Prop.set_state(prop, "disappearing")
    end
end

--- Reset to faded state
---@param prop table Boss block prop instance
function definition.reset(prop)
    Prop.set_state(prop, "faded")
end

return definition
