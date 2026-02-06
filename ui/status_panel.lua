--- Status panel for displaying player stats in rest/pause screen
local canvas = require("canvas")
local nine_slice = require("ui/nine_slice")
local sprites = require("sprites")
local controls = require("controls")
local Playtime = require("Playtime")
local SaveSlots = require("SaveSlots")
local stats = require("player.stats")
local inventory_grid = require("ui/inventory_grid")
local unique_item_registry = require("Prop.unique_item_registry")
local stackable_item_registry = require("Prop.stackable_item_registry")
local weapon_sync = require("player.weapon_sync")

local status_panel = {}
status_panel.__index = status_panel

-- 9-slice definition (same as simple_dialogue)
local slice = nine_slice.create(sprites.ui.simple_dialogue, 76, 37, 10, 7, 9, 7)

-- Text configuration
local TEXT_PADDING_TOP = 7
local TEXT_PADDING_LEFT = 10
local TEXT_PADDING_RIGHT = 9
local LINE_HEIGHT = 8

-- Cap at 20 to keep diminishing returns tables bounded
local MAX_STAT_LEVEL = 20

--- Generate a fibonacci-like cost table from two starting values
---@param a number First cost
---@param b number Second cost
---@param max number Number of entries to generate
---@return number[] table Array of costs
local function generate_fib_table(a, b, max)
    local t = { [1] = a, [2] = b }
    for i = 3, max do
        t[i] = t[i - 1] + t[i - 2]
    end
    return t
end

--- Generate a fibonacci-like cost table from a custom seed sequence
---@param seeds number[] Initial cost values (must have at least 2 entries)
---@param max number Number of entries to generate
---@return number[] table Array of costs
local function generate_seeded_fib_table(seeds, max)
    local t = {}
    for i, v in ipairs(seeds) do
        t[i] = v
    end
    for i = #seeds + 1, max do
        t[i] = t[i - 1] + t[i - 2]
    end
    return t
end

-- Per-stat XP cost tables (fibonacci-like sequences).
-- Health/Stamina use seeded tables for a steeper early curve.
-- Defence/Recovery are mid-cost since percentage bonuses scale multiplicatively.
-- Energy/Critical are expensive as high-impact combat modifiers.
local STAT_EXP_TABLES = {
    Health   = generate_seeded_fib_table({3, 8, 20, 30}, MAX_STAT_LEVEL),
    Stamina  = generate_seeded_fib_table({5, 15, 25},    MAX_STAT_LEVEL),
    Energy   = generate_fib_table(25, 50, MAX_STAT_LEVEL),
    Defence  = generate_fib_table(20, 30, MAX_STAT_LEVEL),
    Recovery = generate_fib_table(20, 40, MAX_STAT_LEVEL),
    Critical = generate_fib_table(50, 100, MAX_STAT_LEVEL),
}

-- Stats that can be leveled up
local LEVELABLE_STATS = {
    Health = true,
    Stamina = true,
    Energy = true,
    Defence = true,
    Recovery = true,
    Critical = true,
}

-- Stat descriptions for the info panel
local STAT_DESCRIPTIONS = {
    Level = "Your current level. Gain experience to level up and increase your stats.",
    Experience = "Points earned by defeating enemies. Spend experience at campfires to increase your level.",
    Gold = "Currency used to purchase items and equipment from merchants.",
    Health = "Your maximum hit points. When health reaches zero, you are defeated.",
    Stamina = "Used for attacks and physical abilities. Depleting stamina leaves you vulnerable until you recover.",
    Energy = "Used by magical abilities. Rest at a campfire to restore.",
    Defence = "Reduces incoming damage from enemy attacks.",
    Recovery = "Increases the rate at which stamina regenerates.",
    Critical = "Chance to deal extra damage with each attack.",
    ["Required XP"] = "Experience required for next level.",
    Time = "Total time spent playing this save file.",
}

-- Must match the number of rows emitted by build_stats_rows (11 stat rows + 2 blank separators)
local STATS_ROW_COUNT = 13

--- Get suffix for levelable stats (shows point increase)
---@param panel table The status_panel instance
---@param stat_name string The stat label
---@return string|nil suffix
local function get_stat_suffix(panel, stat_name)
    local count = panel:get_pending_count(stat_name)
    if count > 0 then
        return "(+" .. count .. ")"
    end
    return nil
end

