--- Minimap panel for the rest/pause screen
--- Shows wall outlines, campfire sprites, and blinking player sprite.
--- Only renders content within visited camera_bounds regions (fog of war).
local canvas = require("canvas")
local simple_dialogue = require("ui/simple_dialogue")
local sprites = require("sprites")
local Prop = require("Prop")

local map_panel = {}

-- Cached wall positions (flat array of {x, y, bi} for fast iteration)
local wall_positions = {}
-- Cached campfire positions (flat array of {x, y, bi})
local campfire_positions = {}
local level_w = 0
local level_h = 0
local bounds = {}  -- Camera bounds regions: array of {x, y, width, height}
local visited = {} -- Set of visited bounds indices: visited[i] = true

-- Padding inside the 9-slice panel
local PAD = 10

-- Campfire sprite frame size (16x16 per frame)
local FRAME_SIZE = 16

-- Fixed pixels per tile (in scaled coordinate space)
local TILE_PX = 3

-- Campfire sprite draw size (pixels)
local CAMPFIRE_SIZE = 4

-- Player dot size (pixels)
local PLAYER_DOT_SIZE = 3

-- Player blink speed (radians per second)
local BLINK_SPEED = 6

-- Scroll speed (tiles per second)
local SCROLL_SPEED = 30

-- Current scroll offset in tiles (relative to player-centered origin)
local scroll_x = 0
local scroll_y = 0

--- Find which camera_bounds region contains a tile position.
---@param tx number Tile X coordinate
---@param ty number Tile Y coordinate
---@return number|nil index Bounds index (1-based) or nil if outside all bounds
local function find_bounds_index(tx, ty)
    for i = 1, #bounds do
        local b = bounds[i]
        if tx >= b.x and tx < b.x + b.width and
           ty >= b.y and ty < b.y + b.height then
            return i
        end
    end
    return nil
end

--- Mark the camera_bounds region containing a position as visited.
--- Called per-frame during gameplay to track exploration.
---@param px number X position in tiles
---@param py number Y position in tiles
function map_panel.mark_visited(px, py)
    local i = find_bounds_index(px, py)
    if i then visited[i] = true end
end

