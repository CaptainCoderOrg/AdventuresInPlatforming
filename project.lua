return {
  name = "Demo Game",
  main = "main.lua",
  type = "canvas",
  canvas = {
    width = 512,
    height = 512,
    background_color = "#000000",
    scale = "full",  -- "full" | "fit" | "1x"
  },
  -- Export settings
  export = {
    -- true: embed all assets as data URLs in a single HTML file (works offline)
    -- false: create ZIP with separate assets folder (smaller file size)
    singleFile = true,
  },
  -- Uncomment to include asset directories:
  assets = { "assets/" },
}