--- Get suffix for percentage stats (shows percentage increase with diminishing returns)
---@param panel table The status_panel instance
---@param stat_name string The stat label
---@param current_points number Current stat points
---@return string|nil suffix
local function get_percent_suffix(panel, stat_name, current_points)
    local count = panel:get_pending_count(stat_name)
    if count > 0 then
        local stat_type = stat_name:lower()
        local current_percent = stats.calculate_percent(current_points, stat_type)
        local new_percent = stats.calculate_percent(current_points + count, stat_type)
        return string.format("(+%.1f%%)", new_percent - current_percent)
    end
    return nil
end

--- Create a new status panel
---@param opts {x: number, y: number, width: number, height: number, player: table|nil}
---@return status_panel
function status_panel.create(opts)
    local self = setmetatable({}, status_panel)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 100
    self.height = opts.height or 100
    self.player = opts.player
    self.selected_index = 1
    self.selectable_rows = {}  -- Maps visual index to selectable row data
    self.active = false        -- Whether panel is in active navigation mode
    self.hovered_index = nil   -- Mouse hover index (separate from keyboard selection)
    self.pending_upgrades = {} -- Track pending stat upgrades: {stat_name = count}
    self.pending_costs = {}    -- Track cost per upgrade: {stat_name = {cost1, cost2, ...}}
    self.focus_area = "stats"  -- "stats" or "inventory"
    self.on_use_item = nil     -- Callback for usable items: fn(item_id)
    self.inventory = inventory_grid.create({ x = 0, y = 0 })

    -- Pre-allocate reusable tables to avoid per-frame allocations
    self._cached_rows = {}
    for i = 1, STATS_ROW_COUNT do
        self._cached_rows[i] = {}
    end
    self._selectable_pool = {}
    for i = 1, 11 do  -- Max 11 selectable rows (all non-blank rows)
        self._selectable_pool[i] = { label = nil, visual_index = nil }
    end

    return self
end

--- Set the player reference for stats display
---@param player table|nil Player instance
---@return nil
function status_panel:set_player(player)
    self.player = player
    if player then
        self.inventory:set_items(player.unique_items)
        self.inventory:set_stackable(player.stackable_items)
        self.inventory:set_equipped(player.equipped_items, player)
        self.inventory.on_use_item = self.on_use_item
        -- Sync player ability flags with current equipment
        weapon_sync.sync(player)
    end
end

--- Check if player can afford to upgrade any stat
---@param available_exp number|nil Pre-computed available XP
---@return boolean can_level True if player can afford at least one stat upgrade
function status_panel:can_level_up(available_exp)
    if not self.player then return false end
    for stat_name in pairs(LEVELABLE_STATS) do
        if self:can_afford_upgrade(stat_name, available_exp) then
            return true
        end
    end
    return false
end

--- Get the minimum upgrade cost across all non-maxed levelable stats
---@return number|nil min_cost Minimum XP cost, or nil if all stats are maxed
function status_panel:get_min_upgrade_cost()
    if not self.player then return nil end
    local min_cost = nil
    for stat_name in pairs(LEVELABLE_STATS) do
        local cost = self:get_next_upgrade_cost(stat_name)
        if cost ~= math.huge then
            if not min_cost or cost < min_cost then
                min_cost = cost
            end
        end
    end
    return min_cost
end

--- Get the total pending XP cost
---@return number total Total XP cost of all pending upgrades
function status_panel:get_total_pending_cost()
    local total = 0
    for stat_name, costs in pairs(self.pending_costs) do
        for _, cost in ipairs(costs) do
            total = total + cost
        end
    end
    return total
end

--- Check if there are any pending upgrades
---@return boolean has_pending True if there are pending upgrades
function status_panel:has_pending_upgrades()
    return self:get_total_pending_cost() > 0
end

--- Get pending upgrade count for a stat
---@param stat_name string The stat label
---@return number count Number of pending upgrades
function status_panel:get_pending_count(stat_name)
    return self.pending_upgrades[stat_name] or 0
end

--- Get total number of pending upgrades across all stats
---@return number total Total number of pending upgrades
function status_panel:get_total_pending_upgrades()
    local total = 0
    for _, count in pairs(self.pending_upgrades) do
        total = total + count
    end
    return total
end