--- Build the minimap data from the current level's wall tiles.
--- Called once per level load.
---@param width number Level width in tiles
---@param height number Level height in tiles
---@param camera_bounds table|nil Array of {x, y, width, height} regions
function map_panel.build(width, height, camera_bounds)
    level_w = width
    level_h = height
    bounds = camera_bounds or {}
    visited = {}

    local platforms = require("platforms")
    local has_bounds = #bounds > 0

    -- Cache walls with pre-computed bounds index for O(1) visited check at draw time
    wall_positions = {}
    local n = 0
    for _, tile in pairs(platforms.walls.tiles) do
        local bi = has_bounds and find_bounds_index(tile.x, tile.y) or nil
        if not has_bounds or bi then
            n = n + 1
            wall_positions[n] = { x = tile.x, y = tile.y, bi = bi }
        end
    end
    for _, tile in pairs(platforms.walls.solo_tiles) do
        local bi = has_bounds and find_bounds_index(tile.x, tile.y) or nil
        if not has_bounds or bi then
            n = n + 1
            wall_positions[n] = { x = tile.x, y = tile.y, bi = bi }
        end
    end

    -- Cache campfire positions with pre-computed bounds index
    campfire_positions = {}
    local campfires = Prop.get_all_of_type("campfire")
    for i = 1, #campfires do
        local fire = campfires[i]
        local bi = has_bounds and find_bounds_index(fire.x, fire.y) or nil
        if not has_bounds or bi then
            campfire_positions[#campfire_positions + 1] = { x = fire.x, y = fire.y, bi = bi }
        end
    end
end

--- Get the set of visited bounds indices for saving.
---@return table visited_indices Array of visited bounds indices (1-based)
function map_panel.get_visited()
    local result = {}
    for i = 1, #bounds do
        if visited[i] then
            result[#result + 1] = i
        end
    end
    return result
end

--- Restore visited bounds from saved data.
---@param visited_indices table|nil Array of visited bounds indices (1-based)
function map_panel.set_visited(visited_indices)
    visited = {}
    if visited_indices then
        for _, i in ipairs(visited_indices) do
            visited[i] = true
        end
    end
end

--- Scroll the map view by a directional offset.
---@param dx number Horizontal direction (-1, 0, or 1)
---@param dy number Vertical direction (-1, 0, or 1)
---@param dt number Delta time in seconds
function map_panel.scroll(dx, dy, dt)
    scroll_x = scroll_x + dx * SCROLL_SPEED * dt
    scroll_y = scroll_y + dy * SCROLL_SPEED * dt
end

--- Reset scroll offset to center on the player.
function map_panel.reset_scroll()
    scroll_x = 0
    scroll_y = 0
end

--- Draw the minimap panel.
---@param x number Panel X position (in scaled coordinates)
---@param y number Panel Y position
---@param width number Panel width
---@param height number Panel height
---@param player table Player instance with x, y fields
---@param elapsed_time number Accumulated time in seconds for animations
function map_panel.draw(x, y, width, height, player, elapsed_time)
    -- Draw 9-slice background
    simple_dialogue.draw({ x = x, y = y, width = width, height = height, text = "" })

    if level_w == 0 or level_h == 0 then return end

    local has_bounds = #bounds > 0
    local inner_w = width - PAD * 2
    local inner_h = height - PAD * 2

    -- Player-centered origin: place player tile at center of panel
    local center_x = x + PAD + inner_w / 2
    local center_y = y + PAD + inner_h / 2
    local player_tx = player and player.x or level_w / 2
    local player_ty = player and player.y or level_h / 2
    local ox = center_x - (player_tx + 0.5 + scroll_x) * TILE_PX
    local oy = center_y - (player_ty + 0.5 + scroll_y) * TILE_PX

    -- Visible tile range for viewport culling
    local clip_x = x + PAD
    local clip_y = y + PAD
    local vis_x1 = (clip_x - ox) / TILE_PX - 1
    local vis_y1 = (clip_y - oy) / TILE_PX - 1
    local vis_x2 = (clip_x + inner_w - ox) / TILE_PX + 1
    local vis_y2 = (clip_y + inner_h - oy) / TILE_PX + 1

    -- Clip to panel interior
    canvas.save()
    canvas.begin_path()
    canvas.rect(clip_x, clip_y, inner_w, inner_h)
    canvas.clip()

    -- Draw wall tiles (viewport culled, O(1) visited check via pre-computed bounds index)
    canvas.set_color("#8899AA")
    for i = 1, #wall_positions do
        local pos = wall_positions[i]
        if pos.x >= vis_x1 and pos.x <= vis_x2 and pos.y >= vis_y1 and pos.y <= vis_y2 then
            if not has_bounds or visited[pos.bi] then
                canvas.fill_rect(ox + pos.x * TILE_PX, oy + pos.y * TILE_PX, TILE_PX, TILE_PX)
            end
        end
    end

    local campfire_half = CAMPFIRE_SIZE / 2

    -- Draw cached campfire sprites (first frame, blinking alpha, O(1) visited check)
    local fire_alpha = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(elapsed_time * BLINK_SPEED * 0.7))
    canvas.set_global_alpha(fire_alpha)
    for i = 1, #campfire_positions do
        local fire = campfire_positions[i]
        if not has_bounds or visited[fire.bi] then
            local cx = ox + (fire.x + 0.5) * TILE_PX - campfire_half
            local cy = oy + (fire.y + 0.5) * TILE_PX - campfire_half
            canvas.draw_image(sprites.environment.campfire,
                cx, cy, CAMPFIRE_SIZE, CAMPFIRE_SIZE,
                0, 0, FRAME_SIZE, FRAME_SIZE)
        end
    end
    canvas.set_global_alpha(1)

    -- Draw player dot (blinking green)
    if player then
        local alpha = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(elapsed_time * BLINK_SPEED))
        canvas.set_global_alpha(alpha)
        canvas.set_color("#00FF00")
        local dot_half = PLAYER_DOT_SIZE / 2
        local px = ox + (player.x + 0.5) * TILE_PX - dot_half
        local py = oy + (player.y + 0.5) * TILE_PX - dot_half
        canvas.fill_rect(px, py, PLAYER_DOT_SIZE, PLAYER_DOT_SIZE)
        canvas.set_global_alpha(1)
    end

    canvas.restore()
end

return map_panel
