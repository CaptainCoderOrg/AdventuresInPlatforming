-- Core dependencies
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local debug = require("debugger")
local world = require("world")
local combat = require("combat")

-- Game systems
local Player = require("player")
local platforms = require("platforms")
local Camera = require("Camera")
local camera_cfg = require("config/camera")
local Projectile = require("Projectile")
local Effects = require("Effects")
local SaveSlots = require("SaveSlots")
local Playtime = require("Playtime")
local rest_state = require("player.rest")
local proximity_audio = require("proximity_audio")

-- UI
local hud = require("ui/hud")
local audio_dialog = require("ui/audio_dialog")
local controls_dialog = require("ui/controls_dialog")
local rest_screen = require("ui/rest_screen")

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
Prop.register("trap_door", require("Prop/trap_door"))

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
local active_slot = nil  -- Currently active save slot (1-3)

canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
canvas.set_image_smoothing(false)

--- Process player and debug input each frame
---@return nil
local function user_input()
    hud.input()

    if hud.is_title_screen_active() or hud.is_game_over_active() or hud.is_rest_screen_active() then
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
    if hud.is_title_screen_active() or hud.is_slot_screen_active() or hud.is_game_over_active() then
        Playtime.pause()
        return
    end

    -- During rest/pause screen, only update prop animations (keep campfire flickering)
    -- Timer keeps counting
    if hud.is_rest_screen_active() then
        Playtime.resume()
        Playtime.update(dt)
        Prop.update_animations(dt)
        return
    end

    -- Resume playtime tracking during gameplay
    Playtime.resume()
    Playtime.update(dt)

    -- Reset cache so props querying player proximity get fresh results this frame
    proximity_audio.invalidate_cache()

    camera:update(sprites.tile_size, dt, camera_cfg.default_lerp)

    -- Capture camera position each frame for rest screen restoration
    -- (saved after camera update settles, used if player enters rest this frame)
    rest_screen.save_camera_position(camera:get_x(), camera:get_y())

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

    -- Aggregate volumes by sound_id so multiple emitters of same type combine naturally
    local nearby = proximity_audio.get_cached(player.x, player.y)
    local volumes = {}
    for _, result in ipairs(nearby) do
        local id = result.config.sound_id
        volumes[id] = math.min(1, (volumes[id] or 0) + result.volume)
    end
    -- Update all spatial sounds (including those not in range -> volume 0)
    for _, sound_id in ipairs(audio.get_spatial_sound_ids()) do
        audio.update_spatial_sound(sound_id, volumes[sound_id] or 0)
    end

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

        -- Apply rest screen camera offset (keeps campfire centered in circle)
        local culling_margin = 0
        if rest_screen.is_active() then
            local offset_x, offset_y = rest_screen.get_camera_offset()
            canvas.translate(offset_x, offset_y)
            -- Convert pixel offset to tile margin (round up to ensure coverage)
            local margin_x = math.ceil(math.abs(offset_x) / sprites.tile_size)
            local margin_y = math.ceil(math.abs(offset_y) / sprites.tile_size)
            culling_margin = math.max(margin_x, margin_y)
        end

        platforms.draw(camera, culling_margin)
        Prop.draw()
        Enemy.draw()
        player:draw()
        Projectile.draw()
        Effects.draw()
        if config.bounding_boxes then
            proximity_audio.draw_debug()
        end
        canvas.restore()
    end

    -- Draw screen-space UI (not affected by camera)
    hud.draw(player)
    debug.draw(player)
end

--- Initialize or reload a level with player and entities
---@param level table|nil Level module to load (defaults to current_level)
---@param spawn_override table|nil Optional spawn position {x, y} to override level spawn
---@param player_data table|nil Optional player stats to restore (max_health, level)
---@param options table|nil Optional settings { skip_camera_snap = bool }
---@return nil
local function init_level(level, spawn_override, player_data, options)
    options = options or {}
    level = level or current_level
    current_level = level

    player = Player.new()

    -- Restore player stats if provided
    if player_data then
        local stat_keys = { "max_health", "level", "experience", "gold", "defense", "strength", "critical_chance" }
        for _, key in ipairs(stat_keys) do
            if player_data[key] then player[key] = player_data[key] end
        end
    end

    level_info = platforms.load_level(level)

    -- Update rest state's level references
    rest_state.current_level = current_level
    rest_state.level_info = level_info
    rest_state.active_slot = active_slot

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
    if options.camera_pos then
        -- Restore camera to saved position (skips lerping on next update)
        camera:restore_position(options.camera_pos.x, options.camera_pos.y)
    elseif not options.skip_camera_snap then
        camera:snap_to_target(sprites.tile_size)
    end

    -- Update rest state's camera reference
    rest_state.camera = camera

    hud.set_gameplay_refs(player, camera)

    was_dead = false
