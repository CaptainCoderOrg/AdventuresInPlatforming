--- Persistent state for collectible module.
--- Separated from init.lua so hot-swapping doesn't clear existing collectibles.
return {
	all = {},
	next_id = 1
}