--- Get cost for next upgrade of a stat
---@param stat_name string The stat label
---@return number cost XP cost for next upgrade (math.huge if at cap)
function status_panel:get_next_upgrade_cost(stat_name)
    if not self.player then return 0 end
    local current = self.player.stat_upgrades[stat_name] or 0
    local pending = self.pending_upgrades[stat_name] or 0
    local next_index = current + pending + 1
    local exp_table = STAT_EXP_TABLES[stat_name]
    if not exp_table or next_index > MAX_STAT_LEVEL then
        return math.huge
    end
    return exp_table[next_index]
end

--- Check if player can afford to upgrade a stat
---@param stat_name string The stat label
---@param available_exp number|nil Pre-computed available XP (avoids recomputing total pending cost)
---@return boolean can_afford True if player has enough XP and stat is not at cap
function status_panel:can_afford_upgrade(stat_name, available_exp)
    if not self.player then return false end
    if not STAT_EXP_TABLES[stat_name] then return false end
    local current = self.player.stat_upgrades[stat_name] or 0
    local pending = self.pending_upgrades[stat_name] or 0
    if current + pending >= MAX_STAT_LEVEL then return false end
    local cost = self:get_next_upgrade_cost(stat_name)
    available_exp = available_exp or (self.player.experience - self:get_total_pending_cost())
    return available_exp >= cost
end

--- Add a pending upgrade for the highlighted stat
---@return boolean success True if upgrade was added
function status_panel:add_pending_upgrade()
    local stat = self:get_highlighted_stat()
    if not stat or not LEVELABLE_STATS[stat] then
        return false
    end

    if not self:can_afford_upgrade(stat) then
        return false
    end

    local cost = self:get_next_upgrade_cost(stat)

    self.pending_upgrades[stat] = (self.pending_upgrades[stat] or 0) + 1
    self.pending_costs[stat] = self.pending_costs[stat] or {}
    table.insert(self.pending_costs[stat], cost)

    return true
end

--- Remove a pending upgrade for the highlighted stat
---@return boolean success True if upgrade was removed
function status_panel:remove_pending_upgrade()
    local stat = self:get_highlighted_stat()
    if not stat then return false end

    local count = self.pending_upgrades[stat] or 0
    if count <= 0 then return false end

    self.pending_upgrades[stat] = count - 1
    if self.pending_upgrades[stat] == 0 then
        self.pending_upgrades[stat] = nil
    end

    -- Remove the last cost
    if self.pending_costs[stat] and #self.pending_costs[stat] > 0 then
        table.remove(self.pending_costs[stat])
        if #self.pending_costs[stat] == 0 then
            self.pending_costs[stat] = nil
        end
    end

    return true
end

--- Confirm all pending upgrades - apply them to the player
---@return boolean success True if upgrades were applied
function status_panel:confirm_upgrades()
    if not self.player or not self:has_pending_upgrades() then
        return false
    end

    local total_cost = self:get_total_pending_cost()
    if self.player.experience < total_cost then
        return false
    end

    -- Deduct experience
    self.player.experience = self.player.experience - total_cost

    -- Apply stat increases and track upgrades
    for stat_name, count in pairs(self.pending_upgrades) do
        -- Update the actual stat
        if stat_name == "Health" then
            self.player.max_health = self.player.max_health + count
        elseif stat_name == "Stamina" then
            self.player.max_stamina = self.player.max_stamina + count
        elseif stat_name == "Energy" then
            self.player.max_energy = self.player.max_energy + count
        elseif stat_name == "Defence" then
            self.player.defense = self.player.defense + count
        elseif stat_name == "Recovery" then
            self.player.recovery = self.player.recovery + count
        elseif stat_name == "Critical" then
            self.player.critical_chance = self.player.critical_chance + count
        end

        -- Track the upgrade count for potential refunds
        self.player.stat_upgrades[stat_name] = (self.player.stat_upgrades[stat_name] or 0) + count
    end

    -- Recompute level as sum of all stat upgrades
    local total_level = 0
    for _, v in pairs(self.player.stat_upgrades) do
        total_level = total_level + v
    end
    self.player.level = total_level

    -- Clear pending
    self:cancel_upgrades()
    return true
end

--- Cancel all pending upgrades
---@return nil
function status_panel:cancel_upgrades()
    self.pending_upgrades = {}
    self.pending_costs = {}
end

