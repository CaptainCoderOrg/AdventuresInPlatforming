local Prop = require("Prop")

return {
    id = "level1",
    background = "library_bg",  -- Key from sprites.environment (e.g., dungeon_bg, garden_bg)
    map = {

        [[########################################################################################################]],
        [[#######################################                                                              ###]],
        [[#######################################                                                              ###]],
        [[#######################################                                                              ###]],
        [[#  +                                  D                                                            K ###]],
        [[#         G          L            6Wl                                                            [######]],
        [[######################%%%%%%%%%%%H########H                                                      [######]],
        [[######################           H########H                  s                 bB    ! *    *    [######]],
        [[######################           H########H               T ###HT T T T T T T ##########################]],
        [[######################           H########H            T    ###H              ##########################]],
        [[######################           H########H    c C  T       ###H^^$||$^^$||$^^$||$$A####################]],
        [[######################&&&&&&&&&&&H###########  ####       R ############################################]],
        [[#############################################  #########################################################]],
        [[#############################################  #########################################################]],
        [[#                ##                  # 9      0#########################################################]],
        [[#                ##                  #H#   #############################################################]],
        [[#                ##                  #H#   #############################################################]],
        [[#                ##                  #H#   #############################################################]],
        [[#                ##                7 #H#   #############################################################]],
        [[#                ##     W  6   W#### #H#   #############################################################]],
        [[#                ## 5 ######   #//// #H#   #############################################################]],
        [[#                ##---######---#//// #H#   #############################################################]],
        [[#                ##   ######   #//// 8H    #############################################################]],
        [[#                ##   ######   #//// ###################################################################]],
        [[#                ##---######---#//// ###################################################################]],
        [[#              3 ##   ######   #//// ###################################################################]],
        [[#             #--##   ######   #//// ###################################################################]],
        [[#            ##  ##---######---#//// ###################################################################]],
        [[# S         ###       ######         ###################################################################]],
        [[# 1      2 ####     4 ###### 4   A   ###################################################################]],
        [[########################################################################################################]],
        [[########################################################################################################]],
        [[########################################################################################################]],
    },
    symbols = {
        ["D"] = { type = "locked_door", required_key = "gold_key" },
        ["*"] = {
            type = "pressure_plate",
            on_pressed = function()
                Prop.group_action("spear_trigger", "fire")
            end
        },
        ["["] = { type = "spear_trap", auto_fire = false, group = "spear_trigger", flip = true },
        ["!"] = { type = "sign", text = "Shield\n{block}" },
        [">"] = { type = "spear_trap", fire_delay = 2.0, cooldown_time = 0.5 },
        ["<"] = { type = "spear_trap", fire_delay = 2.0, cooldown_time = 0.5, flip = true },
        S = { type = "spawn" },
        B = {
            type = "button",
            on_press = function()
                Prop.group_action("entrance_spikes", "set_alternating")
                Prop.group_action("offset_spikes", "set_alternating")
                Prop.group_action("drop_spikes", "disable")
                Prop.group_action("spike_buttons", "pressed")
            end,
            group = "spike_buttons"
        },
        b = { type = "sign", text = "Hammer\nAssign to an ability slot to use" },
        R = { type = "enemy", key = "ratto", offset = { y = 0.5 } },
        W = { type = "enemy", key = "worm" },
        G = { type = "enemy", key = "spike_slug" },
        C = { type = "campfire", name = "Tutorial Campfire" },
        c = { type = "sign", text = "Campfires restore health\nand save progress" },
        s = { type = "sign", text = "[color=#FF0000]DANGER![/color]\nSpikes" },
        ["^"] = { type = "spike_trap", mode = "extended", group = "entrance_spikes", extend_time = 1, retract_time = 3 },
        ["|"] = { type = "spike_trap", mode = "extended", group = "offset_spikes", extend_time = 1, retract_time = 3, alternating_offset = 2 },
        ["$"] = { type = "spike_trap", mode = "extended", group = "drop_spikes" },
        ["Z"] = { type = "sign", text = "Tutorial Complete!\nThanks for playing!" },
        ["1"] = { type = "sign", text = "Move\n{keyboard:move_left}/{keyboard:move_right} or {gamepad:move_left}/{gamepad:move_right}" },
        ["2"] = { type = "sign", text = "Jump\n{jump}" },
        ["3"] = { type = "sign", text = "Drop\n{move_down} + {jump}", offset = { x = 0.5 } },
        ["4"] = { type = "sign", text = "Double Jump\n{jump} + {jump}" },
        ["5"] = { type = "sign", text = "Attack\n{attack}" },
        ["6"] = { type = "sign", text = "Ability: {ability_1}" },
        ["7"] = { type = "sign", text = "Wall Slide\nHold {move_right}" },
        ["8"] = { type = "sign", text = "Climb\n{move_up}" },
        ["9"] = { type = "sign", text = "Dash\n{dash}" },
        ["0"] = { type = "sign", text = "Wall Jump\n{move_right} + {jump}", offset = { x = -0.5 } },
        T = { type = "trap_door" },
        l = { type = "sign", text = "Abilities\n{ability_1} {ability_2} {ability_3} {ability_4}" },
        ["&"] = { type = "spike_trap", mode = "extended", group = "lever_spikes" },
        ["%"] = { type = "appearing_bridge", group = "lever_bridge" },
        L = {
            type = "lever",
            on_left = function()
                Prop.group_action("lever_spikes", "extending")
                Prop.group_action("lever_bridge", "disappear")
            end,
            on_right = function()
                Prop.group_action("lever_spikes", "retracting")
                Prop.group_action("lever_bridge", "appear")
            end
        },
        A = { type = "chest", gold = 20, flip = true },
        K = { type = "unique_item", item_id = "gold_key" },
        ["+"] = {
            type = "stairs",
            variant = "up",
            target_level = "level2",
            target_spawn = "+"
        },
    }
} 