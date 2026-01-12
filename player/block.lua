local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


local block = { name = "block" }


function block.start(player)
	player.animation = Animation.new(common.animations.BLOCK)
end


function block.update(player, dt)
	common.handle_gravity(player)
	if player.is_grounded then
		player.vx = 0
	end
end


function block.input(player)
	if controls.left_down() then
		player.direction = -1
	elseif controls.right_down() then
		player.direction = 1
	end
	if not controls.block_down() then
		player:set_state(player.states.idle)
	end
	common.handle_block(player)
	
end


function block.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return block
