--- Inventory grid component for displaying items in a 5x3 grid
local canvas = require("canvas")
local sprites = require("sprites")
local controls = require("controls")
local unique_item_registry = require("Prop.unique_item_registry")
local stackable_item_registry = require("Prop.stackable_item_registry")
local weapon_sync = require("player.weapon_sync")
local utils = require("ui/utils")

local inventory_grid = {}
inventory_grid.__index = inventory_grid

-- Grid configuration
local CELL_SIZE = 24
local CELL_SPACING = 1
local COLS = 5
local ROWS = 3
local SELECTION_ALPHA = 0.3

-- Sprite frame positions (24px frames, no spacing in sprite sheet)
local FRAME_BACKGROUND_X = 0
local FRAME_SELECTION_X = 24

-- Equipped indicator configuration
local EQUIPPED_MARGIN = 3

-- Header configuration
local HEADER_HEIGHT = 12
local HEADER_FONT_SIZE = 9
local HEADER_TEXT = "Inventory"

-- Note: weapons allow multiple equipped (quick swap system)
-- Note: secondary (including shield/dash) handled via ability_slots component

--- Create a new inventory grid
---@param opts {x: number, y: number, items: table, equipped: table, player: table|nil}
---@return table inventory_grid
function inventory_grid.create(opts)
    local self = setmetatable({}, inventory_grid)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.items = opts.items or {}
    self.equipped = opts.equipped or {}
    self.stackable = {}  -- item_id -> count for stackable items
    self.display_list = {}  -- Combined list: {item_id, count, is_stackable}
    self.player = opts.player
    self.selected_col = 1
    self.selected_row = 1
    self.hovered_col = nil
    self.hovered_row = nil
    self.active = false
    self.on_use_item = nil  -- Callback for usable items: fn(item_id)
    self.on_equip_secondary = nil  -- Callback for secondary equip: fn(item_id)
    return self
end

--- Get the total width of the grid in pixels
---@return number width
function inventory_grid:get_width()
    return COLS * CELL_SIZE + (COLS - 1) * CELL_SPACING
end

--- Get the total height of the grid in pixels (includes header)
---@return number height
function inventory_grid:get_height()
    return HEADER_HEIGHT + ROWS * CELL_SIZE + (ROWS - 1) * CELL_SPACING
end

--- Get the Y offset where cells start (after header)
---@return number offset
function inventory_grid:get_cells_y_offset()
    return HEADER_HEIGHT
end

--- Set the items reference
---@param items table Array of item_id strings
function inventory_grid:set_items(items)
    self.items = items or {}
    self:build_display_list()
end

--- Set the stackable items reference
---@param stackable table Map of item_id -> count
function inventory_grid:set_stackable(stackable)
    self.stackable = stackable or {}
    self:build_display_list()
end

--- Set the equipped reference and optional player for syncing
---@param equipped table Set of equipped item_ids
---@param player table|nil Player reference for weapon_sync
function inventory_grid:set_equipped(equipped, player)
    self.equipped = equipped or {}
    self.player = player
end

--- Check if an item is assigned to an ability slot
---@param item_id string
---@return boolean
function inventory_grid:is_in_ability_slot(item_id)
    if not self.player or not self.player.ability_slots then return false end
    for i = 1, controls.ABILITY_SLOT_COUNT do
        if self.player.ability_slots[i] == item_id then return true end
    end
    return false
end

--- Build the unified display list combining unique and stackable items
--- Unique items come first, followed by stackable items
--- Items assigned to ability slots are excluded
--- Reuses existing entry tables to avoid per-call allocations
function inventory_grid:build_display_list()
    local list = self.display_list
    local idx = 0

    -- Add unique items first (skip items in ability slots)
    for _, item_id in ipairs(self.items) do
        if not self:is_in_ability_slot(item_id) then
            idx = idx + 1
            local entry = list[idx]
            if not entry then
                entry = {}
                list[idx] = entry
            end
            entry.item_id = item_id
            entry.count = 1
            entry.is_stackable = false
        end
    end

    -- Add stackable items
    for item_id, count in pairs(self.stackable) do
        if count > 0 then
            idx = idx + 1
            local entry = list[idx]
            if not entry then
                entry = {}
                list[idx] = entry
            end
            entry.item_id = item_id
            entry.count = count
            entry.is_stackable = true
        end
    end

    -- Clear stale entries from previous builds
    for i = idx + 1, #list do list[i] = nil end
end