end

--- Clean up all game entities and colliders before level reload
--- Must be called before init_level to prevent orphaned colliders
---@return nil
local function cleanup_level()
    world.remove_collider(player)
    combat.remove(player)
    world.clear_probes()
    platforms.clear()
    Enemy.clear()
    Prop.clear()

    -- Projectiles need manual collider removal before clearing pool
    for projectile, _ in pairs(Projectile.all) do
        world.remove_collider(projectile)
    end
    Projectile.all = {}

    Effects.all = {}

    -- Final cleanup ensures no orphaned shapes in spatial hash
    combat.clear()
end

--- Continue from active save slot (campfire checkpoint)
--- Reloads level at saved position, or defaults to level spawn if no checkpoint exists
---@param options table|nil Optional settings { restore_camera_from_rest = bool }
local function continue_from_checkpoint(options)
    local data = active_slot and SaveSlots.get(active_slot)
    options = options or {}

    -- Capture original camera position before cleanup if restoring from rest
    if options.restore_camera_from_rest then
        local cam_x, cam_y = rest_screen.get_original_camera_pos()
        options.camera_pos = { x = cam_x, y = cam_y }
    end

    cleanup_level()

    if data then
        local level = get_level_by_id(data.level_id)
        if level then
            -- Pass data directly; init_level extracts only the stat keys it needs
            init_level(level, { x = data.x, y = data.y }, data, options)
            -- Apply direction after init_level since Player.new() defaults to facing right
            if data.direction then
                player.direction = data.direction
                player.animation.flipped = data.direction
            end
            Playtime.set(data.playtime or 0)
        else
            init_level(nil, nil, nil, options)
            Playtime.reset()
        end
    else
        init_level(nil, nil, nil, options)
        Playtime.reset()
    end

    audio.play_music(audio.level1)
end

--- Continue from rest screen (restores original camera position for smooth transition)
---@return nil
local function continue_from_rest()
    continue_from_checkpoint({ restore_camera_from_rest = true })
end

--- Start new game in active slot (clears slot, uses level spawn)
---@return nil
local function start_new_game()
    if active_slot then
        SaveSlots.clear(active_slot)
    end
    Playtime.reset()
    cleanup_level()
    init_level()
end

local started = false

--- Load a save slot and start the game
---@param slot_index number Slot index (1-3)
local function load_slot(slot_index)
    active_slot = slot_index
    local data = SaveSlots.get(slot_index)

    -- Hide title screen when starting game
    hud.hide_title_screen()

    if data then
        -- Existing save - continue from checkpoint
        continue_from_checkpoint()
    else
        -- Empty slot - start new game
        start_new_game()
    end

    audio.play_music(audio.level1)
end

--- One-time initialization on first game tick (after init_level creates player/camera)
---@return nil
local function on_start()
    if started then return end
    audio.init()
    hud.init()

    --- Return to title screen and reset active save slot
    ---@return nil
    local function return_to_title()
        active_slot = nil
        hud.show_title_screen()
        audio.play_music(audio.title_screen)
    end

    -- Game over screen callbacks
    hud.set_continue_callback(continue_from_checkpoint)
    hud.set_restart_callback(return_to_title)
    hud.set_rest_continue_callback(continue_from_rest)

    -- Title screen callbacks
    hud.set_title_play_game_callback(function()
        hud.show_slot_screen()
    end)

    hud.set_title_audio_callback(function()
        audio_dialog.show()
    end)

    hud.set_title_controls_callback(function()
        controls_dialog.show()
    end)

    -- Slot screen callbacks (back navigates to title which is already shown beneath)
    hud.set_slot_callback(load_slot)

    rest_screen.set_return_to_title_callback(return_to_title)

    hud.show_title_screen()
    audio.play_music(audio.title_screen)

    started = true
end

--- Main game loop - called every frame by canvas.tick
---@return nil
local function game()
    on_start()
    local dt = math.min(canvas.get_delta(), 1/30) -- HACK: 1/30 limits to 30 FPS minimum to prevent physics tunneling
    audio.update(dt)
    hud.update(dt, player)
    user_input()
    update(dt)
    draw()
end

-- Initialization order: init_level creates player/camera, then on_start runs on first tick
init_level()
canvas.tick(game)
canvas.start()
