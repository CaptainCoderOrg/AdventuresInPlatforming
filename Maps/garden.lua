--- Garden map event handlers
--- Contains interaction handlers for interactable props in the garden level
local audio = require("audio")
local Effects = require("Effects")

local garden = {}

--- Handler for opening the cottage door (transitions to adepts_house)
---@param context table Contains player and prop references
function garden.on_open_cottage(context)
    context.player.map_transition_target = {
        map = "adepts_house",
        spawn_id = "entrance",
    }
end

--- Handler for attempting to open the dungeon door (currently locked)
---@param context table Contains player and prop references
function garden.on_open_dungeon(context)
    Effects.create_locked_text(context.player.x + 0.5, context.player.y - 1, context.player)
    audio.play_sfx(audio.locked_door)
end

--- Handler for examining the dead tree
---@param context table Contains player and prop references
function garden.on_dead_tree(context)
    Effects.create_hover_text(context.player, "This tree has been dead for a long time.", 3, 3, "dead_tree", 1)
end

return garden