--- Get item at grid position
---@param col number Column (1-indexed)
---@param row number Row (1-indexed)
---@return string|nil item_id, number|nil count, boolean|nil is_stackable
function inventory_grid:get_item_at(col, row)
    local slot_index = (row - 1) * COLS + col
    local entry = self.display_list[slot_index]
    if entry then
        return entry.item_id, entry.count, entry.is_stackable
    end
    return nil, nil, nil
end

--- Get the currently selected or hovered item based on input mode
--- Mouse mode: only returns hovered item (no fallback to keyboard selection)
--- Keyboard/gamepad mode: returns keyboard selection when grid is active
---@return string|nil item_id
function inventory_grid:get_hovered_item()
    local item_id = self:get_hovered_item_info()
    return item_id
end

--- Get full info for the currently selected or hovered item based on input mode
---@return string|nil item_id, number|nil count, boolean|nil is_stackable
function inventory_grid:get_hovered_item_info()
    if self.hovered_col and self.hovered_row then
        return self:get_item_at(self.hovered_col, self.hovered_row)
    end
    if controls.is_mouse_active() then
        return nil, nil, nil
    end
    if self.active then
        return self:get_item_at(self.selected_col, self.selected_row)
    end
    return nil, nil, nil
end

--- Toggle equipped state for an item
--- Weapons can stack (multiple equipped), with active_weapon tracking which is in use
--- Secondaries delegate to ability slot assignment flow via on_equip_secondary callback
--- Items with type "no_equip" cannot be equipped
--- Stackable items cannot be equipped
---@param item_id string The item to toggle
---@param is_stackable boolean|nil Whether this is a stackable item
function inventory_grid:toggle_equipped(item_id, is_stackable)
    if not item_id then return end

    -- Prevent equipping stackable items
    if is_stackable then return end

    -- Get the item's type
    local item_def = unique_item_registry[item_id]
    local item_type = item_def and item_def.type

    -- Prevent equipping no_equip items
    if item_type == "no_equip" then return end

    -- Usable items trigger callback instead of equipping
    if item_type == "usable" then
        if self.on_use_item then self.on_use_item(item_id) end
        return
    end

    -- If already equipped, unequip
    if self.equipped[item_id] then
        self.equipped[item_id] = nil

        -- For secondaries, also clear from ability_slots
        if item_type == "secondary" and self.player and self.player.ability_slots then
            for i = 1, controls.ABILITY_SLOT_COUNT do
                if self.player.ability_slots[i] == item_id then
                    self.player.ability_slots[i] = nil
                end
            end
        end

        -- Sync player ability flags with equipment
        if self.player then
            weapon_sync.sync(self.player)
        end
        return
    end

    -- For secondary items, delegate to callback (ability slot assignment flow)
    if item_type == "secondary" then
        if self.on_equip_secondary then
            self.on_equip_secondary(item_id)
        end
        return
    end

    -- Equip the item
    self.equipped[item_id] = true

    -- Equipping a weapon makes it the active weapon immediately
    if item_type == "weapon" and self.player then
        self.player.active_weapon = item_id
    end

    -- Sync player ability flags with equipment
    if self.player then
        weapon_sync.sync(self.player)
    end
end

--- Reset selection to first cell
---@return nil
function inventory_grid:reset_selection()
    self.selected_col = 1
    self.selected_row = 1
end

local wrap = utils.wrap

--- Handle keyboard/gamepad input
---@return boolean consumed True if input was consumed
function inventory_grid:input()
    if not self.active then return false end

    local consumed = false

    if controls.menu_up_pressed() then
        self.selected_row = wrap(self.selected_row, -1, ROWS)
        consumed = true
    elseif controls.menu_down_pressed() then
        self.selected_row = wrap(self.selected_row, 1, ROWS)
        consumed = true
    end

    if controls.menu_left_pressed() then
        self.selected_col = wrap(self.selected_col, -1, COLS)
        consumed = true
    elseif controls.menu_right_pressed() then
        self.selected_col = wrap(self.selected_col, 1, COLS)
        consumed = true
    end

    if controls.menu_confirm_pressed() then
        local item_id, _, is_stackable = self:get_hovered_item_info()
        if item_id then
            self:toggle_equipped(item_id, is_stackable)
            consumed = true
        end
    end

    return consumed
end