--- Build the stats rows for display (reuses cached tables to avoid allocations)
---@return table[] Array of {label, value, suffix, extra} pairs (value is nil for blank lines)
function status_panel:build_stats_rows()
    if not self.player then return self._cached_rows end

    local player = self.player
    local rows = self._cached_rows
    local total_pending_cost = self:get_total_pending_cost()
    local pending_level_ups = self:get_total_pending_upgrades()
    self._available_exp = player.experience - total_pending_cost

    local exp_suffix = total_pending_cost > 0 and "(-" .. total_pending_cost .. ")" or nil
    local level_suffix = pending_level_ups > 0 and "(+" .. pending_level_ups .. ")" or nil

    -- Row 1: Level
    rows[1].label = "Level"
    rows[1].value = tostring(player.level)
    rows[1].suffix = level_suffix
    rows[1].suffix_color = "#88FF88"
    rows[1].value_color = nil
    rows[1].monospace = nil

    -- Row 2: Experience
    rows[2].label = "Experience"
    rows[2].value = tostring(player.experience)
    rows[2].suffix = exp_suffix
    rows[2].suffix_color = "#FF8888"
    rows[2].value_color = self:can_level_up(self._available_exp) and "#88FF88" or nil
    rows[2].monospace = nil

    -- Row 3: Next Level
    local min_cost = self:get_min_upgrade_cost()
    rows[3].label = "Required XP"
    rows[3].value = min_cost and tostring(min_cost) or "MAX"
    rows[3].suffix = nil
    rows[3].suffix_color = nil
    rows[3].value_color = (min_cost and self._available_exp >= min_cost) and "#88FF88" or nil
    rows[3].monospace = nil

    -- Row 4: Gold
    rows[4].label = "Gold"
    rows[4].value = tostring(player.gold)
    rows[4].suffix = nil
    rows[4].suffix_color = nil
    rows[4].value_color = nil
    rows[4].monospace = nil

    -- Row 5: Blank
    rows[5].label = nil
    rows[5].value = nil
    rows[5].suffix = nil
    rows[5].suffix_color = nil
    rows[5].value_color = nil
    rows[5].monospace = nil

    -- Row 6: Health
    rows[6].label = "Health"
    rows[6].value = tostring(player.max_health)
    rows[6].suffix = get_stat_suffix(self, "Health")
    rows[6].suffix_color = "#88FF88"
    rows[6].value_color = nil
    rows[6].monospace = nil

    -- Row 7: Stamina
    rows[7].label = "Stamina"
    rows[7].value = tostring(player.max_stamina)
    rows[7].suffix = get_stat_suffix(self, "Stamina")
    rows[7].suffix_color = "#88FF88"
    rows[7].value_color = nil
    rows[7].monospace = nil

    -- Row 8: Energy
    rows[8].label = "Energy"
    rows[8].value = tostring(player.max_energy)
    rows[8].suffix = get_stat_suffix(self, "Energy")
    rows[8].suffix_color = "#88FF88"
    rows[8].value_color = nil
    rows[8].monospace = nil

    -- Row 9: Defence
    rows[9].label = "Defence"
    rows[9].value = string.format("%.1f%%", player:defense_percent())
    rows[9].suffix = get_percent_suffix(self, "Defence", player.defense)
    rows[9].suffix_color = "#88FF88"
    rows[9].value_color = nil
    rows[9].monospace = nil

    -- Row 10: Recovery
    rows[10].label = "Recovery"
    rows[10].value = string.format("%.1f%%", player:recovery_percent())
    rows[10].suffix = get_percent_suffix(self, "Recovery", player.recovery)
    rows[10].suffix_color = "#88FF88"
    rows[10].value_color = nil
    rows[10].monospace = nil

    -- Row 11: Critical
    rows[11].label = "Critical"
    rows[11].value = string.format("%.1f%%", player:critical_percent())
    rows[11].suffix = get_percent_suffix(self, "Critical", player.critical_chance)
    rows[11].suffix_color = "#88FF88"
    rows[11].value_color = nil
    rows[11].monospace = nil

    -- Row 12: Blank
    rows[12].label = nil
    rows[12].value = nil
    rows[12].suffix = nil
    rows[12].suffix_color = nil
    rows[12].value_color = nil
    rows[12].monospace = nil

    -- Row 13: Time
    rows[13].label = "Time"
    rows[13].value = SaveSlots.format_playtime(Playtime.get())
    rows[13].suffix = nil
    rows[13].suffix_color = nil
    rows[13].value_color = nil
    rows[13].monospace = true

    return rows
