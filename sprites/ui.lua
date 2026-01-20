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
	ability_selector_left = "ability_selector_left",
	meter_background = "meter_background",
	meter_shine = "meter_shine",
	meter_cap_red = "meter_cap_red",
	meter_cap_green = "meter_cap_green",
	meter_cap_blue = "meter_cap_blue",
}

canvas.assets.load_image(ui.heart, "sprites/ui/heart.png")
canvas.assets.load_image(ui.dialogue_lg, "sprites/ui/dialogue-lg.png")
canvas.assets.load_image(ui.slider, "sprites/ui/fillable-area.png")
canvas.assets.load_image(ui.button, "sprites/ui/button.png")
canvas.assets.load_image(ui.circle_ui, "sprites/ui/circle_ui.png")
canvas.assets.load_image(ui.small_circle_ui, "sprites/ui/small_circle_ui.png")
canvas.assets.load_image(ui.simple_dialogue, "sprites/ui/simple-dialogue.png")
canvas.assets.load_image(ui.ability_selector_left, "sprites/ui/ability_selector_left.png")
canvas.assets.load_image(ui.meter_background, "sprites/ui/meter-background-slice.png")
canvas.assets.load_image(ui.meter_shine, "sprites/ui/meter-shine-slice.png")
canvas.assets.load_image(ui.meter_cap_red, "sprites/ui/meter-cap-red.png")
canvas.assets.load_image(ui.meter_cap_green, "sprites/ui/meter-cap-green.png")
canvas.assets.load_image(ui.meter_cap_blue, "sprites/ui/meter-cap-blue.png")

return ui
