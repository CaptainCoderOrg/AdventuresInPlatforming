local canvas = require("canvas")
local Player = require("player")
local platforms = require("platforms")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local level1 = require("levels/level1")
local debug = require("debugger")
local hud = require("ui/hud")
local Projectile = require("Projectile")
local Effects = require("Effects")
local Camera = require("Camera")
local camera_cfg = require("config/camera")
local Enemy = require("Enemies")
local RestorePoint = require("RestorePoint")
local rest_state = require("player.rest")
Enemy.register("ratto", require("Enemies/ratto"))
Enemy.register("worm", require("Enemies/worm"))
Enemy.register("spike_slug", require("Enemies/spike_slug"))
local Prop = require("Prop")
Prop.register("campfire", require("Prop/campfire"))
Prop.register("button", require("Prop/button"))
Prop.register("spike_trap", require("Prop/spike_trap"))
Prop.register("sign", require("Prop/sign"))
local world = require("world")

local player  -- Instance created in init_level
local camera  -- Camera instance created in init_level
local level_info  -- Level dimensions from loaded level
local was_dead = false  -- Track death state for game over trigger
local current_level = level1  -- Track current level module

canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
canvas.set_image_smoothing(false)

local function user_input()
    hud.input()

    if hud.is_settings_open() or hud.is_game_over_active() or hud.is_rest_screen_active() then
        return
    end

    if canvas.is_key_pressed(canvas.keys.P) then
        config.bounding_boxes = not config.bounding_boxes
        config.debug = not config.debug
    elseif canvas.is_key_pressed(canvas.keys.DIGIT_1) then
        audio.play_music(audio.level1)
    elseif canvas.is_key_pressed(canvas.keys.DIGIT_2) then
        audio.play_music(audio.title_screen)
    end
    player:input()
end

local OUT_OF_BOUNDS_MARGIN = 5  -- Tiles beyond world edge before triggering recovery

---@param dt number Delta time in seconds (already capped)
local function update(dt)
    if hud.is_settings_open() or hud.is_game_over_active() then
        return
    end

    -- During rest screen, only update prop animations (keep campfire flickering)
    if hud.is_rest_screen_active() then
        Prop.update_animations(dt)
        return
    end
    camera:update(sprites.tile_size, dt, camera_cfg.default_lerp)
    player:update(dt)

    -- Damage and teleport player if too far outside world bounds
    if player.state ~= Player.states.death then
        local out_of_bounds = player.x < -OUT_OF_BOUNDS_MARGIN
            or player.x > level_info.width + OUT_OF_BOUNDS_MARGIN
            or player.y < -OUT_OF_BOUNDS_MARGIN
            or player.y > level_info.height + OUT_OF_BOUNDS_MARGIN
        if out_of_bounds then
            player:take_damage(1)
            if player:health() > 0 then
                player:set_position(player.last_safe_position.x, player.last_safe_position.y)
                player.vx = 0
                player.vy = 0
            end
        end
    end
    Projectile.update(dt, level_info)
    Effects.update(dt)
    Enemy.update(dt, player)
    Prop.update(dt, player)

    -- Trigger game over once when player first enters death state
    -- (was_dead prevents retriggering each frame while dead)
    if player.is_dead and not was_dead then
        was_dead = true
        hud.show_game_over()
    end
end

local function draw()
    canvas.clear()

    -- Draw world-space entities (affected by camera)
    canvas.save()
    camera:apply_transform(sprites.tile_size)
    platforms.draw(camera)
    Prop.draw()
    Enemy.draw()
    player:draw()
    Projectile.draw()
    Effects.draw()
    canvas.restore()

    -- Draw screen-space UI (not affected by camera)
    hud.draw(player)
    debug.draw(player)
end

local function init_level(level, spawn_override)
    level = level or current_level
    current_level = level

    player = Player.new()
    level_info = platforms.load_level(level)

    -- Update rest state's level references
    rest_state.current_level = current_level
    rest_state.level_info = level_info

    local spawn_pos = spawn_override or level_info.spawn
    if spawn_pos then
        player:set_position(spawn_pos.x, spawn_pos.y)
    end
    platforms.build()

    for _, enemy_data in ipairs(level_info.enemies) do
        Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y)
    end

    Prop.clear()
    for _, prop_data in ipairs(level_info.props) do
        Prop.spawn(prop_data.type, prop_data.x, prop_data.y, prop_data)
    end

    camera = Camera.new(
        config.ui.canvas_width,
        config.ui.canvas_height,
        level_info.width,
        level_info.height
    )
    camera:set_target(player)
    camera:set_look_ahead()

    -- Update rest state's camera reference
    rest_state.camera = camera

    was_dead = false
end

--- Clean up all game entities before level reload
local function cleanup_level()
    -- Remove old player collider
    world.remove_collider(player)

    -- Clear all entities
    platforms.clear()
    Enemy.clear()
    Prop.clear()

    -- Clear projectiles
    for projectile, _ in pairs(Projectile.all) do
        world.remove_collider(projectile)
    end
    Projectile.all = {}

    -- Clear effects
    Effects.all = {}
end

--- Continue from restore point (campfire checkpoint)
local function continue_from_checkpoint()
    local restore = RestorePoint.get()

    cleanup_level()

    if restore then
        init_level(restore.level, { x = restore.x, y = restore.y })
        -- Apply direction after init_level since Player.new() defaults to facing right
        if restore.direction then
            player.direction = restore.direction
            player.animation.flipped = restore.direction
        end
    else
        init_level()
    end
end

--- Full restart (clears restore point, uses level spawn)
local function restart_level()
    RestorePoint.clear()
    cleanup_level()
    init_level()
end

local started = false

local function on_start()
    if started then return end
    audio.init()
    hud.init()
    hud.set_continue_callback(continue_from_checkpoint)
    hud.set_restart_callback(restart_level)
    hud.set_rest_continue_callback(continue_from_checkpoint)
    audio.play_music(audio.level1)
    started = true
end

local function game()
    on_start()
    local dt = math.min(canvas.get_delta(), 1/30) -- HACK: 1/3 limits to 30 FPS which prevents the player from falling through platforms
    audio.update()
    hud.update(dt)
    user_input()
    update(dt)
    draw()
end

init_level()
canvas.tick(game)
canvas.start()
