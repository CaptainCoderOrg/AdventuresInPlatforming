local Animation = require('Animation')
local common = require('player.common')
local controls = require('controls')
local weapon_sync = require('player.weapon_sync')

--- Throw state: Player throws the selected projectile.
--- Movement allowed during throw animation. Clears input queue on entry.
local throw = { name = "throw" }

local THROW_COOLDOWN = 0.2

--- Called when entering throw state. Creates projectile and clears input queue.
---@param player table The player object
function throw.start(player)
	-- Defensive guard: if no projectile equipped, return to idle
	if not player.projectile then
		player:set_state(player.states.idle)
		return
	end
	-- Consume energy based on projectile's cost (clamp to max in case of race)
	local energy_cost = player.projectile.energy_cost or 1
	player.energy_used = math.min(player.energy_used + energy_cost, player.max_energy)
	weapon_sync.consume_charge(player)
	player.animation = Animation.new(common.animations.THROW)
	player.throw_state.remaining_time = (common.animations.THROW.frame_count * common.animations.THROW.ms_per_frame) / 1000
	player.projectile.create(player.x, player.y, player.direction, player)
	common.clear_input_queue(player)
end

--- Updates throw state. Applies gravity and handles animation timing.
--- Processes input queue on completion; transitions to idle if no queued input.
---@param player table The player object
---@param dt number Delta time
function throw.update(player, dt)
	common.handle_gravity(player, dt)
	player.throw_state.remaining_time = player.throw_state.remaining_time - dt
	if player.throw_state.remaining_time <= 0 then
		-- Set cooldown before processing queue so it's always respected
		player.throw_cooldown = THROW_COOLDOWN
		if not common.process_input_queue(player) then
			player:set_state(player.states.idle)
		end
	end
end

--- Handles input while throwing. Allows movement and immediate jump.
--- Queues attack/throw for execution after animation completes.
---@param player table The player object
function throw.input(player)
	if controls.left_down() then
		player.direction = -1
		player.vx = player.direction * player:get_speed()
	elseif controls.right_down() then
		player.direction = 1
		player.vx = player.direction * player:get_speed()
	else
		player.vx = 0
	end
	-- Allow immediate jump during throw for responsiveness (mobile state)
	-- while attack/throw are queued for after animation completes
	common.handle_jump(player)

	common.queue_inputs(player)
end

--- Renders the player in throw animation.
---@param player table The player object
function throw.draw(player)
	common.draw(player)
end

return throw
