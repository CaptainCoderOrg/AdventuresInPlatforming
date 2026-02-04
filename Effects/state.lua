--- Persistent state for effects module.
--- Separated from init.lua so hot-swapping doesn't clear existing effects.
return {
	all = {},
	damage_texts = {},
	status_texts = {},
	fatigue_particles = {},
	collect_particles = {},
	flying_objects = {},     -- Flying object effects (boss axe drop, etc.)
	next_id = 1,
	active_xp_text = nil,    -- Tracks current XP text for accumulation
	active_gold_text = nil,  -- Tracks current gold text for accumulation
}
