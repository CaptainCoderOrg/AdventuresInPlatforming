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
	local x_adjust = 0
	if anim.flipped == 1 then 
		x_adjust = anim.width
	elseif anim.width > TILE then -- Facing left
		x_adjust = -TILE
	end
	
	canvas.save()
	canvas.translate(x + (x_adjust*SCALE), y)
	canvas.scale(-anim.flipped, 1)
	canvas.draw_image(anim.name, 0, 0, 
					  anim.width*SCALE, anim.height*SCALE, 
					  anim.frame*anim.width, 0, 
					  anim.width, anim.height)
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


--- Creates a sprite animation specifying the sprite_id, number of frames, speed (delay between frames)
function sprites.create_animation(name, frame_count, options)
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

return sprites
