local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local audio = require('audio')
local Animation = require('Animation')


--- Hit state: Player is stunned after taking damage.
--- Applies knockback away from damage source. Clears input queue on entry.
local hit = { name = "hit" }
local INVINCIBLE_TIME = 1.2

--- Called when entering hit state. Sets knockback and clears input queue.
--- @param player table The player object
function hit.start(player)
	player.hit_state.knockback_speed = 2
	player.animation = Animation.new(common.animations.HIT)
	player.hit_state.remaining_time = (common.animations.HIT.frame_count * common.animations.HIT.ms_per_frame) / 1000
	player.vy = math.max(0, player.vy)
	common.clear_input_queue(player)
end

--- Updates hit state. Applies knockback velocity and gravity.
--- Grants invincibility and processes input queue on completion.
--- @param player table The player object
--- @param dt number Delta time
function hit.update(player, dt)
	player.vx = -player.direction * player.hit_state.knockback_speed
	common.handle_gravity(player)
	player.hit_state.remaining_time = player.hit_state.remaining_time - dt
	if player.hit_state.remaining_time < 0 then
		player.invincible_time = INVINCIBLE_TIME
		if not common.process_input_queue(player) then
			player:set_state(player.states.idle)
		end
	end
end

--- Handles input while stunned. Queues jump/attack/throw for after stun ends.
--- @param player table The player object
function hit.input(player)
	common.queue_inputs(player)
end

--- Renders the player in hit stun animation.
--- @param player table The player object
function hit.draw(player)
	player.animation:draw(player.x * sprites.tile_size, player.y * sprites.tile_size)
end

return hit
