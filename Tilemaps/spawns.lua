return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  name = "spawns",
  class = "",
  tilewidth = 32,
  tileheight = 32,
  spacing = 0,
  margin = 0,
  columns = 0,
  objectalignment = "unspecified",
  tilerendersize = "tile",
  fillmode = "stretch",
  tileoffset = {
    x = 0,
    y = 0
  },
  grid = {
    orientation = "orthogonal",
    width = 1,
    height = 1
  },
  properties = {},
  wangsets = {},
  tilecount = 18,
  tiles = {
    {
      id = 1,
      properties = {
        ["flip"] = true,
        ["gold"] = 5,
        ["type"] = "chest"
      },
      image = "objects/brown_chest.png",
      width = 16,
      height = 16
    },
    {
      id = 17,
      properties = {
        ["flip"] = false,
        ["gold"] = 5,
        ["type"] = "chest"
      },
      image = "objects/brown_chest_no_flip.png",
      width = 16,
      height = 16
    },
    {
      id = 2,
      properties = {
        ["type"] = "button"
      },
      image = "objects/button.png",
      width = 16,
      height = 16
    },
    {
      id = 3,
      properties = {
        ["type"] = "campfire"
      },
      image = "objects/campfire.png",
      width = 16,
      height = 16
    },
    {
      id = 4,
      properties = {
        ["type"] = "unique_item"
      },
      image = "objects/gold_key_spin.png",
      width = 16,
      height = 16
    },
    {
      id = 5,
      properties = {
        ["type"] = "ladder"
      },
      image = "objects/ladder_bottom.png",
      width = 16,
      height = 16
    },
    {
      id = 6,
      properties = {
        ["type"] = "ladder"
      },
      image = "objects/ladder_mid.png",
      width = 16,
      height = 16
    },
    {
      id = 7,
      properties = {
        ["type"] = "ladder"
      },
      image = "objects/ladder_top.png",
      width = 16,
      height = 16
    },
    {
      id = 8,
      properties = {
        ["type"] = "lever"
      },
      image = "objects/lever.png",
      width = 16,
      height = 16
    },
    {
      id = 9,
      properties = {
        ["type"] = "locked_door"
      },
      image = "objects/locked_door.png",
      width = 16,
      height = 32
    },
    {
      id = 10,
      properties = {
        ["type"] = "pressure_plate"
      },
      image = "objects/pressure_plate.png",
      width = 32,
      height = 16
    },
    {
      id = 11,
      properties = {
        ["text"] = "Undefined",
        ["type"] = "sign"
      },
      image = "../assets/sprites/environment/sign.png",
      width = 16,
      height = 16
    },
    {
      id = 12,
      properties = {
        ["type"] = "speark_trap"
      },
      image = "objects/spear_trap.png",
      width = 16,
      height = 16
    },
    {
      id = 13,
      properties = {
        ["type"] = "spike_trap"
      },
      image = "objects/spikes-retract.png",
      width = 16,
      height = 16
    },
    {
      id = 14,
      properties = {
        ["type"] = "stairs"
      },
      image = "objects/stairs_up.png",
      width = 32,
      height = 32
    },
    {
      id = 15,
      properties = {
        ["type"] = "trap_door"
      },
      image = "objects/trap_door.png",
      width = 32,
      height = 16
    },
    {
      id = 16,
      properties = {
        ["offset_y"] = 0,
        ["type"] = "decoy_painting"
      },
      image = "enemies/ghost_painting.png",
      width = 16,
      height = 24
    },
    {
      id = 18,
      properties = {
        ["state"] = "open",
        ["type"] = "boss_door"
      },
      image = "../assets/sprites/environment/boss_door.png",
      x = 0,
      y = 0,
      width = 32,
      height = 32
    }
  }
}
