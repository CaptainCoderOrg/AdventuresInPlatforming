--- Persistent state for effects module.
--- Separated from init.lua so hot-swapping doesn't clear existing effects.
return {
	all = {},
	damage_texts = {},
	status_texts = {},
	fatigue_particles = {},
	next_id = 1
}
