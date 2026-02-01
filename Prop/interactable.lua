--- Interactable prop definition - invisible trigger areas with custom handlers
--- Shows text prompt when player is nearby, calls handler on interact
local common = require("Prop/common")
local TextDisplay = require("TextDisplay")

--- Resolve a handler path like "garden.on_open_cottage" to a function
--- Loads Maps/<map_name> and navigates the nested table path
---@param path string Dot-separated path (e.g., "garden.on_open_cottage")
---@return function|nil handler The resolved function or nil if not found
local function resolve_handler(path)
    if not path or path == "" then return nil end

    -- Strip leading "maps." prefix if present (allows both "maps.garden.events.x" and "garden.events.x")
    if path:sub(1, 5) == "maps." then
        path = path:sub(6)
    end

    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    if #parts < 2 then return nil end

    -- First part is map name, load from Maps/<name>
    local map_name = parts[1]
    local ok, map_module = pcall(require, "Maps/" .. map_name)
    if not ok or not map_module then
        print("[Interactable] Warning: Could not load Maps/" .. map_name)
        return nil
    end

    -- Navigate remaining path
    local current = map_module
    for i = 2, #parts do
        current = current[parts[i]]
        if not current then
            print("[Interactable] Warning: Path not found: " .. path)
            return nil
        end
    end

    if type(current) ~= "function" then
        print("[Interactable] Warning: Path does not resolve to function: " .. path)
        return nil
    end

    return current
end

return {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#00FFFF",  -- Cyan for debug visibility

    ---@param prop table The prop instance being spawned
    ---@param _def table The prop definition (unused)
    ---@param options table Spawn options (text, on_interact, width, height)
    on_spawn = function(prop, _def, options)
        -- Override box dimensions from tilemap if provided
        prop.box.w = options.width or prop.box.w
        prop.box.h = options.height or prop.box.h

        -- Create text display for interaction prompt (optional)
        if options.text then
            prop.text_display = TextDisplay.new(options.text, { anchor = "top" })
        end

        -- Resolve handler function from path string
        prop.handler = resolve_handler(options.on_interact)
    end,

    initial_state = "idle",

    states = {
        idle = {
            ---@param prop table The prop instance
            ---@param player table The player instance
            ---@return boolean True if interaction occurred
            interact = function(prop, player)
                if prop.handler then
                    prop.handler({ player = player, prop = prop })
                    return true
                end
                return false
            end,

            ---@param prop table The prop instance
            ---@param dt number Delta time in seconds
            ---@param player table The player object
            update = function(prop, dt, player)
                if prop.text_display then
                    local is_active = player and common.player_touching(prop, player)
                    prop.text_display:update(dt, is_active)
                end
            end,

            ---@param prop table The prop instance
            draw = function(prop)
                if prop.text_display then
                    prop.text_display:draw(prop.x, prop.y, prop.box.w, prop.box.h)
                end
            end
        }
    }
}
