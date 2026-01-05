local canvas = require("canvas")

local sprites = {}

local ANIM_SPEED = 7 -- Number of game frames per animation frame
local TILE = 16
local SCALE = 2

sprites.tile_size = TILE * SCALE

canvas.assets.add_path("assets/")
canvas.assets.load_image("tilemap", "images/tilemap_packed.png")

canvas.assets.load_image("dialogue_lg", "sprites/ui/dialogue-lg.png")
canvas.assets.load_image("slider", "sprites/ui/fillable-area.png")
canvas.assets.load_image("button", "sprites/ui/button.png")
canvas.assets.load_font("menu_font", "fonts/13px-sword.ttf")

canvas.assets.load_image("player_idle", "sprites/character/idle.png")
canvas.assets.load_image("player_run", "sprites/character/run.png")
canvas.assets.load_image("player_dash", "sprites/character/dash.png")
canvas.assets.load_image("player_fall", "sprites/character/fall.png")
canvas.assets.load_image("player_jump_up", "sprites/character/jump_up.png")
canvas.assets.load_image("player_double_jump", "sprites/character/double_jump.png")
canvas.assets.load_image("player_wall_slide", "sprites/character/wall_slide.png")

canvas.assets.load_image("player_attack_0", "sprites/character/attack_0.png")
canvas.assets.load_image("player_attack_1", "sprites/character/attack_1.png")
canvas.assets.load_image("player_attack_2", "sprites/character/attack_2.png")

function sprites.draw_animation(anim, x, y)
	local x_adjust
	if anim.flipped == 1 then 
		x_adjust = sprites.tile_size * anim.width
	else -- Facing left
		x_adjust = -(sprites.tile_size * (anim.width-1)) 
	end
	canvas.save()
	canvas.translate(x + x_adjust, y)
	canvas.scale(-anim.flipped, 1)
	canvas.draw_image(anim.name, 0, 0, 
					  sprites.tile_size*anim.width, sprites.tile_size, 
					  anim.frame*TILE*anim.width, 0, 
					  TILE*anim.width, TILE)
	canvas.restore()
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
function sprites.create_animation(name, frame_count, speed, width)
	if speed == nil then speed = ANIM_SPEED end
	if width == nil then width = 1 end
    return {
        name = name,
        frame_count = frame_count,
        frame = 0,
        flipped = 1,
		speed = speed,
		width = width,
    }
end

return sprites
