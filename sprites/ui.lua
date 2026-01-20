local canvas = require("canvas")

--- UI sprite asset keys.
---@type table<string, string>
local ui = {
	heart = "heart",
	dialogue_lg = "dialogue_lg",
	slider = "slider",
	button = "button",
	circle_ui = "circle_ui",
	small_circle_ui = "small_circle_ui",
	simple_dialogue = "simple_dialogue",
}

canvas.assets.load_image(ui.heart, "sprites/ui/heart.png")
canvas.assets.load_image(ui.dialogue_lg, "sprites/ui/dialogue-lg.png")
canvas.assets.load_image(ui.slider, "sprites/ui/fillable-area.png")
canvas.assets.load_image(ui.button, "sprites/ui/button.png")
canvas.assets.load_image(ui.circle_ui, "sprites/ui/circle_ui.png")
canvas.assets.load_image(ui.small_circle_ui, "sprites/ui/small_circle_ui.png")
canvas.assets.load_image(ui.simple_dialogue, "sprites/ui/simple-dialogue.png")

return ui