end

--- Get the effective selection index based on input mode
--- Mouse mode: only returns hovered_index (no fallback to keyboard selection)
--- Keyboard/gamepad mode: returns selected_index when panel is active
---@return number|nil index The effective row index, or nil if nothing selected
function status_panel:get_effective_index()
    if controls.is_mouse_active() then
        return self.hovered_index
    end
    return self.hovered_index or (self.active and self.selected_index)
end

--- Get the description for the currently selected or hovered stat/item
---@return string|nil Description text for the info panel, or nil if nothing selected/hovered
function status_panel:get_description()
    -- Check inventory first (if mouse is hovering or inventory is focused)
    local inv_desc = self:get_inventory_description()
    if inv_desc then
        return inv_desc
    end

    -- Fall back to stats description
    local index = self:get_effective_index()
    local selectable = index and self.selectable_rows[index]
    if selectable and selectable.label then
        return STAT_DESCRIPTIONS[selectable.label]
    end
    return nil
end

--- Get the currently highlighted stat label (hovered or selected)
---@return string|nil label The stat label, or nil if nothing highlighted
function status_panel:get_highlighted_stat()
    local index = self:get_effective_index()
    local selectable = index and self.selectable_rows[index]
    return selectable and selectable.label
end

--- Get the description for the currently hovered inventory item
---@return string|nil description Item name and description, or nil if nothing hovered
function status_panel:get_inventory_description()
    local item_id, _, is_stackable = self.inventory:get_hovered_item_info()
    if not item_id then
        return nil
    end

    -- Look up in appropriate registry
    local item_def = is_stackable and stackable_item_registry[item_id] or unique_item_registry[item_id]
    if not item_def then
        return nil
    end

    if item_def.description and item_def.description ~= "" then
        return item_def.name .. ": " .. item_def.description
    end
    return item_def.name
end

--- Check if the currently hovered inventory item is equipped
---@return boolean|string|nil is_equipped True if equipped, false if not, "usable" for usable items, nil if nothing hovered or item is no_equip/stackable
function status_panel:is_hovered_item_equipped()
    local item_id, _, is_stackable = self.inventory:get_hovered_item_info()
    if item_id then
        -- Don't show equip option for stackable items
        if is_stackable then
            return nil
        end
        local item_def = unique_item_registry[item_id]
        if item_def then
            if item_def.type == "no_equip" then return nil end
            if item_def.type == "usable" then return "usable" end
        end
        return self.inventory.equipped[item_id] == true
    end
    return nil
end

--- Check if the currently highlighted stat can be leveled up
---@return boolean is_levelable True if the stat can be leveled up
function status_panel:is_highlighted_levelable()
    return LEVELABLE_STATS[self:get_highlighted_stat()] == true
end

--- Get the cost to level up the currently highlighted stat
---@return number|nil cost The XP cost, or nil if not levelable or at cap
function status_panel:get_level_cost()
    if not self:is_highlighted_levelable() then
        return nil
    end
    local stat = self:get_highlighted_stat()
    local cost = self:get_next_upgrade_cost(stat)
    if cost == math.huge then return nil end
    return cost
end

--- Check if selection is from mouse hover on stats (vs keyboard/gamepad)
---@return boolean is_mouse True if currently hovering stats with mouse
function status_panel:is_mouse_hover()
    return self.hovered_index ~= nil
end

--- Check if any area (stats or inventory) has mouse hover
---@return boolean has_hover True if mouse is hovering over stats or inventory
function status_panel:has_any_mouse_hover()
    return self.hovered_index ~= nil or self.inventory.hovered_col ~= nil
end

--- Reset selection to first item
---@return nil
function status_panel:reset_selection()
    self.selected_index = 1
    self.focus_area = "stats"
    self.inventory.active = false
    self.inventory:reset_selection()
end

--- Check if inventory grid is currently focused
---@return boolean is_inventory_focused
function status_panel:is_inventory_focused()
    return self.focus_area == "inventory"
end

--- Switch focus back to stats from inventory
---@return nil
function status_panel:focus_stats()
    self.focus_area = "stats"
    self.inventory.active = false
end

--- Toggle equipped state for the currently hovered inventory item
---@return boolean toggled True if an item was toggled
function status_panel:toggle_hovered_equipped()
    local item_id, _, is_stackable = self.inventory:get_hovered_item_info()
    if item_id then
        self.inventory:toggle_equipped(item_id, is_stackable)
        return true
    end
    return false
