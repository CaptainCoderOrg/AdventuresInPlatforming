local canvas = require("canvas")

--- Player sprite asset keys.
---@type table<string, string>
local player = {
	block = "player_block",
	block_step = "player_block_step",
	idle = "player_idle",
	run = "player_run",
	dash = "player_dash",
	fall = "player_fall",
	jump_up = "player_jump_up",
	double_jump = "player_double_jump",
	wall_slide = "player_wall_slide",
	turn = "player_turn",
	death = "player_death",
	attack_0 = "player_attack_0",
	attack_1 = "player_attack_1",
	attack_2 = "player_attack_2",
	attack_hammer = "player_attack_hammer",
	throw = "player_throw",
	climb_up = "player_climb_up",
	climb_down = "player_climb_down",
	hit = "player_hit",
	rest = "player_rest",
	stairs_up = "player_stairs_up",
	stairs_down = "player_stairs_down",
}

canvas.assets.load_image(player.block, "sprites/character/block.png")
canvas.assets.load_image(player.block_step, "sprites/character/block-step.png")
canvas.assets.load_image(player.idle, "sprites/character/idle.png")
canvas.assets.load_image(player.run, "sprites/character/run.png")
canvas.assets.load_image(player.dash, "sprites/character/dash.png")
canvas.assets.load_image(player.fall, "sprites/character/fall.png")
canvas.assets.load_image(player.jump_up, "sprites/character/jump_up.png")
canvas.assets.load_image(player.double_jump, "sprites/character/double_jump.png")
canvas.assets.load_image(player.wall_slide, "sprites/character/wall_slide.png")
canvas.assets.load_image(player.turn, "sprites/character/turn.png")
canvas.assets.load_image(player.death, "sprites/character/death.png")
canvas.assets.load_image(player.attack_0, "sprites/character/attack_0.png")
canvas.assets.load_image(player.attack_1, "sprites/character/attack_1.png")
canvas.assets.load_image(player.attack_2, "sprites/character/attack_2.png")
canvas.assets.load_image(player.attack_hammer, "sprites/character/attack_hammer.png")
canvas.assets.load_image(player.throw, "sprites/character/throw.png")
canvas.assets.load_image(player.climb_up, "sprites/character/climb_up.png")
canvas.assets.load_image(player.climb_down, "sprites/character/climb_down.png")
canvas.assets.load_image(player.hit, "sprites/character/hit.png")
canvas.assets.load_image(player.rest, "sprites/character/rest.png")
canvas.assets.load_image(player.stairs_up, "sprites/character/stairs_up.png")
canvas.assets.load_image(player.stairs_down, "sprites/character/stairs_down.png")

return player
