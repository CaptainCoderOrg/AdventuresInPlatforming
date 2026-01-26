local canvas = require("canvas")

--- Enemy sprite asset keys organized by enemy type.
---@type table<string, table<string, string>>
local enemies = {
	ratto = {
		idle = "ratto_idle",
		run = "ratto_run",
		hit = "ratto_hit",
		death = "ratto_death",
	},
	worm = {
		run = "worm_run",
		death = "worm_death",
	},
	spikeslug = {
		run = "spikeslug_run",
		hit = "spikeslug_hit",
		defense = "spikeslug_defense",
		stop_defend = "spikeslug_stop_defend",
		death = "spikeslug_death",
	},
	bat_eye = {
		idle = "bateye_idle",
		alert = "bateye_alert",
		attack_start = "bateye_attack_start",
		attack = "bateye_attack",
		attack_recovery = "bateye_attack_recovery",
		hit = "bateye_hit",
		death = "bateye_death",
	},
}

canvas.assets.load_image(enemies.ratto.idle, "sprites/enemies/ratto/ratto_idle.png")
canvas.assets.load_image(enemies.ratto.run, "sprites/enemies/ratto/ratto_run.png")
canvas.assets.load_image(enemies.ratto.hit, "sprites/enemies/ratto/ratto_hit.png")
canvas.assets.load_image(enemies.ratto.death, "sprites/enemies/ratto/ratto_death.png")

canvas.assets.load_image(enemies.worm.run, "sprites/enemies/worm/worm_run.png")
canvas.assets.load_image(enemies.worm.death, "sprites/enemies/worm/worm_death.png")

canvas.assets.load_image(enemies.spikeslug.run, "sprites/enemies/spike_slug/spikeslug_run.png")
canvas.assets.load_image(enemies.spikeslug.hit, "sprites/enemies/spike_slug/spikeslug_hit.png")
canvas.assets.load_image(enemies.spikeslug.defense, "sprites/enemies/spike_slug/spikeslug_defense.png")
canvas.assets.load_image(enemies.spikeslug.stop_defend, "sprites/enemies/spike_slug/spikeslug_stop_defend.png")
canvas.assets.load_image(enemies.spikeslug.death, "sprites/enemies/spike_slug/spikeslug_death.png")

canvas.assets.load_image(enemies.bat_eye.idle, "sprites/enemies/bat_eye/bateye_idle.png")
canvas.assets.load_image(enemies.bat_eye.alert, "sprites/enemies/bat_eye/bateye_alert.png")
canvas.assets.load_image(enemies.bat_eye.attack_start, "sprites/enemies/bat_eye/bateye_attack_start.png")
canvas.assets.load_image(enemies.bat_eye.attack, "sprites/enemies/bat_eye/bateye_attack.png")
canvas.assets.load_image(enemies.bat_eye.attack_recovery, "sprites/enemies/bat_eye/bateye_attack_recovery.png")
canvas.assets.load_image(enemies.bat_eye.hit, "sprites/enemies/bat_eye/bateye_hit.png")
canvas.assets.load_image(enemies.bat_eye.death, "sprites/enemies/bat_eye/bateye_death.png")

return enemies