end

--- Update the status panel with mouse hover detection
---@param dt number Delta time in seconds
---@param local_mx number Local mouse X coordinate (relative to panel)
---@param local_my number Local mouse Y coordinate (relative to panel)
---@param mouse_active boolean Whether mouse input is active
function status_panel:update(dt, local_mx, local_my, mouse_active)
    self.hovered_index = nil
    self.inventory.suppress_selection = false

    -- Update inventory grid position and hover
    local inv_x = self:get_inventory_x()
    local inv_y = TEXT_PADDING_TOP
    self.inventory.x = inv_x
    self.inventory.y = inv_y
    self.inventory:update(dt, local_mx - inv_x, local_my - inv_y, mouse_active)

    if not mouse_active then return end

    -- Check if mouse is over inventory cells (not header)
    local inv_width = self.inventory:get_width()
    local inv_cells_y = inv_y + self.inventory:get_cells_y_offset()
    local inv_cells_height = self.inventory:get_height() - self.inventory:get_cells_y_offset()
    local over_inventory = local_mx >= inv_x and local_mx < inv_x + inv_width and
                           local_my >= inv_cells_y and local_my < inv_cells_y + inv_cells_height

    if over_inventory then
        -- Mouse is over inventory cells, don't highlight stats
        return
    end

    -- Check if mouse is over a selectable row (stats area)
    -- Stats area ends where inventory begins
    local stats_right = inv_x
    local y_start = TEXT_PADDING_TOP
    for i, row_data in ipairs(self.selectable_rows) do
        local row_y = y_start + (row_data.visual_index - 1) * LINE_HEIGHT
        if local_my >= row_y and local_my < row_y + LINE_HEIGHT then
            if local_mx >= TEXT_PADDING_LEFT and local_mx < stats_right then
                self.hovered_index = i
                if self.active then
                    self.selected_index = i
                end
                -- Suppress inventory when stats has mouse hover
                self.inventory.suppress_selection = true
                break
            end
        end
    end
end

--- Get the X position for the inventory grid
---@return number x position relative to panel
function status_panel:get_inventory_x()
    return self.width - TEXT_PADDING_RIGHT - self.inventory:get_width()
end

-- Cached layout table for get_stats_layout (reused to avoid allocations)
local _cached_stats_layout = {
    x = TEXT_PADDING_LEFT,
    y = TEXT_PADDING_TOP,
    width = 0,
    bottom = TEXT_PADDING_TOP + STATS_ROW_COUNT * LINE_HEIGHT,
}

--- Get the stats area layout info for external button positioning
---@return table {x, y, width, bottom} Stats area dimensions
function status_panel:get_stats_layout()
    local inv_x = self:get_inventory_x()
    _cached_stats_layout.width = inv_x - TEXT_PADDING_LEFT
    return _cached_stats_layout
end

--- Handle keyboard/gamepad input for navigation
---@return nil
function status_panel:input()
    -- Handle navigation between stats and inventory
    if self.focus_area == "stats" then
        if controls.menu_up_pressed() then
            self.selected_index = self.selected_index - 1
            if self.selected_index < 1 then
                self.selected_index = #self.selectable_rows
            end
        elseif controls.menu_down_pressed() then
            self.selected_index = self.selected_index + 1
            if self.selected_index > #self.selectable_rows then
                self.selected_index = 1
            end
        elseif controls.menu_right_pressed() then
            -- Switch to inventory
            self.focus_area = "inventory"
            self.inventory.active = true
        end
    else
        -- Inventory is focused, delegate to inventory grid
        if controls.menu_left_pressed() and self.inventory.selected_col == 1 then
            -- At left edge of inventory, switch back to stats
            self.focus_area = "stats"
            self.inventory.active = false
        else
            self.inventory:input()
        end
    end
end

