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
	zombie = {
		idle = "zombie_idle",
		run = "zombie_run",
		attack = "zombie_attack",
		hit = "zombie_hit",
		death = "zombie_death",
	},
	ghost_painting = {
		static = "ghost_painting_static",
		fly = "ghost_painting_fly",
		hit = "ghost_painting_hit",
		death = "ghost_painting_death",
	},
	magician = {
		sheet = "magician_sheet",
		projectile = "magician_projectile",
		projectile_hit = "magician_projectile_hit",
	},
	magician_blue = {
		sheet = "magician_blue_sheet",
		projectile = "magician_projectile_yellow",
		projectile_hit = "magician_projectile_yellow_hit",
	},
	magician_purple = {
		sheet = "magician_purple_sheet",
		projectile = "magician_projectile_green",
		projectile_hit = "magician_projectile_green_hit",
	},
	guardian = {
		idle = "guardian_idle",
		alert = "guardian_alert",
		attack = "guardian_attack",
		hit = "guardian_hit",
		death = "guardian_death",
		jump = "guardian_jump",
		land = "guardian_land",
		run = "guardian_run",
	},
	flaming_skull = {
		float = "flaming_skull_float",
		hit = "flaming_skull_hit",
		death = "flaming_skull_death",
	},
	blue_slime = {
		idle = "blue_slime_idle",
		jump = "blue_slime_jump",
		hit = "blue_slime_hit",
		death = "blue_slime_death",
	},
	red_slime = {
		idle = "red_slime_idle",
		jump = "red_slime_jump",
		hit = "red_slime_hit",
		death = "red_slime_death",
	},
	gnomo = {
		sheet = "gnomo_sheet",
	},
	gnomo_boss = {
		green = "gnomo_boss_green",
		blue = "gnomo_boss_blue",
		magenta = "gnomo_boss_magenta",
		red = "gnomo_boss_red",
	},
	shieldmaiden = {
		sheet = "shieldmaiden_sheet",
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

canvas.assets.load_image(enemies.zombie.idle, "sprites/enemies/zombie/zombie_idle.png")
canvas.assets.load_image(enemies.zombie.run, "sprites/enemies/zombie/zombie_run.png")
canvas.assets.load_image(enemies.zombie.attack, "sprites/enemies/zombie/zombie_attack.png")
canvas.assets.load_image(enemies.zombie.hit, "sprites/enemies/zombie/zombie_hit.png")
canvas.assets.load_image(enemies.zombie.death, "sprites/enemies/zombie/zombie_death.png")

canvas.assets.load_image(enemies.ghost_painting.static, "sprites/enemies/ghost_painting/ghost_painting.png")
canvas.assets.load_image(enemies.ghost_painting.fly, "sprites/enemies/ghost_painting/ghost_painting_fly.png")
canvas.assets.load_image(enemies.ghost_painting.hit, "sprites/enemies/ghost_painting/ghost_painting_hit.png")
canvas.assets.load_image(enemies.ghost_painting.death, "sprites/enemies/ghost_painting/ghost_painting_death.png")

canvas.assets.load_image(enemies.magician.sheet, "sprites/enemies/magician/magician_red.png")
canvas.assets.load_image(enemies.magician.projectile, "sprites/enemies/magician/magician_projectile.png")
canvas.assets.load_image(enemies.magician.projectile_hit, "sprites/enemies/magician/magician_projectile_hit.png")

canvas.assets.load_image(enemies.magician_blue.sheet, "sprites/enemies/magician/magician_blue.png")
canvas.assets.load_image(enemies.magician_blue.projectile, "sprites/enemies/magician/magician_projectile_yellow.png")
canvas.assets.load_image(enemies.magician_blue.projectile_hit, "sprites/enemies/magician/magician_projectile_yellow_hit.png")

canvas.assets.load_image(enemies.magician_purple.sheet, "sprites/enemies/magician/magician_purple.png")
canvas.assets.load_image(enemies.magician_purple.projectile, "sprites/enemies/magician/magician_projectile_green.png")
canvas.assets.load_image(enemies.magician_purple.projectile_hit, "sprites/enemies/magician/magician_projectile_green_hit.png")

canvas.assets.load_image(enemies.guardian.idle, "sprites/enemies/guardian/guardian_idle.png")
canvas.assets.load_image(enemies.guardian.alert, "sprites/enemies/guardian/guardian_alerted.png")
canvas.assets.load_image(enemies.guardian.attack, "sprites/enemies/guardian/guardian_attack.png")
canvas.assets.load_image(enemies.guardian.hit, "sprites/enemies/guardian/guardian_hit.png")
canvas.assets.load_image(enemies.guardian.death, "sprites/enemies/guardian/guardian_death.png")
canvas.assets.load_image(enemies.guardian.jump, "sprites/enemies/guardian/guardian_jump.png")
canvas.assets.load_image(enemies.guardian.land, "sprites/enemies/guardian/guardian_land.png")
canvas.assets.load_image(enemies.guardian.run, "sprites/enemies/guardian/guardian_run.png")

canvas.assets.load_image(enemies.flaming_skull.float, "sprites/enemies/flaming_skull/flaming_skull.png")
canvas.assets.load_image(enemies.flaming_skull.hit, "sprites/enemies/flaming_skull/flaming_skull_hit.png")
canvas.assets.load_image(enemies.flaming_skull.death, "sprites/enemies/flaming_skull/flaming_skull_death.png")

canvas.assets.load_image(enemies.blue_slime.idle, "sprites/enemies/blue_slime/blue_slime_idle.png")
canvas.assets.load_image(enemies.blue_slime.jump, "sprites/enemies/blue_slime/blue_slime_jump.png")
canvas.assets.load_image(enemies.blue_slime.hit, "sprites/enemies/blue_slime/blue_slime_hit.png")
canvas.assets.load_image(enemies.blue_slime.death, "sprites/enemies/blue_slime/blue_slime_death.png")

canvas.assets.load_image(enemies.red_slime.idle, "sprites/enemies/red_slime/red_slime_idle.png")
canvas.assets.load_image(enemies.red_slime.jump, "sprites/enemies/red_slime/red_slime_jump.png")
canvas.assets.load_image(enemies.red_slime.hit, "sprites/enemies/red_slime/red_slime_hit.png")
canvas.assets.load_image(enemies.red_slime.death, "sprites/enemies/red_slime/red_slime_death.png")

canvas.assets.load_image(enemies.gnomo.sheet, "sprites/enemies/gnomo/gnomo.png")

-- Gnomo boss variants (green reuses the original gnomo sheet)
canvas.assets.load_image(enemies.gnomo_boss.green, "sprites/enemies/gnomo/gnomo.png")
canvas.assets.load_image(enemies.gnomo_boss.blue, "sprites/enemies/gnomo/gnomo_blue.png")
canvas.assets.load_image(enemies.gnomo_boss.magenta, "sprites/enemies/gnomo/gnomo_magenta.png")
canvas.assets.load_image(enemies.gnomo_boss.red, "sprites/enemies/gnomo/gnomo_red.png")

canvas.assets.load_image(enemies.shieldmaiden.sheet, "sprites/enemies/shieldmaiden/shieldmaiden.png")

return enemies
