-- Core dependencies
local canvas = require("canvas")
local config = require("config")
local sprites = require("sprites")
local audio = require("audio")
local debugger = require("debugger")
local world = require("world")
local combat = require("combat")
local profiler = require("profiler")

-- Game systems
local Player = require("player")
local platforms = require("platforms")
local Camera = require("Camera")
local camera_cfg = require("config/camera")
local Projectile = require("Projectile")
local Effects = require("Effects")
local Collectible = require("Collectible")
local SaveSlots = require("SaveSlots")
local Playtime = require("Playtime")
local rest_state = require("player.rest")
local proximity_audio = require("proximity_audio")

-- UI
local hud = require("ui/hud")
local audio_dialog = require("ui/audio_dialog")
local controls_dialog = require("ui/controls_dialog")
local rest_screen = require("ui/rest_screen")
local screen_fade = require("ui/screen_fade")

-- Enemies
local Enemy = require("Enemies")
Enemy.register("ratto", require("Enemies/ratto"))
Enemy.register("worm", require("Enemies/worm"))
Enemy.register("spike_slug", require("Enemies/spike_slug"))
Enemy.register("bat_eye", require("Enemies/bat_eye"))
Enemy.register("zombie", require("Enemies/zombie"))
Enemy.register("ghost_painting", require("Enemies/ghost_painting"))
local magician_def = require("Enemies/magician")
Enemy.register("magician", magician_def)

-- Props
local Prop = require("Prop")
Prop.register("campfire", require("Prop/campfire"))
Prop.register("button", require("Prop/button"))
Prop.register("spike_trap", require("Prop/spike_trap"))
Prop.register("sign", require("Prop/sign"))
Prop.register("trap_door", require("Prop/trap_door"))
Prop.register("chest", require("Prop/chest"))
Prop.register("spear_trap", require("Prop/spear_trap"))
Prop.register("pressure_plate", require("Prop/pressure_plate"))
Prop.register("locked_door", require("Prop/locked_door"))
Prop.register("unique_item", require("Prop/unique_item"))
Prop.register("lever", require("Prop/lever"))
Prop.register("appearing_bridge", require("Prop/appearing_bridge"))
Prop.register("stairs", require("Prop/stairs"))
Prop.register("decoy_painting", require("Prop/decoy_painting"))

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

--- Find spawn position by symbol in a level
---@param level table Level module with map
---@param symbol string Symbol to search for
---@return table|nil spawn Position {x, y} or nil if not found
local function find_spawn_by_symbol(level, symbol)
    if not level or not level.map then return nil end
    for row_idx, row in ipairs(level.map) do
        for col_idx = 1, #row do
            local char = row:sub(col_idx, col_idx)
            if char == symbol then
                return { x = col_idx - 1, y = row_idx - 1 }
            end
        end
    end
    return nil
end

--- Get player data for preservation during level transitions
--- Combines core stats and transient state for mid-level preservation
---@param p table Player instance
---@return table data Player stats to preserve
local function get_player_save_data(p)
    local data = SaveSlots.get_player_stats(p)
    local transient = SaveSlots.get_transient_state(p)
    for key, value in pairs(transient) do
        data[key] = value
    end
    data.prop_states = Prop.get_persistent_states()
    return data
end

local player  -- Instance created in init_level
local camera  -- Camera instance created in init_level
local level_info  -- Level dimensions from loaded level
local was_dead = false  -- Track death state for game over trigger
local current_level = level1  -- Track current level module
local active_slot = nil  -- Currently active save slot (1-3)
local proximity_volumes = {}  -- Reused per-frame to avoid allocations

-- Forward declarations for functions used before definition
local cleanup_level
local init_level

canvas.set_size(config.ui.canvas_width, config.ui.canvas_height)
canvas.set_image_smoothing(false)

--- Process player and debug input each frame
---@return nil
local function user_input()
    hud.input()

    -- Profiler toggle works on any screen
    if canvas.is_key_pressed(canvas.keys.O) then
        profiler.toggle()
        config.profiler = profiler.enabled
    end

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
    profiler.start("playtime")
    Playtime.resume()
    Playtime.update(dt)
    profiler.stop("playtime")

    -- Reset cache so props querying player proximity get fresh results this frame
    proximity_audio.invalidate_cache()

    profiler.start("camera")
    camera:update(sprites.tile_size, dt, camera_cfg.default_lerp)

    -- Capture camera position each frame for rest screen restoration
    -- (saved after camera update settles, used if player enters rest this frame)
    rest_screen.save_camera_position(camera:get_x(), camera:get_y())
    profiler.stop("camera")

    profiler.start("player")
    player:update(dt)

    -- Check for stairs level transition
    if player.stairs_transition_ready and player.stairs_target and not screen_fade.is_active() then
        local target = player.stairs_target
        local target_level = get_level_by_id(target.level_id)
        local spawn_pos = target_level and find_spawn_by_symbol(target_level, target.spawn_symbol)

        -- Clear flags regardless of whether transition succeeds
        player.stairs_transition_ready = false
        player.stairs_target = nil

        if spawn_pos then
            local player_data = get_player_save_data(player)
            screen_fade.start(function()
                cleanup_level()
                init_level(target_level, spawn_pos, player_data)
                audio.play_music(audio.level1)
            end)
            profiler.stop("player")
            return
        end
    end

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
    profiler.stop("player")

    profiler.start("projectiles")
    Projectile.update(dt, level_info)
    profiler.stop("projectiles")

    profiler.start("effects")
    Effects.update(dt)
    profiler.stop("effects")

    profiler.start("collectibles")
    Collectible.update(dt, player)
    profiler.stop("collectibles")

    profiler.start("enemies")
    Enemy.update(dt, player, camera)
    profiler.stop("enemies")

    profiler.start("props")
    Prop.update(dt, player)
    profiler.stop("props")

    -- Aggregate volumes by sound_id so multiple emitters of same type combine naturally
    profiler.start("proximity")
    local nearby = proximity_audio.get_cached(player.x, player.y)
    for k in pairs(proximity_volumes) do proximity_volumes[k] = nil end
    for i = 1, #nearby do
        local result = nearby[i]
        local id = result.config.sound_id
        proximity_volumes[id] = math.min(1, (proximity_volumes[id] or 0) + result.volume)
    end
    -- Update all spatial sounds (including those not in range -> volume 0)
    local sound_ids = audio.get_spatial_sound_ids()
    for i = 1, #sound_ids do
        local sound_id = sound_ids[i]
        audio.update_spatial_sound(sound_id, proximity_volumes[sound_id] or 0)
    end
    profiler.stop("proximity")

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
        Prop.draw(camera)
        Enemy.draw(camera)
        player:draw()
        Projectile.draw(camera)
        Effects.draw()
        Collectible.draw()
        if config.bounding_boxes then
            proximity_audio.draw_debug()
        end
        canvas.restore()
    end

    -- Draw screen-space UI (not affected by camera)
    hud.draw(player)

    -- Draw screen fade overlay (covers everything)
    screen_fade.draw()
