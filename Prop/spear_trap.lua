--- Spear trap prop definition - Wall-mounted trap that fires damaging spears
local Animation = require("Animation")
local audio = require("audio")
local canvas = require("canvas")
local combat = require("combat")
local config = require("config")
local Effects = require("Effects")
local Prop = require("Prop")
local common = require("Prop/common")
local proximity_audio = require("proximity_audio")
local sprites = require("sprites")
local world = require("world")

local TRAP_ANIM = Animation.create_definition(sprites.environment.spear_trap, 8, {
    ms_per_frame = 60,
    width = 16,
    height = 16,
    loop = false
})

local SPEAR_ANIM = Animation.create_definition(sprites.environment.spear, 3, {
    ms_per_frame = 100,
    width = 16,
    height = 8,
    loop = true
})

local DEFAULT_FIRE_DELAY = 2.0
local DEFAULT_COOLDOWN_TIME = 0.5
local SPEAR_SPEED = 12  -- tiles per second
local SPEAR_DAMAGE = 1
local SOUND_RADIUS = 16  -- tiles

--------------------------------------------------------------------------------
-- Spear projectile pool (local to this module)
--------------------------------------------------------------------------------
local Spear = {}
Spear.all = {}

-- Dirty flags for once-per-frame updates/draws
-- Update pass sets needs_draw=true after running, draw pass sets needs_update=true
Spear.needs_update = true
Spear.needs_draw = false

-- Module-level table to track removal indices (avoids allocation each frame)
local spear_indices_to_remove = {}

