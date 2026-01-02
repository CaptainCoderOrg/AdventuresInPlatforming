local sprites = require('sprites') -- TODO: Appears to be a bug in how require works?
local idle = {} 

local animation = sprites.create_animation("player_idle", 6, 12)
local t = 0

function idle.input(player)
end

function idle.draw(player)
    sprites.draw_animation(animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

function idle.update(player)
    if t % animation.speed == 0 then
		animation.frame = (animation.frame + 1) % animation.frame_count
	end
    t = t + 1
end

function idle.init()
    t = 0
end

return idle