--- Witch NPC prop definition - Interactable merchant NPC
local sprites = require("sprites")
local npc_common = require("Prop/npc_common")

return npc_common.create({
    sprite = sprites.npcs.witch_merchant_idle,
    frame_count = 10,
    ms_per_frame = 100,
    width = 32,
    height = 32,
    box_size = 2,
    draw_width = 2,
    dialogue = "Hello, traveler!",
})
