--- Ability slots component for displaying 6 horizontal ability slots
local canvas = require("canvas")
local sprites = require("sprites")
local controls = require("controls")
local unique_item_registry = require("Prop.unique_item_registry")
local control_icon = require("ui.control_icon")
local utils = require("ui/utils")

local ability_slots = {}
ability_slots.__index = ability_slots

-- Grid configuration
local SLOT_COUNT = controls.ABILITY_SLOT_COUNT
local CELL_SIZE = 20
local CELL_SPACING = 1
local SELECTION_ALPHA = 0.3

-- Sprite frame positions (24px source frames, drawn at CELL_SIZE)
local SPRITE_SIZE = 24
local FRAME_BACKGROUND_X = 0
local FRAME_SELECTION_X = 24

-- Header configuration
local HEADER_HEIGHT = 12
local HEADER_FONT_SIZE = 9
local HEADER_TEXT = "Abilities"

-- Assignment mode header
local ASSIGN_HEADER_TEXT = "Assign to Slot"

-- Keybind icon configuration
local ICON_SIZE = 8
local ICON_MARGIN = 2
local ABILITY_ACTION_IDS = controls.ABILITY_ACTION_IDS

--- Create a new ability slots component
---@param opts {x: number, y: number, player: table|nil}
---@return table ability_slots
function ability_slots.create(opts)
    local self = setmetatable({}, ability_slots)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.player = opts.player
    self.selected_slot = 1
    self.hovered_slot = nil
    self.active = false
    -- Assignment mode state
    self.assigning = false
    self.assign_item_id = nil
    return self
end

--- Get the total width of the slots in pixels
---@return number width
function ability_slots:get_width()
    return SLOT_COUNT * CELL_SIZE + (SLOT_COUNT - 1) * CELL_SPACING
end

--- Get the total height including header
---@return number height
function ability_slots:get_height()
    return HEADER_HEIGHT + CELL_SIZE
end

--- Set the player reference
---@param player table|nil Player instance
function ability_slots:set_player(player)
    self.player = player
end

--- Enter assignment mode: pre-selects first empty slot (or slot 1 if all full)
---@param item_id string The secondary item to assign
function ability_slots:begin_assign(item_id)
    self.assigning = true
    self.assign_item_id = item_id
    -- Pre-select first empty slot
    self.selected_slot = 1
    if self.player and self.player.ability_slots then
        for i = 1, SLOT_COUNT do
            if not self.player.ability_slots[i] then
                self.selected_slot = i
                break
            end
        end
    end
end

--- Confirm assignment to the selected slot.
--- Returns the displaced item_id if the slot was occupied, or nil.
---@return string|nil displaced_item_id Item that was in the slot before, or nil
function ability_slots:confirm_assign()
    if not self.assigning or not self.assign_item_id or not self.player then
        self:cancel_assign()
        return nil
    end
    local slot = self.selected_slot
    local displaced = self.player.ability_slots[slot]
    self.player.ability_slots[slot] = self.assign_item_id
    self.assigning = false
    self.assign_item_id = nil
    return displaced
end

--- Cancel assignment mode
---@return nil
function ability_slots:cancel_assign()
    self.assigning = false
    self.assign_item_id = nil
end

--- Unequip the item in a slot, returning the removed item_id
---@param slot number Slot index (1-6)
---@return string|nil item_id The removed item, or nil if slot was empty
function ability_slots:unequip_slot(slot)
    if not self.player or not self.player.ability_slots then return nil end
    local item_id = self.player.ability_slots[slot]
    self.player.ability_slots[slot] = nil
    return item_id
end

--- Reset selection to first slot
---@return nil
function ability_slots:reset_selection()
    self.selected_slot = 1
end

local wrap = utils.wrap

--- Handle keyboard/gamepad input
---@return boolean consumed True if input was consumed
function ability_slots:input()
    if not self.active then return false end

    local consumed = false

    if controls.menu_left_pressed() then
        self.selected_slot = wrap(self.selected_slot, -1, SLOT_COUNT)
        consumed = true
    elseif controls.menu_right_pressed() then
        self.selected_slot = wrap(self.selected_slot, 1, SLOT_COUNT)
        consumed = true
    end

    return consumed
end

