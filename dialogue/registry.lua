--- Static registry of dialogue trees
--- All dialogue trees must be statically required here (no dynamic requires)
local registry = {}

-- Static requires for all dialogue trees
registry.adept_house_dialogue = require("dialogue/trees/adept_house_dialogue")
registry.gnomo_apology = require("dialogue/trees/gnomo_apology")
registry.zabarbra = require("dialogue/trees/zabarbra")
registry.valkyrie_apology = require("dialogue/trees/valkyrie_apology")

--- Get a dialogue tree by ID
---@param tree_id string Dialogue tree identifier
---@return table|nil tree Dialogue tree or nil if not found
function registry.get(tree_id)
    return registry[tree_id]
end

return registry