--- Update the grid with mouse hover detection
---@param _ number Delta time (unused, for API consistency)
---@param local_mx number Local mouse X (relative to grid)
---@param local_my number Local mouse Y (relative to grid)
---@param mouse_active boolean Whether mouse input is active
function inventory_grid:update(_, local_mx, local_my, mouse_active)
    self.hovered_col = nil
    self.hovered_row = nil

    if not mouse_active then return end

    -- Offset mouse Y by header height
    local cell_my = local_my - HEADER_HEIGHT

    -- Check each cell for hover
    for row = 1, ROWS do
        for col = 1, COLS do
            local cx = (col - 1) * (CELL_SIZE + CELL_SPACING)
            local cy = (row - 1) * (CELL_SIZE + CELL_SPACING)

            if local_mx >= cx and local_mx < cx + CELL_SIZE and
               cell_my >= cy and cell_my < cy + CELL_SIZE then
                self.hovered_col = col
                self.hovered_row = row
                if self.active then
                    self.selected_col = col
                    self.selected_row = row
                end
                return
            end
        end
    end
end

--- Check if a cell is selected (keyboard) or hovered (mouse) based on input mode
--- Mouse mode: only returns true for hovered cell
--- Keyboard/gamepad mode: returns true for keyboard selection when grid is active
---@param col number Column to check
---@param row number Row to check
---@return boolean is_selected
function inventory_grid:is_cell_selected(col, row)
    if self.suppress_selection then
        return false
    end
    local is_hovered = self.hovered_col == col and self.hovered_row == row
    if controls.is_mouse_active() then
        return is_hovered
    end
    local is_keyboard_selected = self.active and self.selected_col == col and self.selected_row == row
    return is_hovered or is_keyboard_selected
end

--- Draw the inventory grid
---@return nil
function inventory_grid:draw()
    local sprite = sprites.ui.inventory_cell

    canvas.save()
    canvas.set_font_family("menu_font")

    -- Draw header text
    canvas.set_font_size(HEADER_FONT_SIZE)
    canvas.set_text_align("left")
    canvas.set_text_baseline("top")
    canvas.set_color("#AAAAAA")
    canvas.draw_text(self.x, self.y, HEADER_TEXT)

    -- Set up font for equipped indicators (used inside loop)
    canvas.set_font_size(7)
    canvas.set_text_align("right")
    canvas.set_text_baseline("bottom")

    -- Draw cells (offset by header)
    local cells_y = self.y + HEADER_HEIGHT

    for row = 1, ROWS do
        for col = 1, COLS do
            local cx = self.x + (col - 1) * (CELL_SIZE + CELL_SPACING)
            local cy = cells_y + (row - 1) * (CELL_SIZE + CELL_SPACING)

            -- 1. Draw cell background (frame 1)
            canvas.draw_image(sprite, cx, cy, CELL_SIZE, CELL_SIZE,
                FRAME_BACKGROUND_X, 0, CELL_SIZE, CELL_SIZE)

            -- 2. Draw item if present
            local item_id, count, is_stackable = self:get_item_at(col, row)
            if item_id then
                -- Look up in appropriate registry
                local item_def = is_stackable and stackable_item_registry[item_id] or unique_item_registry[item_id]
                if item_def then
                    -- Center 16px item in 24px cell
                    local item_size = 16
                    local offset = (CELL_SIZE - item_size) / 2
                    local draw_x = cx + offset
                    local draw_y = cy + offset

                    if item_def.static_sprite then
                        -- Static items: draw the whole sprite
                        canvas.draw_image(item_def.static_sprite, draw_x, draw_y, item_size, item_size)
                    elseif item_def.animated_sprite then
                        -- Animated items: draw only the first frame (16x16)
                        canvas.draw_image(item_def.animated_sprite, draw_x, draw_y, item_size, item_size,
                            0, 0, item_size, item_size)
                    end

                    -- 3. Draw "E" if equipped (unique items only)
                    if not is_stackable and self.equipped[item_id] then
                        canvas.set_color("#FFFFFF")
                        canvas.draw_text(cx + CELL_SIZE - EQUIPPED_MARGIN, cy + CELL_SIZE - EQUIPPED_MARGIN, "E")
                    end

                    -- 4. Draw count for stackable items with count > 1
                    if is_stackable and count and count > 1 then
                        canvas.set_color("#FFFFFF")
                        canvas.draw_text(cx + CELL_SIZE - EQUIPPED_MARGIN, cy + CELL_SIZE - EQUIPPED_MARGIN, tostring(count))
                    end
                end
            end

            -- 5. Draw selection overlay if selected/hovered (frame 2)
            if self:is_cell_selected(col, row) then
                canvas.set_global_alpha(SELECTION_ALPHA)
                canvas.draw_image(sprite, cx, cy, CELL_SIZE, CELL_SIZE,
                    FRAME_SELECTION_X, 0, CELL_SIZE, CELL_SIZE)
                canvas.set_global_alpha(1)
            end
        end
    end

    canvas.restore()
end

return inventory_grid
