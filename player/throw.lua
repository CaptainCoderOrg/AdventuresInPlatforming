local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Projectile = require('Projectile')


local throw = { name = "throw" }


function throw.start(player)
	common.animations.THROW.frame = 0
	player.animation = common.animations.THROW
	throw.remaining_frames = common.animations.THROW.frame_count * common.animations.THROW.speed
	Projectile.create_axe(player.x, player.y, player.direction)
end


function throw.update(player, dt)
	common.handle_gravity(player)
	throw.remaining_frames = throw.remaining_frames - 1
	if throw.remaining_frames < 0 then
		player:set_state(player.states.idle)
	end
end


function throw.input(player)
	if controls.left_down() then
		player.direction = -1
		player.vx = player.direction * player.speed
	elseif controls.right_down() then
		player.direction = 1
		player.vx = player.direction * player.speed
	else
		player.vx = 0
	end
end


function throw.draw(player)
	sprites.draw_animation(player.animation, player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return throw
