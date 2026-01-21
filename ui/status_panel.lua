--- Status panel for displaying player stats in rest/pause screen
local simple_dialogue = require("ui/simple_dialogue")
local Playtime = require("Playtime")
local SaveSlots = require("SaveSlots")

local status_panel = {}
status_panel.__index = status_panel

--- Create a new status panel
---@param opts {x: number, y: number, width: number, height: number, player: table|nil}
---@return table status_panel
function status_panel.create(opts)
    local self = setmetatable({}, status_panel)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 100
    self.height = opts.height or 100
    self.player = opts.player
    return self
end

--- Set the player reference for stats display
---@param player table|nil Player instance
---@return nil
function status_panel:set_player(player)
    self.player = player
end

--- Build the stats text for display
---@return string Stats text with newlines
function status_panel:build_stats_text()
    if not self.player then return "" end

    local player = self.player
    local lines = {
        "Level: " .. player.level,
        "Exp: " .. player.experience,
        "Gold: " .. player.gold,
        "",
        "HP: " .. player:health() .. "/" .. player.max_health,
        "SP: " .. (player.max_stamina - player.stamina_used) .. "/" .. player.max_stamina,
        "EP: " .. (player.max_energy - player.energy_used) .. "/" .. player.max_energy,
        "DEF: " .. player.defense,
        "STR: " .. player.strength,
        "CRIT: " .. player.critical_chance .. "%",
        "",
        "Time: " .. SaveSlots.format_playtime(Playtime.get())
    }
    return table.concat(lines, "\n")
end

--- Update the status panel (for future: hover detection for tooltips)
---@param dt number Delta time in seconds
---@param local_mx number Local mouse X coordinate
---@param local_my number Local mouse Y coordinate
---@param mouse_active boolean Whether mouse input is active
function status_panel:update(dt, local_mx, local_my, mouse_active)
    -- For future: hover detection for tooltips
end

--- Handle input (for future: keyboard/gamepad navigation)
---@return nil
function status_panel:input()
end

--- Draw the status panel
---@return nil
function status_panel:draw()
    simple_dialogue.draw({
        x = self.x,
        y = self.y,
        width = self.width,
        height = self.height,
        text = self:build_stats_text()
    })
end

return status_panel
