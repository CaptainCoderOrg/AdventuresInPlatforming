local canvas = require("canvas")
local config = require("config")

local sprites = {}

sprites.tile_size = config.ui.TILE * config.ui.SCALE

canvas.assets.add_path("assets/")
sprites.HEART = "heart"
canvas.assets.load_image(sprites.HEART, "sprites/ui/heart.png")
canvas.assets.load_image("tilemap", "images/tilemap_packed.png")
local LADDER_TOP = "ladder_top"
local LADDER_MID = "ladder_mid"
local LADDER_BOTTOM = "ladder_bottom"
canvas.assets.load_image(LADDER_TOP, "sprites/environment/ladder_top.png")
canvas.assets.load_image(LADDER_MID, "sprites/environment/ladder_mid.png")
canvas.assets.load_image(LADDER_BOTTOM, "sprites/environment/ladder_bottom.png")

sprites.ui = {}
canvas.assets.load_image("dialogue_lg", "sprites/ui/dialogue-lg.png")
canvas.assets.load_image("slider", "sprites/ui/fillable-area.png")
canvas.assets.load_image("button", "sprites/ui/button.png")
sprites.ui.circle_ui = "circle_ui"
canvas.assets.load_image(sprites.circle_ui, "sprites/ui/circle_ui.png")
sprites.ui.small_circle_ui = "small_circle_ui"
canvas.assets.load_image(sprites.ui.small_circle_ui, "sprites/ui/small_circle_ui.png")

canvas.assets.load_image("player_block", "sprites/character/block.png")
canvas.assets.load_image("player_idle", "sprites/character/idle.png")
canvas.assets.load_image("player_run", "sprites/character/run.png")
canvas.assets.load_image("player_dash", "sprites/character/dash.png")
canvas.assets.load_image("player_fall", "sprites/character/fall.png")
canvas.assets.load_image("player_jump_up", "sprites/character/jump_up.png")
canvas.assets.load_image("player_double_jump", "sprites/character/double_jump.png")
canvas.assets.load_image("player_wall_slide", "sprites/character/wall_slide.png")
canvas.assets.load_image("player_turn", "sprites/character/turn.png")
canvas.assets.load_image("player_turn", "sprites/character/turn.png")
canvas.assets.load_image("player_death", "sprites/character/death.png")

canvas.assets.load_image("player_attack_0", "sprites/character/attack_0.png")
canvas.assets.load_image("player_attack_1", "sprites/character/attack_1.png")
canvas.assets.load_image("player_attack_2", "sprites/character/attack_2.png")
canvas.assets.load_image("player_attack_hammer", "sprites/character/attack_hammer.png")
canvas.assets.load_image("player_throw", "sprites/character/throw.png")

canvas.assets.load_image("player_climb_up", "sprites/character/climb_up.png")
canvas.assets.load_image("player_climb_down", "sprites/character/climb_down.png")

canvas.assets.load_image("player_hit", "sprites/character/hit.png")

sprites.AXE_SPRITE = "throwable_axe"
canvas.assets.load_image(sprites.AXE_SPRITE, "sprites/throwables/throwable_axe.png")
sprites.SHURIKEN_SPRITE = "shuriken"
canvas.assets.load_image(sprites.SHURIKEN_SPRITE, "sprites/throwables/shuriken.png")

canvas.assets.load_image("effect_hit", "sprites/effects/hit.png")
canvas.assets.load_image("shuriken_hit", "sprites/effects/shuriken_hit.png")

sprites.ratto = { 
	idle = "ratto_idle",
	run = "ratto_run",
	hit = "ratto_hit",
	death = "ratto_death",
}
canvas.assets.load_image(sprites.ratto.idle, "sprites/enemies/ratto/ratto_idle.png")
canvas.assets.load_image(sprites.ratto.run, "sprites/enemies/ratto/ratto_run.png")
canvas.assets.load_image(sprites.ratto.hit, "sprites/enemies/ratto/ratto_hit.png")
canvas.assets.load_image(sprites.ratto.death, "sprites/enemies/ratto/ratto_death.png")

sprites.worm = {
	run = "worm_run",
	death = "worm_death",
}
canvas.assets.load_image(sprites.worm.run, "sprites/enemies/worm/worm_run.png")
canvas.assets.load_image(sprites.worm.death, "sprites/enemies/worm/worm_death.png")

sprites.spikeslug = {
	run = "spikeslug_run",
	hit = "spikeslug_hit",
	defense = "spikeslug_defense",
	stop_defend = "spikeslug_stop_defend",
	death = "spikeslug_death",
}
canvas.assets.load_image(sprites.spikeslug.run, "sprites/enemies/spike_slug/spikeslug_run.png")
canvas.assets.load_image(sprites.spikeslug.hit, "sprites/enemies/spike_slug/spikeslug_hit.png")
canvas.assets.load_image(sprites.spikeslug.defense, "sprites/enemies/spike_slug/spikeslug_defense.png")
canvas.assets.load_image(sprites.spikeslug.stop_defend, "sprites/enemies/spike_slug/spikeslug_stop_defend.png")
canvas.assets.load_image(sprites.spikeslug.death, "sprites/enemies/spike_slug/spikeslug_death.png")

function sprites.draw_ladder(dx, dy, sprite)
	if sprite == nil then sprite = LADDER_MID end
	canvas.draw_image(sprite, dx, dy, config.ui.TILE * config.ui.SCALE, config.ui.TILE * config.ui.SCALE)
end

function sprites.draw_tile(tx, ty, dx, dy)
	canvas.draw_image(
		"tilemap",
		dx,
		dy,
		config.ui.TILE * config.ui.SCALE,
		config.ui.TILE * config.ui.SCALE, -- destination: x, y, width, height
		tx * config.ui.TILE,
		ty * config.ui.TILE,
		config.ui.TILE,
		config.ui.TILE -- source: x, y, width, height
	)
end

return sprites
