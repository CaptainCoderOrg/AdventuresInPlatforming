local canvas = require("canvas")

local sprites = {}

local ANIM_SPEED = 7 -- Number of game frames per animation frame
local TILE = 16
local SCALE = 2

sprites.tile_size = TILE * SCALE

canvas.assets.add_path("assets/")
sprites.HEART = "heart"
canvas.assets.load_image(sprites.HEART, "sprites/ui/heart.png")
canvas.assets.load_image("tilemap", "images/tilemap_packed.png")
local LADDER_TOP = "ladder_top"
local LADDER_MID = "ladder_mid"
local LADDER_BOTTOM = "ladder_bottom"
canvas.assets.load_image(LADDER_TOP, "sprites/environment/ladder_top.png")
canvas.assets.load_image(LADDER_MID, "sprites/environment/ladder_mid.png")
canvas.assets.load_image(LADDER_BOTTOM, "sprites/environment/ladder_bottom.png")

canvas.assets.load_image("dialogue_lg", "sprites/ui/dialogue-lg.png")
canvas.assets.load_image("slider", "sprites/ui/fillable-area.png")
canvas.assets.load_image("button", "sprites/ui/button.png")

canvas.assets.load_image("player_block", "sprites/character/block.png")
canvas.assets.load_image("player_idle", "sprites/character/idle.png")
canvas.assets.load_image("player_run", "sprites/character/run.png")
canvas.assets.load_image("player_dash", "sprites/character/dash.png")
canvas.assets.load_image("player_fall", "sprites/character/fall.png")
canvas.assets.load_image("player_jump_up", "sprites/character/jump_up.png")
canvas.assets.load_image("player_double_jump", "sprites/character/double_jump.png")
canvas.assets.load_image("player_wall_slide", "sprites/character/wall_slide.png")
canvas.assets.load_image("player_turn", "sprites/character/turn.png")
canvas.assets.load_image("player_turn", "sprites/character/turn.png")
canvas.assets.load_image("player_death", "sprites/character/death.png")

canvas.assets.load_image("player_attack_0", "sprites/character/attack_0.png")
canvas.assets.load_image("player_attack_1", "sprites/character/attack_1.png")
canvas.assets.load_image("player_attack_2", "sprites/character/attack_2.png")
canvas.assets.load_image("player_attack_hammer", "sprites/character/attack_hammer.png")
canvas.assets.load_image("player_throw", "sprites/character/throw.png")

canvas.assets.load_image("player_climb_up", "sprites/character/climb_up.png")
canvas.assets.load_image("player_climb_down", "sprites/character/climb_down.png")

canvas.assets.load_image("player_hit", "sprites/character/hit.png")

canvas.assets.load_image("throwable_axe", "sprites/throwables/throwable_axe.png")

function sprites.draw_animation(anim, x, y)
	-- Support both old API (direct animation) and new API (animation state)
	local definition = anim.definition or anim
	local frame = anim.definition and anim.frame or definition.frame
	local flipped = anim.definition and anim.flipped or definition.flipped

	local x_adjust = 0
	if flipped == 1 then
		x_adjust = definition.width
	elseif definition.width > TILE then -- Facing left
		x_adjust = -TILE
	end

	canvas.save()
	canvas.translate(x + (x_adjust*SCALE), y)
	canvas.scale(-flipped, 1)
	canvas.draw_image(definition.name, 0, 0,
					  definition.width*SCALE, definition.height*SCALE,
					  frame*definition.width, 0,
					  definition.width, definition.height)
	canvas.restore()
end

function sprites.draw_ladder(dx, dy, sprite)
	if sprite == nil then sprite = LADDER_MID end
	canvas.draw_image(sprite, dx, dy, TILE * SCALE, TILE * SCALE)
end

function sprites.draw_tile(tx, ty, dx, dy)
	canvas.draw_image(
		"tilemap",
		dx,
		dy,
		TILE * SCALE,
		TILE * SCALE, -- destination: x, y, width, height
		tx * TILE,
		ty * TILE,
		TILE,
		TILE -- source: x, y, width, height
	)
end


--- DEPRECATED: Use Animation.create_definition() instead
--- Creates a sprite animation definition (immutable template)
function sprites.create_animation(name, frame_count, options)
	print("DEPRECATED: sprites.create_animation() is deprecated. Use Animation.create_definition() with ms_per_frame instead.")
	options = options ~= nil and options or {}
	options.speed = options.speed ~= nil and options.speed or 6
	options.width = options.width ~= nil and options.width or TILE
	options.height = options.height ~= nil and options.height or TILE
	if options.loop == nil then options.loop = true end
	return {
		name = name,
		frame_count = frame_count,
		frame = 0,
		flipped = 1,
		speed = options.speed,
		width = options.width,
		height = options.height,
		loop = options.loop,
	}
end

--- DEPRECATED: Use Animation.new() instead
--- Creates a per-entity animation state from an animation definition
---@param definition table The animation definition from create_animation
---@param options table Optional parameters (frame, flipped)
function sprites.create_animation_state(definition, options)
	print("DEPRECATED: sprites.create_animation_state() is deprecated. Use Animation.new() instead.")
	options = options or {}
	return {
		definition = definition,
		frame = options.frame or 0,
		flipped = options.flipped or 1,
		timer = 0
	}
end

return sprites
