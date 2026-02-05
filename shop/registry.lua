--- Static registry of shop inventories
--- All shop inventories must be statically required here (no dynamic requires)
local registry = {}

-- Static requires for all shop inventories
registry.witch_shop = require("shop/inventories/witch_shop")

--- Get a shop inventory by ID
---@param shop_id string Shop identifier
---@return table|nil inventory Shop inventory or nil if not found
function registry.get(shop_id)
    return registry[shop_id]
end

return registry