--- Spawn a new spear projectile
---@param x number X position in tiles
---@param y number Y position in tiles
---@param direction number Direction to travel (-1 = left, 1 = right)
function Spear.spawn(x, y, direction)
    -- Hitbox aligned to front of spear based on direction
    -- Spear sprite is 1x0.5 tiles, hitbox is 0.25x0.5 tiles
    local box_x = direction == 1 and 0.75 or 0  -- Right side when facing right, left side when facing left

    local spear = {
        x = x,
        y = y,
        direction = direction,
        box = { x = box_x, y = 0, w = 0.25, h = 0.5 },
        animation = Animation.new(SPEAR_ANIM, { flipped = direction }),
        marked_for_destruction = false,
        debug_color = "#FFA500",  -- Orange
    }

    -- Add trigger collider for wall detection
    world.add_trigger_collider(spear)
    -- Add to combat system for player collision
    combat.add(spear)

    Spear.all[#Spear.all + 1] = spear
    return spear
end

--- Creates hit effect at spear tip and marks spear for destruction
---@param spear table Spear instance
---@param x number X position of impact
---@param y number Y position of impact
local function spear_impact(spear, x, y)
    local effect_x = x + spear.box.x - 0.25
    local effect_y = y - 0.25
    Effects.create_hit(effect_x, effect_y, spear.direction)
    spear.marked_for_destruction = true
end

--- Update all spears (called once per frame via dirty flag)
---@param dt number Delta time in seconds
---@param player table Player instance for collision
function Spear.update_all(dt, player)
    if not Spear.needs_update then return end
    Spear.needs_update = false
    Spear.needs_draw = true

    -- Clear removal indices
    for i = 1, #spear_indices_to_remove do spear_indices_to_remove[i] = nil end

    for i = 1, #Spear.all do
        local spear = Spear.all[i]
        if spear.marked_for_destruction then
            world.remove_trigger_collider(spear)
            combat.remove(spear)
            spear_indices_to_remove[#spear_indices_to_remove + 1] = i
        else
            spear.x = spear.x + spear.direction * SPEAR_SPEED * dt
            combat.update(spear)
            spear.animation:play(dt)

            local collision = world.move_trigger(spear)
            if collision then
                spear_impact(spear, collision.x, collision.y)
                audio.play_solid_sound()
            elseif common.damage_player(spear, player, SPEAR_DAMAGE) then
                spear_impact(spear, spear.x, spear.y)
            end
        end
    end

    -- Remove in reverse order, swap with last element
    for i = #spear_indices_to_remove, 1, -1 do
        local idx = spear_indices_to_remove[i]
        Spear.all[idx] = Spear.all[#Spear.all]
        Spear.all[#Spear.all] = nil
    end
end

--- Draw all spears (called once per frame via dirty flag)
function Spear.draw_all()
    if not Spear.needs_draw then return end
    Spear.needs_draw = false
    Spear.needs_update = true

    for i = 1, #Spear.all do
        local spear = Spear.all[i]
        if not spear.marked_for_destruction then
            local px = spear.x * sprites.tile_size
            local py = spear.y * sprites.tile_size
            spear.animation:draw(px, py)

            -- Debug bounding box
            if config.bounding_boxes and spear.box then
                local bx = (spear.x + spear.box.x) * sprites.tile_size
                local by = (spear.y + spear.box.y) * sprites.tile_size
                local bw = spear.box.w * sprites.tile_size
                local bh = spear.box.h * sprites.tile_size
                canvas.draw_rect(bx, by, bw, bh, spear.debug_color)
            end
        end
    end
end

--- Clear all spears (called on level reload)
function Spear.clear_all()
    for i = 1, #Spear.all do
        local spear = Spear.all[i]
        world.remove_trigger_collider(spear)
        combat.remove(spear)
    end
    Spear.all = {}
    -- Reset dirty flags for clean state
    Spear.needs_update = true
    Spear.needs_draw = false
end

--------------------------------------------------------------------------------
-- Spear trap prop definition
--------------------------------------------------------------------------------

---@class SpearTrapOptions
---@field fire_delay number|nil Time between shots (default: 2.0)
---@field cooldown_time number|nil Time after firing before next cycle (default: 0.5)
---@field initial_offset number|nil Timer offset for staggered firing (default: 0)
---@field flip boolean|nil If true, faces and fires right (default: false/left)
---@field auto_fire boolean|nil If false, only fires via external trigger (default: true)
---@field enabled boolean|nil If false, trap cannot fire (default: true)
local definition = {
    box = { x = 0, y = 0, w = 1, h = 1 },
    debug_color = "#FF00FF",  -- Magenta
    initial_state = "idle",

    on_spawn = function(prop, _, options)
        -- Clear stale spears on first spear_trap spawn of level load
        -- (Prop.all is empty after Prop.clear(), so no other spear_traps exist yet)
        local is_first = true
        for p, _ in pairs(Prop.all) do
            if p.type_key == "spear_trap" then
                is_first = false
                break
            end
        end
        if is_first then
            Spear.clear_all()
        end

        prop.fire_delay = options.fire_delay or DEFAULT_FIRE_DELAY
        prop.cooldown_time = options.cooldown_time or DEFAULT_COOLDOWN_TIME
        prop.initial_offset = options.initial_offset or 0
        prop.timer = prop.initial_offset
        prop.auto_fire = options.auto_fire ~= false  -- Default true for backward compatibility
        prop.enabled = options.enabled ~= false  -- Default true

        prop.animation = Animation.new(TRAP_ANIM, { start_frame = 0 })
        prop.animation:pause()

        -- Register for spatial audio queries
        proximity_audio.register(prop, {
            sound_id = "spear_trap_fire",
            radius = SOUND_RADIUS,
            max_volume = 1.0
        })
    end,

    --- Shared draw for all states - draws trap animation and spears
    ---@param prop table Prop instance to draw
    draw = function(prop)
        common.draw(prop)
        Spear.draw_all()
    end,

    states = {
        idle = {
            start = function(prop)
                -- Reset timer but preserve initial_offset for first cycle
                if prop.first_cycle_done then
                    prop.timer = 0
                end
                prop.animation = Animation.new(TRAP_ANIM, { start_frame = 0 })
                prop.animation:pause()
            end,
            update = function(prop, dt, player)
                Spear.update_all(dt, player)

                if not prop.enabled then return end

                prop.timer = prop.timer + dt
                if prop.auto_fire and prop.timer >= prop.fire_delay then
                    prop.first_cycle_done = true
                    Prop.set_state(prop, "firing")
                end
            end,
        },

        firing = {
            start = function(prop)
                prop.animation = Animation.new(TRAP_ANIM, { start_frame = 0 })
                prop.spear_spawned = false
                prop.fire_sound_played = false
            end,
            update = function(prop, dt, player)
                Spear.update_all(dt, player)

                -- Frame 5: mechanism releases, play sound slightly before visual spawn
                if not prop.fire_sound_played and prop.animation.frame >= 5 then
                    prop.fire_sound_played = true
                    if player and proximity_audio.is_in_range(player.x, player.y, prop) then
                        audio.play_sfx(audio.spear_trap_fire)
                    end
                end

                -- Frame 6: chamber is empty, spear has visually left the trap
                if not prop.spear_spawned and prop.animation.frame >= 6 then
                    prop.spear_spawned = true

                    -- Spawn position: front of trap (right side when facing right, left when facing left)
                    -- Center vertically (spear is 0.5 tiles, trap is 1 tile)
                    local spawn_x = prop.flipped == 1 and (prop.x + 1) or (prop.x - 0.25)
                    local spawn_y = prop.y + 0.25

                    Spear.spawn(spawn_x, spawn_y, prop.flipped)
                end

                if prop.animation:is_finished() then
                    Prop.set_state(prop, "cooldown")
                end
            end,
        },

        cooldown = {
            start = function(prop)
                prop.timer = 0
                -- Keep showing frame 6 (empty chamber)
                prop.animation = Animation.new(TRAP_ANIM, { start_frame = 7 })
                prop.animation:pause()
            end,
            update = function(prop, dt, player)
                Spear.update_all(dt, player)

                prop.timer = prop.timer + dt
                if prop.timer >= prop.cooldown_time then
                    Prop.set_state(prop, "idle")
                end
            end,
        }
    },

    --- Trigger the trap to fire (external API for pressure plates, etc.)
    ---@param prop table Spear trap prop instance
    fire = function(prop)
        if not prop.enabled then return end
        if prop.state_name == "idle" then
            Prop.set_state(prop, "firing")
        end
    end,

    --- Enable the trap (allows auto-fire and manual fire)
    ---@param prop table Spear trap prop instance
    enable = function(prop)
        prop.enabled = true
    end,

    --- Disable the trap (prevents auto-fire and manual fire)
    ---@param prop table Spear trap prop instance
    disable = function(prop)
        prop.enabled = false
    end,
}

return definition
