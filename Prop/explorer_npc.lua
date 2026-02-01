--- Explorer NPC prop definition - Interactable NPC
local sprites = require("sprites")
local npc_common = require("Prop/npc_common")

return npc_common.create({
    sprite = sprites.npcs.explorer_idle,
    frame_count = 5,
    ms_per_frame = 150,
    width = 16,
    height = 16,
    dialogue = "The dungeon lies ahead...",
})
