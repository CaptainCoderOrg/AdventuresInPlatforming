local Animation = require('Animation')
local common = require('player.common')
local controls = require('controls')
local sprites = require('sprites')
local Enemy = require('Enemies')
local RestorePoint = require('RestorePoint')

--- Y-offset to show sitting pose (sprite is drawn lower)
local REST_Y_OFFSET = 0.25

--- Rest state: Player is resting near a campfire.
--- Can perform all actions available from idle state.
local rest = { name = "rest" }

--- Storage for level references (set from main.lua)
---@type table|nil
rest.current_level = nil
---@type table|nil
rest.level_info = nil

--- Called when entering rest state. Sets rest animation and stops movement.
--- Also heals player, saves restore point, and respawns enemies.
---@param player table The player object
function rest.start(player)
	player.animation = Animation.new(common.animations.REST)
	player.vx = 0
	player.damage = 0

	if rest.current_level then
		RestorePoint.set(player.x, player.y, rest.current_level)
	end

	if rest.level_info then
		Enemy.clear()
		for _, enemy_data in ipairs(rest.level_info.enemies) do
			Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y)
		end
	end
end

--- Handles input while resting. Movement exits rest state.
---@param player table The player object
function rest.input(player)
	if common.check_cooldown_queues(player) then return end

	if controls.left_down() then
		player.direction = -1
		player:set_state(player.states.run)
		return
	elseif controls.right_down() then
		player.direction = 1
		player:set_state(player.states.run)
		return
	end

	common.handle_throw(player)
	common.handle_hammer(player)
	common.handle_block(player)
	if not controls.down_down() then
		common.handle_attack(player)
	end
	common.handle_dash(player)
	common.handle_jump(player)
	common.handle_climb(player)
end

--- Updates rest state. Stops horizontal movement and applies gravity.
--- Exits to idle if no longer near campfire.
---@param player table The player object
---@param dt number Delta time in seconds
function rest.update(player, dt)
	player.vx = 0
	common.handle_gravity(player, dt)

	if not common.is_near_campfire(player) then
		player:set_state(player.states.idle)
	end
end

--- Renders the player in rest pose.
---@param player table The player object
function rest.draw(player)
	player.animation:draw(player.x * sprites.tile_size, (player.y + REST_Y_OFFSET) * sprites.tile_size)
end

return rest