end

--- Initialize or reload a level with player and entities
---@param level table|nil Level module to load (defaults to current_level)
---@param spawn_override table|nil Optional spawn position {x, y} to override level spawn
---@param player_data table|nil Optional player stats to restore (max_health, level)
---@param options table|nil Optional settings { skip_camera_snap = bool }
---@return nil
init_level = function(level, spawn_override, player_data, options)
    options = options or {}
    level = level or current_level
    current_level = level

    player = Player.new()

    -- Restore player stats if provided
    if player_data then
        SaveSlots.restore_player_stats(player, player_data)
        SaveSlots.restore_transient_state(player, player_data)
        -- Update active projectile reference if projectile_ix was restored
        if player_data.projectile_ix then
            player.projectile = player.projectile_options[player.projectile_ix]
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
        Enemy.spawn(enemy_data.type, enemy_data.x, enemy_data.y, enemy_data)
    end

    Prop.clear()
    for _, prop_data in ipairs(level_info.props) do
        local prop_def = Prop.types[prop_data.type]
        -- Props spawn by default; only skip if should_spawn explicitly returns false
        local spawn_check = prop_def and prop_def.should_spawn
        if not spawn_check or spawn_check(prop_data, player) then
            Prop.spawn(prop_data.type, prop_data.x, prop_data.y, prop_data)
        end
    end

    -- Restore persistent prop states from save data
    if player_data and player_data.prop_states then
        Prop.restore_persistent_states(player_data.prop_states)
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
cleanup_level = function()
    world.remove_collider(player)
    world.remove_shield(player)
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

    -- Clear magician magic bolts
    magician_def.clear_bolts()

    -- Clear spear trap projectiles (trigger colliders not cleared by Prop.clear)
    local spear_trap_def = Prop.types["spear_trap"]
    if spear_trap_def then spear_trap_def.clear_spears() end

    Effects.clear()
    Collectible.clear()

    -- Final cleanup ensures no orphaned shapes in spatial hash
    combat.clear()
end

--- Continue from active save slot (campfire checkpoint)
--- Reloads level at saved position, or defaults to level spawn if no checkpoint exists
---@param options table|nil Optional settings { restore_camera_from_rest = bool }
---@return nil
local function continue_from_checkpoint(options)
    local data = active_slot and SaveSlots.get(active_slot)
    options = options or {}

    -- Capture original camera position before cleanup if restoring from rest
    if options.restore_camera_from_rest then
        local cam_x, cam_y = rest_screen.get_original_camera_pos()
        options.camera_pos = { x = cam_x, y = cam_y }
    end

    cleanup_level()

    local level = data and get_level_by_id(data.level_id)
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
    Prop.clear_persistent_states()
    cleanup_level()
    init_level(level1)
    audio.play_music(audio.level1)
end

local started = false

--- Load a save slot and start the game
---@param slot_index number Slot index (1-3)
---@return nil
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
    hud.set_title_play_game_callback(hud.show_slot_screen)
    hud.set_title_audio_callback(audio_dialog.show)
    hud.set_title_controls_callback(controls_dialog.show)

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
    profiler.begin_frame()
    on_start()
    local dt = math.min(canvas.get_delta(), 1/30) -- HACK: 1/30 limits to 30 FPS minimum to prevent physics tunneling

    profiler.start("audio")
    audio.update(dt)
    profiler.stop("audio")

    profiler.start("hud")
    hud.update(dt, player)
    screen_fade.update(dt)
    profiler.stop("hud")

    profiler.start("input")
    user_input()
    profiler.stop("input")

    profiler.start("update")
    update(dt)
    profiler.stop("update")

    profiler.start("draw")
    draw()
    profiler.stop("draw")

    profiler.end_frame()

    -- Draw debug/profiler overlay (excluded from profiler timing)
    debugger.draw(player)
end

-- Initialization order: init_level creates player/camera, then on_start runs on first tick
init_level()
canvas.tick(game)
canvas.start()
