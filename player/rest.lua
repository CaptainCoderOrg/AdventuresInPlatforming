local Animation = require('Animation')
local common = require('player.common')
local sprites = require('sprites')
local Enemy = require('Enemies')
local RestorePoint = require('RestorePoint')
local Prop = require('Prop')
local prop_common = require('Prop/common')
local hud = require('ui/hud')

--- Y-offset to show sitting pose (sprite is drawn lower)
local REST_Y_OFFSET = 0.25

--- Rest state: Player is resting near a campfire.
--- Shows rest screen overlay with continue option.
local rest = { name = "rest" }

--- Storage for level references (set from main.lua)
---@type table|nil
rest.current_level = nil
---@type table|nil
rest.level_info = nil
---@type table|nil
rest.camera = nil

--- Find the campfire the player is currently touching
---@param player table The player object
---@return table|nil campfire The campfire prop or nil if not found
local function find_current_campfire(player)
	for prop in pairs(Prop.all) do
		if prop.type_key == "campfire" and prop_common.player_touching(prop, player) then
			return prop
		end
	end
	return nil
end

--- Called when entering rest state. Sets rest animation and stops movement.
--- Also heals player, saves restore point, respawns enemies, and shows rest screen.
---@param player table The player object
function rest.start(player)
	player.animation = Animation.new(common.animations.REST)
	player.animation.flipped = player.direction
	player.vx = 0
	player.damage = 0

	-- Animate props back to default states
	Prop.reset_all()

	if rest.current_level then
		RestorePoint.set(player.x, player.y, rest.current_level, player.direction)
	end

	if rest.level_info then
		Enemy.clear()
		for _, enemy_data in ipairs(rest.level_info.enemies) do
			Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y)
		end
	end

	-- Find the campfire and show rest screen
	local campfire = find_current_campfire(player)
	if campfire and rest.camera then
		-- Center on campfire (add 0.5 to center on tile)
		hud.show_rest_screen(campfire.x + 0.5, campfire.y + 0.5, rest.camera)
	end
end

--- Handles input while resting.
--- Input is blocked by rest screen, nothing to do here.
---@param player table The player object
function rest.input(player)
	-- Input is blocked by rest screen overlay
	-- Player will be reloaded when "Continue" is pressed
end

--- Updates rest state. Keeps player stationary.
--- Player stays in rest state until level reload from rest screen.
---@param player table The player object
---@param dt number Delta time in seconds
function rest.update(player, dt)
	player.vx = 0
	player.vy = 0
	-- Player remains stationary while rest screen is active
end

--- Renders the player in rest pose.
---@param player table The player object
function rest.draw(player)
	player.animation:draw(player.x * sprites.tile_size, (player.y + REST_Y_OFFSET) * sprites.tile_size)
end

return rest