--- Draw the status panel
---@return nil
function status_panel:draw()
    nine_slice.draw(slice, self.x, self.y, self.width, self.height)

    canvas.save()

    local text_x = self.x + TEXT_PADDING_LEFT
    local text_y = self.y + TEXT_PADDING_TOP

    canvas.set_font_family("menu_font")
    canvas.set_font_size(8)
    canvas.set_text_baseline("top")

    local rows = self:build_stats_rows()

    -- Build selectable rows mapping (only rows with labels are selectable)
    -- Reuses pooled tables to avoid per-frame allocations
    local selectable_idx = 0
    for visual_index, row in ipairs(rows) do
        if row.label then
            selectable_idx = selectable_idx + 1
            local entry = self._selectable_pool[selectable_idx]
            entry.label = row.label
            entry.visual_index = visual_index
            self.selectable_rows[selectable_idx] = entry
        end
    end
    -- Clear any extra entries from previous frames
    for i = selectable_idx + 1, #self.selectable_rows do
        self.selectable_rows[i] = nil
    end

    -- Clamp selected index to valid range
    local row_count = #self.selectable_rows
    self.selected_index = math.max(1, math.min(self.selected_index, row_count))

    -- Get the visual index of the highlighted row (selected if active and focused on stats, or hovered)
    -- Don't highlight stats when inventory is focused or has mouse hover
    local highlighted_visual_index = nil
    local inventory_has_hover = self.inventory.hovered_col ~= nil
    if not inventory_has_hover then
        if self.active and self.focus_area == "stats" and self.selectable_rows[self.selected_index] then
            highlighted_visual_index = self.selectable_rows[self.selected_index].visual_index
        elseif self.hovered_index and self.selectable_rows[self.hovered_index] then
            highlighted_visual_index = self.selectable_rows[self.hovered_index].visual_index
        end
    end

    -- Compute label widths once (font must be active)
    if not self._max_label_width then
        self._max_label_width = 0
        for _, row in ipairs(rows) do
            if row.label then
                local label_width = canvas.get_text_width(row.label)
                if label_width > self._max_label_width then
                    self._max_label_width = label_width
                end
            end
        end
        self._char_width = canvas.get_text_width("0")
    end
    local max_label_width = self._max_label_width
    local max_value_width = self._char_width * 8  -- "00:00:00" = 8 characters

    -- Value column right edge: 20px gap after widest label, plus widest value
    local value_right_x = text_x + max_label_width + 20 + max_value_width

    -- Suffix column: to the right of values with small gap
    local suffix_gap = 4
    local suffix_x = value_right_x + suffix_gap

    local y_offset = 0

    for visual_index, row in ipairs(rows) do
        if row.label then
            local is_highlighted = (visual_index == highlighted_visual_index)
            local text_color = is_highlighted and "#FFFF00" or "#FFFFFF"

            canvas.set_color(text_color)

            -- Draw label left-aligned
            canvas.set_text_align("left")
            canvas.draw_text(text_x, text_y + y_offset, row.label)

            -- Use value_color if present and not highlighted
            local value_color = (not is_highlighted and row.value_color) or text_color
            canvas.set_color(value_color)

            if row.monospace then
                -- Draw each character individually with fixed spacing
                canvas.set_text_align("center")
                local str = row.value
                local start_x = value_right_x - (self._char_width * #str) + (self._char_width / 2)
                for i = 1, #str do
                    local char = str:sub(i, i)
                    canvas.draw_text(start_x + (i - 1) * self._char_width, text_y + y_offset, char)
                end
            else
                -- Draw value right-aligned within value column
                canvas.set_text_align("right")
                canvas.draw_text(value_right_x, text_y + y_offset, row.value)
            end

            -- Draw suffix if present (e.g., "(+1)" or "(-50)")
            if row.suffix then
                canvas.set_text_align("left")
                canvas.set_color(row.suffix_color or "#FFFFFF")
                canvas.draw_text(suffix_x, text_y + y_offset, row.suffix)
            end

            -- Draw per-stat up-arrow icon for affordable levelable stats
            if LEVELABLE_STATS[row.label] and self:can_afford_upgrade(row.label, self._available_exp) then
                local icon_size = 7
                local icon_x = suffix_x + (row.suffix and canvas.get_text_width(row.suffix) + 2 or 0)
                local icon_y = text_y + y_offset + (LINE_HEIGHT - icon_size) / 2
                canvas.draw_image(sprites.ui.level_up_icon, icon_x, icon_y, icon_size, icon_size)
            end
        end
        y_offset = y_offset + LINE_HEIGHT
    end

    -- Draw inventory grid on the right side
    local inv_x = self:get_inventory_x()
    local inv_y = TEXT_PADDING_TOP
    self.inventory.x = self.x + inv_x
    self.inventory.y = self.y + inv_y
    self.inventory:draw()

    canvas.restore()
end

return status_panel
