local sprites = require('sprites')
local slime_common = require('Enemies/slime_common')

--- Blue Slime enemy: A bouncing slime that idles with slow wandering and jumps toward the player.
--- Passive variant - tends to move away from player when nearby.
--- States: idle (wander), prep_jump (squat), launch (jump up), falling (descent), landing (land), hit, knockback, death
--- Health: 2 HP. Contact damage: 1. XP: 2. Gold: 0-1.

return slime_common.create(sprites.enemies.blue_slime, {
	-- Movement
	wander_speed = 1.5,
	jump_horizontal_speed = 6,

	-- Jump physics
	jump_velocity_min = -14,
	jump_velocity_variance = 4,

	-- Timers
	idle_time_min = 0.5,
	idle_time_variance = 1.0,
	move_burst_min = 0.1,
	move_burst_variance = 0.15,
	pause_min = 0.1,
	pause_variance = 0.2,

	-- Detection
	player_near_range = 3,

	-- Behavior: passive - moves away when player is near
	near_move_toward_chance = 0.2,  -- 80% chance to move away when near
	far_move_toward_chance = 0.5,   -- 50% chance to move toward when far
	near_jump_chance = 0.7,         -- 70% jump chance when near
	far_jump_chance = 0.3,          -- 30% jump chance when far

	-- Animation
	prep_jump_ms = 300,  -- ~1.2s total (4 frames * 300ms)

	-- Stats
	max_health = 2,
	contact_damage = 1,

	-- Loot
	loot_xp = 2,
	loot_gold_min = 0,
	loot_gold_max = 1,

	-- Energy drops (0-5 particles at 0.1 each = 0-0.5 Energy)
	loot_energy_max = 5,
})
