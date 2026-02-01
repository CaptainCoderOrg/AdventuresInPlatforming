return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.11.2",
  class = "",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = 24,
  height = 14,
  tilewidth = 16,
  tileheight = 16,
  nextlayerid = 6,
  nextobjectid = 11,
  properties = {
    ["id"] = "shop"
  },
  tilesets = {
    {
      name = "tileset_witch_shop",
      firstgid = 1,
      filename = "tileset_witch_shop.tsx",
      exportfilename = "tileset_witch_shop.lua"
    },
    {
      name = "tileset_garden",
      firstgid = 226,
      filename = "tileset_garden.tsx",
      exportfilename = "tileset_garden.lua"
    },
    {
      name = "idle",
      firstgid = 358,
      filename = "idle.tsx"
    },
    {
      name = "NPCS",
      firstgid = 364,
      filename = "NPCS.tsx",
      exportfilename = "NPCS.lua"
    }
  },
  layers = {
    {
      type = "imagelayer",
      image = "../assets/Tilesets/bg_00_witch_shop.png",
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
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 24,
      height = 14,
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
      data = {
        17, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 19,
        32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        182, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 49,
        238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238,
        238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238,
        238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 3,
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
          name = "Start",
          type = "",
          shape = "rectangle",
          x = 32,
          y = 160,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 358,
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
          x = 64.3333,
          y = 160,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 364,
          visible = true,
          properties = {
            ["type"] = "witch_npc"
          }
        },
        {
          id = 3,
          name = "",
          type = "",
          shape = "rectangle",
          x = 144,
          y = 160,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 365,
          visible = true,
          properties = {}
        },
        {
          id = 4,
          name = "",
          type = "",
          shape = "rectangle",
          x = 224,
          y = 160,
          width = 16,
          height = 16,
          rotation = 0,
          gid = 366,
          visible = true,
          properties = {}
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 5,
      name = "Triggers",
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
          id = 5,
          name = "",
          type = "",
          shape = "rectangle",
          x = -46,
          y = 80,
          width = 46,
          height = 128,
          rotation = 0,
          visible = true,
          properties = {
            ["target_id"] = "shop_exit",
            ["target_map"] = "garden",
            ["type"] = "map_transition"
          }
        },
        {
          id = 10,
          name = "",
          type = "",
          shape = "rectangle",
          x = 8.5,
          y = 144.5,
          width = 16,
          height = 16,
          rotation = 0,
          visible = true,
          properties = {
            ["id"] = "enter_shop"
          }
        }
      }
    }
  }
}