--- Update with mouse hover detection
---@param _ number Delta time (unused)
---@param local_mx number Local mouse X (relative to component)
---@param local_my number Local mouse Y (relative to component)
---@param mouse_active boolean Whether mouse input is active
function ability_slots:update(_, local_mx, local_my, mouse_active)
    self.hovered_slot = nil

    if not mouse_active then return end

    local cell_my = local_my - HEADER_HEIGHT

    for slot = 1, SLOT_COUNT do
        local cx = (slot - 1) * (CELL_SIZE + CELL_SPACING)
        if local_mx >= cx and local_mx < cx + CELL_SIZE and
           cell_my >= 0 and cell_my < CELL_SIZE then
            self.hovered_slot = slot
            if self.active then
                self.selected_slot = slot
            end
            return
        end
    end
end

--- Check if a slot is selected (keyboard) or hovered (mouse)
---@param slot number Slot to check
---@return boolean is_selected
function ability_slots:is_slot_selected(slot)
    local is_hovered = self.hovered_slot == slot
    if controls.is_mouse_active() then
        return is_hovered
    end
    local is_keyboard_selected = self.active and self.selected_slot == slot
    return is_hovered or is_keyboard_selected
end

--- Get the currently selected or hovered slot's item_id
---@return string|nil item_id
function ability_slots:get_hovered_item()
    local slot = nil
    if self.hovered_slot then
        slot = self.hovered_slot
    elseif not controls.is_mouse_active() and self.active then
        slot = self.selected_slot
    end
    if not slot or not self.player or not self.player.ability_slots then return nil end
    return self.player.ability_slots[slot]
end

--- Get the effective selected slot index
---@return number|nil slot
function ability_slots:get_effective_slot()
    if self.hovered_slot then
        return self.hovered_slot
    end
    if not controls.is_mouse_active() and self.active then
        return self.selected_slot
    end
    return nil
end

--- Draw the ability slots
---@return nil
function ability_slots:draw()
    local sprite = sprites.ui.inventory_cell

    canvas.save()
    canvas.set_font_family("menu_font")

    -- Draw header
    canvas.set_font_size(HEADER_FONT_SIZE)
    canvas.set_text_align("left")
    canvas.set_text_baseline("top")
    if self.assigning then
        canvas.set_color("#FFFF00")
        canvas.draw_text(self.x, self.y, ASSIGN_HEADER_TEXT)
    else
        canvas.set_color("#AAAAAA")
        canvas.draw_text(self.x, self.y, HEADER_TEXT)
    end

    local cells_y = self.y + HEADER_HEIGHT

    for slot = 1, SLOT_COUNT do
        local cx = self.x + (slot - 1) * (CELL_SIZE + CELL_SPACING)
        local cy = cells_y

        -- Draw cell background
        canvas.draw_image(sprite, cx, cy, CELL_SIZE, CELL_SIZE,
            FRAME_BACKGROUND_X, 0, SPRITE_SIZE, SPRITE_SIZE)

        -- Draw item if slot is populated
        local item_id = self.player and self.player.ability_slots and self.player.ability_slots[slot]
        if item_id then
            local item_def = unique_item_registry[item_id]
            if item_def then
                local item_size = 16
                local offset = (CELL_SIZE - item_size) / 2
                local draw_x = cx + offset
                local draw_y = cy + offset

                if item_def.static_sprite then
                    canvas.draw_image(item_def.static_sprite, draw_x, draw_y, item_size, item_size)
                elseif item_def.animated_sprite then
                    canvas.draw_image(item_def.animated_sprite, draw_x, draw_y, item_size, item_size,
                        0, 0, item_size, item_size)
                end
            end
        end

        -- Draw keybind icon in the bottom-right corner
        local icon_x = cx + CELL_SIZE - ICON_SIZE - ICON_MARGIN
        local icon_y = cy + CELL_SIZE - ICON_SIZE - ICON_MARGIN
        if not item_id then
            canvas.set_global_alpha(0.4)
        end
        control_icon.draw(ABILITY_ACTION_IDS[slot], icon_x, icon_y, ICON_SIZE)
        if not item_id then
            canvas.set_global_alpha(1)
        end

        -- Draw selection overlay
        if self:is_slot_selected(slot) then
            canvas.set_global_alpha(SELECTION_ALPHA)
            canvas.draw_image(sprite, cx, cy, CELL_SIZE, CELL_SIZE,
                FRAME_SELECTION_X, 0, SPRITE_SIZE, SPRITE_SIZE)
            canvas.set_global_alpha(1)
        end
    end

    canvas.restore()
end

return ability_slots
