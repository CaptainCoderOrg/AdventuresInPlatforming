return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  name = "tileset_dungeon",
  class = "",
  tilewidth = 16,
  tileheight = 16,
  spacing = 0,
  margin = 0,
  columns = 9,
  image = "../assets/Tilesets/tileset_dungeon.png",
  imagewidth = 144,
  imageheight = 112,
  objectalignment = "unspecified",
  tilerendersize = "tile",
  fillmode = "stretch",
  tileoffset = {
    x = 0,
    y = 0
  },
  grid = {
    orientation = "orthogonal",
    width = 16,
    height = 16
  },
  properties = {},
  wangsets = {
    {
      name = "Dungeon Platforms",
      class = "",
      tile = -1,
      wangsettype = "corner",
      properties = {},
      colors = {
        {
          color = { 255, 0, 0 },
          name = "Platform",
          class = "",
          probability = 1,
          tile = -1,
          properties = {}
        },
        {
          color = { 0, 255, 0 },
          name = "Not Platform",
          class = "",
          probability = 1,
          tile = -1,
          properties = {}
        }
      },
      wangtiles = {
        {
          wangid = { 0, 1, 0, 2, 0, 1, 0, 1 },
          tileid = 0
        },
        {
          wangid = { 0, 1, 0, 2, 0, 2, 0, 1 },
          tileid = 1
        },
        {
          wangid = { 0, 1, 0, 1, 0, 2, 0, 1 },
          tileid = 2
        },
        {
          wangid = { 0, 2, 0, 2, 0, 1, 0, 1 },
          tileid = 9
        },
        {
          wangid = { 0, 2, 0, 2, 0, 2, 0, 2 },
          tileid = 10
        },
        {
          wangid = { 0, 1, 0, 1, 0, 2, 0, 2 },
          tileid = 11
        },
        {
          wangid = { 0, 2, 0, 2, 0, 2, 0, 1 },
          tileid = 18
        },
        {
          wangid = { 0, 1, 0, 2, 0, 2, 0, 2 },
          tileid = 20
        },
        {
          wangid = { 0, 2, 0, 1, 0, 1, 0, 1 },
          tileid = 27
        },
        {
          wangid = { 0, 1, 0, 1, 0, 1, 0, 2 },
          tileid = 29
        },
        {
          wangid = { 0, 2, 0, 2, 0, 1, 0, 2 },
          tileid = 36
        },
        {
          wangid = { 0, 2, 0, 1, 0, 2, 0, 2 },
          tileid = 38
        },
        {
          wangid = { 0, 2, 0, 1, 0, 1, 0, 2 },
          tileid = 55
        }
      }
    }
  },
  tilecount = 63,
  tiles = {
    {
      id = 0,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 1,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 2,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 4,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 5,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 6,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 9,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 10,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 11,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 13,
      type = "wall"
    },
    {
      id = 15,
      type = "wall"
    },
    {
      id = 17,
      type = "bridge",
      properties = {
        ["type"] = "bridge"
      }
    },
    {
      id = 18,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 20,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 22,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 23,
      type = "wall"
    },
    {
      id = 24,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 26,
      type = "bridge",
      properties = {
        ["type"] = "bridge"
      }
    },
    {
      id = 27,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 29,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 35,
      type = "bridge",
      properties = {
        ["type"] = "bridge"
      }
    },
    {
      id = 36,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 38,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 45,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 47,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 54,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 55,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    },
    {
      id = 56,
      type = "wall",
      properties = {
        ["type"] = "wall"
      }
    }
  }
}
