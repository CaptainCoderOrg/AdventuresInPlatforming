-- Core dependencies
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local debug = require("debugger")
local world = require("world")

-- Game systems
local Player = require("player")
local platforms = require("platforms")
local Camera = require("Camera")
local camera_cfg = require("config/camera")
local Projectile = require("Projectile")
local Effects = require("Effects")
local RestorePoint = require("RestorePoint")
local rest_state = require("player.rest")

-- UI
local hud = require("ui/hud")
local settings_menu = require("ui/settings_menu")

-- Enemies
local Enemy = require("Enemies")
Enemy.register("ratto", require("Enemies/ratto"))
Enemy.register("worm", require("Enemies/worm"))
Enemy.register("spike_slug", require("Enemies/spike_slug"))

-- Props
local Prop = require("Prop")
Prop.register("campfire", require("Prop/campfire"))
Prop.register("button", require("Prop/button"))
Prop.register("spike_trap", require("Prop/spike_trap"))
Prop.register("sign", require("Prop/sign"))

-- Levels
local level1 = require("levels/level1")
local level2 = require("levels/level2")

local levels = {
    level1 = level1,
    level2 = level2,
}

--- Get level module by ID
---@param id string Level identifier
---@return table|nil Level module or nil if not found
local function get_level_by_id(id)
    return levels[id]
end

local player  -- Instance created in init_level
local camera  -- Camera instance created in init_level
local level_info  -- Level dimensions from loaded level
local was_dead = false  -- Track death state for game over trigger
local current_level = level1  -- Track current level module

canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
canvas.set_image_smoothing(false)

--- Process player and debug input each frame
---@return nil
local function user_input()
    hud.input()

    if hud.is_title_screen_active() or hud.is_settings_open() or hud.is_game_over_active() or hud.is_rest_screen_active() then
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

--- Process game logic for one frame
---@param dt number Delta time in seconds (already capped)
---@return nil
local function update(dt)
    if hud.is_title_screen_active() or hud.is_settings_open() or hud.is_game_over_active() then
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

--- Render the game world and UI
---@return nil
local function draw()
    canvas.clear()

    -- Skip world rendering when title screen is active
    if not hud.is_title_screen_active() then
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
    end

    -- Draw screen-space UI (not affected by camera)
    hud.draw(player)
    debug.draw(player)
end

--- Initialize or reload a level with player and entities
---@param level table|nil Level module to load (defaults to current_level)
---@param spawn_override table|nil Optional spawn position {x, y} to override level spawn
---@return nil
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
    camera:snap_to_target(sprites.tile_size)

    -- Update rest state's camera reference
    rest_state.camera = camera

    was_dead = false
end

--- Clean up all game entities and colliders before level reload
--- Must be called before init_level to prevent orphaned colliders
local function cleanup_level()
    world.remove_collider(player)
    platforms.clear()
    Enemy.clear()
    Prop.clear()

    -- Projectiles need manual collider removal before clearing pool
    for projectile, _ in pairs(Projectile.all) do
        world.remove_collider(projectile)
    end
    Projectile.all = {}

    Effects.all = {}
end

--- Continue from restore point (campfire checkpoint)
--- Reloads level at saved position, or defaults to level spawn if no checkpoint exists
local function continue_from_checkpoint()
    local restore = RestorePoint.get()

    cleanup_level()

    if restore then
        local level = get_level_by_id(restore.level_id)
        if level then
            init_level(level, { x = restore.x, y = restore.y })
            -- Apply direction after init_level since Player.new() defaults to facing right
            if restore.direction then
                player.direction = restore.direction
                player.animation.flipped = restore.direction
            end
        else
            -- Fallback if level not found
            init_level()
        end
    else
        init_level()
    end

    -- Restore ambient music after leaving rest screen
    audio.play_music(audio.level1)
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

    -- Game over screen callbacks
    hud.set_continue_callback(continue_from_checkpoint)
    hud.set_restart_callback(function()
        hud.show_title_screen()
        audio.play_music(audio.title_screen)
    end)
    hud.set_rest_continue_callback(continue_from_checkpoint)

    -- Title screen callbacks
    hud.set_title_continue_callback(continue_from_checkpoint)
    hud.set_title_new_game_callback(function()
        restart_level()
        audio.play_music(audio.level1)
    end)

    hud.set_title_settings_callback(function()
        -- Open settings menu from title screen (hides "Return to Title Screen" button)
        settings_menu.show(true)
    end)
    settings_menu.set_return_to_title_callback(function()
        hud.show_title_screen()
        audio.play_music(audio.title_screen)
    end)

    hud.show_title_screen()
    audio.play_music(audio.title_screen)

    started = true
end

local function game()
    on_start()
    local dt = math.min(canvas.get_delta(), 1/30) -- HACK: 1/30 limits to 30 FPS minimum to prevent physics tunneling
    audio.update()
    hud.update(dt)
    user_input()
    update(dt)
    draw()
end

init_level()
canvas.tick(game)
canvas.start()
