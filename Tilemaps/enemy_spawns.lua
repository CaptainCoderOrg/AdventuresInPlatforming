return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  name = "enemy_spawns",
  class = "",
  tilewidth = 48,
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
  tilecount = 9,
  tiles = {
    {
      id = 0,
      properties = {
        ["key"] = "guardian",
        ["offset_x"] = -1,
        ["offset_y"] = 1,
        ["type"] = "enemy"
      },
      image = "enemies/guardian.png",
      width = 48,
      height = 32
    },
    {
      id = 1,
      properties = {
        ["key"] = "magician",
        ["type"] = "enemy"
      },
      image = "enemies/magician.png",
      width = 16,
      height = 16
    },
    {
      id = 2,
      properties = {
        ["key"] = "ratto",
        ["offset_x"] = 0,
        ["offset_y"] = 0.5,
        ["type"] = "enemy"
      },
      image = "enemies/ratto.png",
      width = 16,
      height = 8
    },
    {
      id = 3,
      properties = {
        ["key"] = "spike_slug",
        ["offset_x"] = 0,
        ["offset_y"] = 0,
        ["type"] = "enemy"
      },
      image = "enemies/spikeslig.png",
      width = 16,
      height = 16
    },
    {
      id = 4,
      properties = {
        ["key"] = "worm",
        ["offset_x"] = 0,
        ["offset_y"] = 0,
        ["type"] = "enemy"
      },
      image = "enemies/worm.png",
      width = 16,
      height = 8
    },
    {
      id = 5,
      properties = {
        ["key"] = "zombie",
        ["type"] = "enemy"
      },
      image = "enemies/zombie.png",
      width = 16,
      height = 16
    },
    {
      id = 6,
      properties = {
        ["key"] = "bat_eye",
        ["type"] = "enemy"
      },
      image = "enemies/bateye.png",
      width = 16,
      height = 16
    },
    {
      id = 7,
      properties = {
        ["key"] = "ghost_painting",
        ["offset_y"] = 0,
        ["type"] = "enemy"
      },
      image = "enemies/ghost_painting.png",
      width = 16,
      height = 24
    },
    {
      id = 8,
      properties = {
        ["key"] = "flaming_skull",
        ["offset_y"] = 0,
        ["speed"] = 5,
        ["type"] = "enemy"
      },
      image = "../assets/sprites/enemies/flaming_skull/flaming_skull.png",
      x = 0,
      y = 0,
      width = 18,
      height = 26
    }
  }
}
