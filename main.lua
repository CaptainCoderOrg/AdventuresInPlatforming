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
Enemy.register("ratto", require("Enemies/ratto"))
Enemy.register("worm", require("Enemies/worm"))
Enemy.register("spike_slug", require("Enemies/spike_slug"))
local Sign = require("Sign")
local SpikeTrap = require("SpikeTrap")
local Button = require("Button")
local Campfire = require("Campfire")
local world = require("world")

local player  -- Instance created in init_level
local camera  -- Camera instance created in init_level
local level_info  -- Level dimensions from loaded level
local was_dead = false  -- Track death state for game over trigger

canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
canvas.set_image_smoothing(false)

local function user_input()
    hud.input()

    if hud.is_settings_open() or hud.is_game_over_active() then
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
    Sign.update(dt, player)
    SpikeTrap.update(dt, player)
    Button.update(dt)
    Campfire.update(dt)

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
    Sign.draw()
    SpikeTrap.draw()
    Button.draw()
    Enemy.draw()
    player:draw()
    Campfire.draw()
    Projectile.draw()
    Effects.draw()
    canvas.restore()

    -- Draw screen-space UI (not affected by camera)
    hud.draw(player)
    debug.draw(player)
end

local function init_level()
    player = Player.new()
    level_info = platforms.load_level(level1)
    if level_info.spawn then
        player:set_position(level_info.spawn.x, level_info.spawn.y)
    end
    platforms.build()

    for _, enemy_data in ipairs(level_info.enemies) do
        Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y)
    end

    Sign.clear()
    for _, sign_data in ipairs(level_info.signs) do
        Sign.new(sign_data.x, sign_data.y, sign_data.text)
    end

    SpikeTrap.clear()
    for _, trap_data in ipairs(level_info.spike_traps) do
        SpikeTrap.new(trap_data.x, trap_data.y, trap_data)
    end

    Button.clear()
    for _, button_data in ipairs(level_info.buttons) do
        Button.new(button_data.x, button_data.y, button_data)
    end

    Campfire.clear()
    for _, campfire_data in ipairs(level_info.campfires) do
        Campfire.new(campfire_data.x, campfire_data.y)
    end

    camera = Camera.new(
        config.ui.canvas_width,
        config.ui.canvas_height,
        level_info.width,
        level_info.height
    )
    camera:set_target(player)
    camera:set_look_ahead()

    was_dead = false
end

local function restart_level()
    -- Remove old player collider
    world.remove_collider(player)

    -- Clear all entities
    platforms.clear()
    Enemy.clear()
    Sign.clear()
    SpikeTrap.clear()
    Button.clear()
    Campfire.clear()

    -- Clear projectiles
    for projectile, _ in pairs(Projectile.all) do
        world.remove_collider(projectile)
    end
    Projectile.all = {}

    -- Clear effects
    Effects.all = {}

    -- Reinitialize level
    init_level()
end

local started = false

local function on_start()
    if started then return end
    audio.init()
    hud.init()
    hud.set_restart_callback(restart_level)
    audio.play_music(audio.level1)
    started = true
end

local function game()
    on_start()
    local dt = math.min(canvas.get_delta(), 0.5)
    audio.update()
    hud.update(dt)
    user_input()
    update(dt)
    draw()
end

init_level()
canvas.tick(game)
canvas.start()
