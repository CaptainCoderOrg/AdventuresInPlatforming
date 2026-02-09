local sprites = require('sprites')
local slime_common = require('Enemies/slime_common')

--- Red Slime enemy: An aggressive bouncing slime that pursues the player.
--- Aggressive variant - more HP, moves toward player, jumps more often.
--- States: idle (wander), prep_jump (squat), launch (jump up), falling (descent), landing (land), hit, knockback, death
--- Health: 3 HP. Contact damage: 1. XP: 3. Gold: 0-1.

return slime_common.create(sprites.enemies.red_slime, {
	-- Movement
	wander_speed = 1.5,
	jump_horizontal_speed = 7,  -- Faster than blue

	-- Jump physics
	jump_velocity_min = -14,
	jump_velocity_variance = 4,

	-- Timers (shorter than blue - more aggressive)
	idle_time_min = 0.4,
	idle_time_variance = 0.8,
	move_burst_min = 0.1,
	move_burst_variance = 0.15,
	pause_min = 0.08,
	pause_variance = 0.15,

	-- Detection (larger range than blue)
	player_near_range = 4,

	-- Behavior: aggressive - moves toward player
	near_move_toward_chance = 0.7,  -- 70% chance to move toward when near
	far_move_toward_chance = 0.6,   -- 60% chance to move toward when far
	near_jump_chance = 0.85,        -- 85% jump chance when near
	far_jump_chance = 0.5,          -- 50% jump chance when far

	-- Animation (faster prep than blue)
	prep_jump_ms = 225,  -- ~0.9s total (4 frames * 225ms)

	-- Stats (tougher than blue)
	max_health = 3,
	contact_damage = 1,

	-- Loot (better than blue)
	loot_xp = 3,
	loot_gold_min = 0,
	loot_gold_max = 1,

	-- HP drops (0-5 particles at 0.1 each = 0-0.5 HP)
	loot_health_max = 5,
})
