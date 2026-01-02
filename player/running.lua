local sprites = require('sprites') -- TODO: Appears to be a bug in how require works?
local state = {} 

local animation = sprites.create_animation("player_run", 8, 7)
local t = 0

function state.input(player)
end

function state.draw(player)
    sprites.draw_animation(animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

function state.update(player)
    if t % animation.speed == 0 then
		animation.frame = (animation.frame + 1) % animation.frame_count
	end
    t = t + 1
end

function state.init()
    t = 0
end

return idle