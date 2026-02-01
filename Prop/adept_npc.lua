--- Adept NPC prop definition - Interactable NPC
local sprites = require("sprites")
local npc_common = require("Prop/npc_common")

return npc_common.create({
    sprite = sprites.npcs.adept_reading,
    frame_count = 6,
    ms_per_frame = 200,
    width = 16,
    height = 16,
    dialogue = "Knowledge is power...",
})
