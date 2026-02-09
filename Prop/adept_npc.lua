--- Adept NPC prop definition - Interactable NPC
--- Dialogue tree specified via Tiled property: on_dialogue
--- Triggers credits screen when show_credits flag is set after dialogue closes
local sprites = require("sprites")
local npc_common = require("Prop/npc_common")
local hud = require("ui/hud")

return npc_common.create({
    sprite = sprites.npcs.adept_reading,
    frame_count = 6,
    ms_per_frame = 200,
    width = 16,
    height = 16,
    dialogue = "Knowledge is power...",  -- Fallback if no on_dialogue property
    on_dialogue_close = function(player)
        if player and player.dialogue_flags and player.dialogue_flags.show_credits then
            player.dialogue_flags.show_credits = nil
            hud.show_credits_screen()
        end
    end,
})
