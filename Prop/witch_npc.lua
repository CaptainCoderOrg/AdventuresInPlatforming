--- Zabarbra the Witch NPC - Custom prop with dialogue-driven interaction
--- First meeting gives Minor Healing. Subsequent visits offer equipment upgrades.
local Animation = require("Animation")
local TextDisplay = require("TextDisplay")
local common = require("Prop/common")
local sprites = require("sprites")
local dialogue_screen = require("ui/dialogue_screen")
local pickup_dialogue = require("ui/pickup_dialogue")
local npc_common = require("Prop/npc_common")

local animation_def = Animation.create_definition(sprites.npcs.witch_merchant_idle, 10, {
    ms_per_frame = 100,
    width = 32,
    height = 32,
    loop = true,
})

local BOX_SIZE = 2
local DRAW_WIDTH = 2

return {
    box = { x = -1, y = 0, w = BOX_SIZE + 2, h = BOX_SIZE },
    debug_color = "#FF00FF",

    ---@param prop table The prop instance
    ---@param _player table The player instance (unused - refs come from npc_common)
    ---@return boolean True to indicate interaction was handled
    interact = function(prop, _player)
        local player_ref = prop._player_ref
        local camera_ref = npc_common.get_camera()
        if not player_ref or not camera_ref then return false end

        -- Start dialogue first, then set on_close callback
        -- (start() clears on_close_callback, so it must be set after)
        -- Skip the greeting router: go directly to introduction or hub
        local met = player_ref.dialogue_flags and player_ref.dialogue_flags.met_zabarbra
        local start_node = met and "hub" or "introduction"
        dialogue_screen.start("zabarbra", player_ref, camera_ref, start_node)
        dialogue_screen.set_on_close(function(saved_player, saved_camera, saved_original_y)
            if not saved_player then return end

            -- First meeting: show pickup dialogue for Minor Healing
            if saved_player.dialogue_flags and saved_player.dialogue_flags.met_zabarbra then
                local has_healing = false
                for _, uid in ipairs(saved_player.unique_items or {}) do
                    if uid == "minor_healing" then has_healing = true; break end
                end
                if not has_healing then
                    pickup_dialogue.show("minor_healing", saved_player)
                    return
                end
            end

            -- Check for open_upgrades flag (keep_camera option held camera in place)
            if saved_player.dialogue_flags and saved_player.dialogue_flags.open_upgrades then
                saved_player.dialogue_flags.open_upgrades = nil
                local upgrade_screen = require("ui/upgrade_screen")
                upgrade_screen.start(saved_player, saved_camera, saved_original_y)
            end
        end)
        return true
    end,

    ---@param prop table The prop instance being spawned
    ---@param _def table The definition (unused)
    ---@param _options table Spawn options from Tiled
    on_spawn = function(prop, _def, _options)
        prop.animation = Animation.new(animation_def)
        prop.text_display = TextDisplay.new("Talk\n{move_up}", { anchor = "top" })
        prop._gave_healing = false
    end,

    ---@param prop table Prop instance
    ---@param dt number Delta time in seconds
    ---@param player table Player instance for proximity check
    update = function(prop, dt, player)
        -- Cache player ref for interact() (npc_common refs may not be set yet)
        prop._player_ref = player
        local is_active = common.player_touching(prop, player)
        local in_dialogue = dialogue_screen.is_active()
        local upgrade_screen = require("ui/upgrade_screen")
        local in_overlay = in_dialogue or upgrade_screen.is_active()
        prop.text_display:update(dt, is_active and not in_overlay)
    end,

    ---@param prop table Prop instance
    draw = function(prop)
        common.draw(prop)
        prop.text_display:draw(prop.x, prop.y, DRAW_WIDTH)
    end,
}
