local Prop = require("Prop")

return {
    map = {
        [[#X#################################################]],
        [[#  S                                              #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[#                                                 #]],
        [[# C B                               Bb     s      #]],
        [[#####^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^####^^^^##  ####]],
        [[#############################################  ####]],
        [[#############################################  ####]],
        [[#                ##               #### 9      0####]],
        [[#                ##               ####H#   ########]],
        [[#                ##               ####H#   ########]],
        [[#                ##             7 ####H#   ########]],
        [[#                ##             # ####H#   ########]],
        [[#                ##     W  6  W## ####H#   ########]],
        [[#                ## 5 ######  #// ####H#   ########]],
        [[#                ##---######--#// ####H#   ########]],
        [[#                ##   ######  #//    8H    ########]],
        [[#                ##   ######  #// #################]],
        [[#                ##---######--#// #################]],
        [[#             3  ##   ######  #// #################]],
        [[#             #--##   ######  #// #################]],
        [[#            ##  ##---######--#// #################]],
        [[#           ###       ######  #// #################]],
        [[# 1      2 ####     4 ######      #################]],
        [[###################################################]],
    },
    symbols = {
        S = { type = "spawn" },
        B = {
            type = "button",
            on_press = function()
                Prop.group_action("entrance_spikes", "retracting")
                Prop.group_action("spike_buttons", "pressed")
            end,
            group = "spike_buttons"
        },
        b = { type = "sign", text = "Hammer\n{hammer}" },
        R = { type = "enemy", key = "ratto" },
        W = { type = "enemy", key = "worm" },
        G = { type = "enemy", key = "spike_slug" },
        C = { type = "campfire" },
        ["^"] = { type = "spike_trap", mode = "extended", group = "entrance_spikes" },
        s = { type = "sign", text = "WARNING!\nSpikes", offset = { x = 0.5 } },
        ["1"] = { type = "sign", text = "Move\n{keyboard:move_left}/{keyboard:move_right} or {gamepad:move_left}/{gamepad:move_right}" },
        ["2"] = { type = "sign", text = "Jump\n{jump}" },
        ["3"] = { type = "sign", text = "Drop\n{move_down} + {jump}" },
        ["4"] = { type = "sign", text = "Double Jump\n{jump} + {jump}" },
        ["5"] = { type = "sign", text = "Attack\n{attack}" },
        ["6"] = { type = "sign", text = "Throw: {throw}" },
        ["7"] = { type = "sign", text = "Wall Slide\nHold {move_right}" },
        ["8"] = { type = "sign", text = "Climb\n{move_up}" },
        ["9"] = { type = "sign", text = "Dash\n{dash}" },
        ["0"] = { type = "sign", text = "Wall Jump\n{move_right} + {jump}", offset = { x = -0.5 } },
    }
} 