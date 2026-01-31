local Animation = require('Animation')
local audio = require('audio')
local common = require('player.common')
local Enemy = require('Enemies')
local hud = require('ui/hud')
local Prop = require('Prop')
local prop_common = require('Prop/common')
local SaveSlots = require('SaveSlots')

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
---@type number|nil
rest.active_slot = nil

--- Extracts the level ID from a level module.
--- Supports both ASCII levels (id at top level) and Tiled levels (id in properties).
---@param level table|nil Level module to extract ID from
---@return string|nil level_id The level ID or nil if not found
local function get_level_id(level)
	if not level then return nil end
	if level.id then return level.id end
	if level.properties and level.properties.id then return level.properties.id end
	return nil
end

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
--- Also heals player, saves to active slot, respawns enemies, and shows rest screen.
---@param player table The player object
function rest.start(player)
	player.animation = Animation.new(common.animations.REST)
	player.animation.flipped = player.direction
	player.vx = 0
	player.damage = 0
	player.energy_used = 0

	-- Animate props back to default states
	Prop.reset_all()

	-- Find the campfire for name and screen centering
	local campfire = find_current_campfire(player)
	local campfire_name = campfire and campfire.name or "Campfire"

	-- Save to active slot with full data
	local level_id = get_level_id(rest.current_level)
	if rest.active_slot and level_id then
		local save_data = SaveSlots.build_player_data(player, level_id, campfire_name)
		SaveSlots.set(rest.active_slot, save_data)
	end

	if rest.level_info then
		Enemy.clear()
		for _, enemy_data in ipairs(rest.level_info.enemies) do
			Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y)
		end
	end

	-- Show rest screen centered on campfire
	if campfire and rest.camera then
		-- Center on campfire (add 0.5 to center on tile)
		hud.show_rest_screen(campfire.x + 0.5, campfire.y + 0.5, rest.camera, player,
			rest.active_slot, level_id, campfire_name)
	end

	-- Fade to rest music
	audio.play_music(audio.rest)
end

--- Handles input while resting. Input is blocked by rest screen overlay.
---@param player table The player object
function rest.input(player)
end

--- Updates rest state. Keeps player stationary until level reload from rest screen.
---@param player table The player object
---@param dt number Delta time in seconds (unused: rest state is static, waiting for UI)
function rest.update(player, dt)
	player.vx = 0
	player.vy = 0
end

--- Renders the player in rest pose.
---@param player table The player object
function rest.draw(player)
	common.draw(player, REST_Y_OFFSET)
end

return rest
