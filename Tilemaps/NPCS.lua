return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  name = "NPCS",
  class = "",
  tilewidth = 64,
  tileheight = 64,
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
  tilecount = 4,
  tiles = {
    {
      id = 0,
      properties = {
        ["type"] = "witch_merchant"
      },
      image = "npcs/witch_merchant_static.png",
      width = 32,
      height = 32
    },
    {
      id = 1,
      properties = {
        ["type"] = "explorer_npc"
      },
      image = "npcs/explorer1.png",
      width = 16,
      height = 16
    },
    {
      id = 2,
      properties = {
        ["type"] = "adept_npc"
      },
      image = "npcs/adept2.png",
      width = 16,
      height = 16
    },
    {
      id = 3,
      image = "../assets/Tilesets/house_00.png",
      width = 64,
      height = 64
    }
  }
}
