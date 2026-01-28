--- Decoy Painting prop - Decorative painting that looks like ghost_painting enemy (visual only)
local sprites = require('sprites')
local canvas = require('canvas')

return {
	box = { x = 0, y = 0, w = 0, h = 0 },  -- No collision - purely visual

	--- Draw the decoy painting sprite
	---@param prop table The prop instance
	draw = function(prop)
		local ts = sprites.tile_size
		local x = sprites.px(prop.x)
		local y = sprites.px(prop.y - 0.5)  -- -8 pixel offset to match ghost_painting

		canvas.draw_image(
			sprites.enemies.ghost_painting.static,
			x, y,
			ts, ts * 1.5,
			0, 0,
			16, 24
		)
	end,
}
