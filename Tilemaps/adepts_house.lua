return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  class = "",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = 24,
  height = 11,
  tilewidth = 16,
  tileheight = 16,
  nextlayerid = 8,
  nextobjectid = 23,
  properties = {},
  tilesets = {
    {
      name = "alchemy_room_tileset",
      firstgid = 1,
      filename = "alchemy_room_tileset.tsx"
    },
    {
      name = "idle",
      firstgid = 127,
      filename = "idle.tsx"
    },
    {
      name = "NPCS",
      firstgid = 133,
      filename = "NPCS.tsx",
      exportfilename = "NPCS.lua"
    },
    {
      name = "decorations",
      firstgid = 137,
      filename = "decorations.tsx",
      exportfilename = "decorations.lua"
    },
    {
      name = "spawns",
      firstgid = 183,
      filename = "spawns.tsx",
      exportfilename = "spawns.lua"
    },
    {
      name = "unique_items",
      firstgid = 202,
      filename = "unique_items.tsx",
      exportfilename = "unique_items.lua"
    },
    {
      name = "tileset_dungeon",
      firstgid = 218,
      filename = "tileset_dungeon.tsx",
      exportfilename = "tileset_dungeon.lua"
    }
  },
  layers = {
    {
      type = "imagelayer",
      image = "../assets/Tilesets/alchemy_room_bg_00.png",
      id = 2,
      name = "Background",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      repeatx = true,
      repeaty = true,
      properties = {}
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 7,
      name = "Camera",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {
        ["type"] = "camera_bounds"
      },
      objects = {
        {
          id = 15,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = -0.333333,
          width = 384,
          height = 176,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 19,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = -176,
          width = 384,
          height = 176,
          rotation = 0,
          visible = true,
          properties = {}
        }
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 24,
      height = 11,
      id = 1,
      name = "Walls / Platforms",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {
        ["type"] = "wall"
      },
      encoding = "lua",
      chunks = {
        {
          x = 0, y = -16, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,
            35, 35, 35, 35, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
            35, 35, 35, 35, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 30, 244, 235, 20, 21, 22, 0, 0, 0, 20, 21, 21,
            35, 35, 35, 35, 30, 0, 0, 34, 35, 36, 0, 0, 0, 48, 49, 18,
            35, 35, 35, 35, 30, 0, 0, 34, 35, 36, 0, 0, 0, 0, 0, 34,
            35, 35, 35, 35, 30, 0, 0, 48, 49, 50, 0, 0, 0, 0, 0, 48,
            35, 35, 35, 35, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 44, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21
          }
        },
        {
          x = 16, y = -16, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            18, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            32, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            46, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            49, 49, 49, 49, 18, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 32, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 32, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 32, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            22, 0, 0, 20, 46, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0
          }
        },
        {
          x = -16, y = 0, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 49,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 36, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 36, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 36, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 44, 21,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        },
        {
          x = 0, y = 0, width = 16, height = 16,
          data = {
            35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,
            35, 16, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49,
            35, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            49, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
            35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,
            35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,
            35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        },
        {
          x = 16, y = 0, width = 16, height = 16,
          data = {
            36, 0, 0, 34, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            50, 0, 0, 48, 49, 18, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 32, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 32, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 32, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 32, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 32, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            21, 21, 21, 21, 21, 46, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            35, 35, 35, 35, 35, 35, 35, 35, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        }
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 24,
      height = 11,
      id = 3,
      name = "Decorations",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "lua",
      chunks = {
        {
          x = 0, y = 0, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 42, 0, 0, 0, 0, 42, 0, 0, 0, 0, 42, 0,
            0, 0, 0, 0, 42, 0, 0, 0, 0, 42, 0, 0, 0, 0, 42, 0,
            0, 0, 0, 0, 42, 0, 0, 139, 0, 42, 0, 0, 0, 0, 42, 0,
            0, 0, 0, 0, 42, 81, 82, 0, 0, 42, 0, 0, 0, 0, 42, 0,
            0, 0, 0, 0, 56, 0, 0, 0, 0, 56, 0, 96, 97, 0, 56, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 118, 119, 120, 121, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        },
        {
          x = 16, y = 0, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            95, 95, 0, 56, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        }
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 24,
      height = 11,
      id = 5,
      name = "Decorations2",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "lua",
      chunks = {
        {
          x = 0, y = 0, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 142, 0, 79, 0, 0, 0, 0, 79, 0, 0, 0, 0, 79, 0,
            0, 0, 0, 0, 0, 0, 0, 76, 77, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 90, 91, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        },
        {
          x = 16, y = 0, width = 16, height = 16,
          data = {
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            143, 0, 0, 79, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 4,
      name = "Props",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      objects = {
        {
          id = 1,
          name = "",
          type = "",
          shape = "rectangle",
          x = 309.333,
          y = 111.333,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 127,
          visible = true,
          properties = {
            ["type"] = "spawn"
          }
        },
        {
          id = 2,
          name = "",
          type = "",
          shape = "rectangle",
          x = 144,
          y = 112,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 135,
          visible = true,
          properties = {
            ["flip"] = true,
            ["on_dialogue"] = "adept_house_dialogue"
          }
        },
        {
          id = 3,
          name = "",
          type = "",
          shape = "rectangle",
          x = 8,
          y = 80,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 152,
          visible = true,
          properties = {}
        },
        {
          id = 5,
          name = "",
          type = "",
          shape = "rectangle",
          x = 301,
          y = 112.667,
          width = 36,
          height = 16,
          rotation = 0,
          gid = 182,
          visible = true,
          properties = {
            ["text"] = "Move\n{keyboard:move_left}/{keyboard:move_right} or {gamepad:move_left}/{gamepad:move_right}"
          }
        },
        {
          id = 7,
          name = "",
          type = "",
          shape = "rectangle",
          x = 166,
          y = 112,
          width = 8,
          height = 16,
          rotation = 0,
          gid = 168,
          visible = true,
          properties = {}
        },
        {
          id = 8,
          name = "",
          type = "",
          shape = "rectangle",
          x = 211,
          y = 112,
          width = 8,
          height = 16,
          rotation = 0,
          gid = 2147483816,
          visible = true,
          properties = {}
        },
        {
          id = 18,
          name = "",
          type = "",
          shape = "rectangle",
          x = 80,
          y = 112,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 200,
          visible = true,
          properties = {
            ["gold"] = 20,
            ["item_id"] = "longsword",
            ["required_key"] = "adept_key"
          }
        },
        {
          id = 20,
          name = "",
          type = "",
          shape = "rectangle",
          x = 80,
          y = -16,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 217,
          visible = true,
          properties = {}
        },
        {
          id = 21,
          name = "",
          type = "",
          shape = "rectangle",
          x = 240,
          y = -128,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 200,
          visible = true,
          properties = {
            ["flip"] = true,
            ["gold"] = 200,
            ["id"] = "adepts_shield_chest",
            ["item_id"] = "adepts_shield",
            ["required_key"] = "gold_key"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 6,
      name = "Locations",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      objects = {
        {
          id = 10,
          name = "",
          type = "",
          shape = "rectangle",
          x = 301.667,
          y = 102.667,
          width = 34.6667,
          height = 7.66667,
          rotation = 0,
          visible = true,
          properties = {
            ["type"] = "one_way_platform"
          }
        },
        {
          id = 11,
          name = "",
          type = "",
          shape = "rectangle",
          x = 113,
          y = 80.3333,
          width = 29.6667,
          height = 9.66667,
          rotation = 0,
          visible = true,
          properties = {
            ["type"] = "one_way_platform"
          }
        },
        {
          id = 12,
          name = "",
          type = "",
          shape = "rectangle",
          x = 177.333,
          y = 104.667,
          width = 29,
          height = 8.33333,
          rotation = 0,
          visible = true,
          properties = {
            ["type"] = "one_way_platform"
          }
        },
        {
          id = 13,
          name = "",
          type = "",
          shape = "rectangle",
          x = 256.667,
          y = 97,
          width = 30.3333,
          height = 5.33333,
          rotation = 0,
          visible = true,
          properties = {
            ["type"] = "one_way_platform"
          }
        },
        {
          id = 14,
          name = "",
          type = "",
          shape = "rectangle",
          x = 80.3333,
          y = 88.6667,
          width = 31.3333,
          height = 6.33333,
          rotation = 0,
          visible = true,
          properties = {
            ["type"] = "one_way_platform"
          }
        },
        {
          id = 16,
          name = "",
          type = "",
          shape = "rectangle",
          x = -55,
          y = 31.6667,
          width = 46,
          height = 128,
          rotation = 0,
          visible = true,
          properties = {
            ["target_id"] = "adept_house_exit",
            ["target_map"] = "garden",
            ["type"] = "map_transition"
          }
        },
        {
          id = 17,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 96,
          width = 16,
          height = 16,
          rotation = 0,
          visible = true,
          properties = {
            ["id"] = "entrance"
          }
        }
      }
    }
  }
}
