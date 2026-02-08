--- Valkyrie Boss: A single-entity boss encounter in the viking lair.
--- Currently has idle/hit/death states for testing.
local Animation = require('Animation')
local sprites = require('sprites')
local coordinator = require('Enemies/Bosses/valkyrie/coordinator')
local cinematic = require('Enemies/Bosses/valkyrie/cinematic')
local common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')
local boss_health_bar = require('ui/boss_health_bar')

local canvas = require('canvas')
local config = require('config')
local Prop = require('Prop')

local valkyrie = {}

local FRAME_W = 40
local FRAME_H = 29

-- Cached sprite dimensions (avoid per-frame multiplication)
local SPRITE_WIDTH = FRAME_W * config.ui.SCALE
local SPRITE_HEIGHT = FRAME_H * config.ui.SCALE
local BASE_WIDTH = 16 * config.ui.SCALE   -- 1-tile character anchor width
local EXTRA_HEIGHT = (FRAME_H - 16) * config.ui.SCALE  -- Sprite extends above 1-tile base
local Y_NUDGE = 13 * config.ui.SCALE       -- Shift sprite down to align with hitbox
local X_NUDGE_RIGHT = 10 * config.ui.SCALE -- Extra rightward shift when facing right

--- Draw valkyrie sprite (40x29 sprite with character anchored at bottom).
--- Uses canvas transforms to flip visually while hitbox stays fixed.
---@param enemy table The enemy instance
local function draw_sprite(enemy)
    if not enemy.animation then return end

    local definition = enemy.animation.definition
    local frame = enemy.animation.frame
    local x = sprites.px(enemy.x)
    local lift = Prop.get_pressure_plate_lift(enemy)
    local y = sprites.stable_y(enemy, enemy.y, -lift)

    canvas.save()

    if enemy.direction == 1 then
        canvas.translate(x + SPRITE_WIDTH - BASE_WIDTH + X_NUDGE_RIGHT, y - EXTRA_HEIGHT + Y_NUDGE)
        canvas.scale(-1, 1)
    else
        canvas.translate(x - BASE_WIDTH, y - EXTRA_HEIGHT + Y_NUDGE)
    end

    local sheet_frame = frame + (definition.frame_offset or 0)
    local source_y = (definition.row or 0) * definition.height
    canvas.draw_image(definition.name, 0, 0,
        SPRITE_WIDTH, SPRITE_HEIGHT,
        sheet_frame * definition.width, source_y,
        definition.width, definition.height)
    canvas.restore()
end

-- Animation definitions (single sheet, rows by animation)
local sheet = sprites.enemies.shieldmaiden.sheet
local ANIMATIONS = {
    ATTACK = Animation.create_definition(sheet, 5, { ms_per_frame = 60, loop = false, width = FRAME_W, height = FRAME_H, row = 0 }),
    BLOCK = Animation.create_definition(sheet, 3, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 1 }),
    IDLE = Animation.create_definition(sheet, 4, { ms_per_frame = 150, width = FRAME_W, height = FRAME_H, row = 2 }),
    JUMP = Animation.create_definition(sheet, 2, { ms_per_frame = 80, loop = false, width = FRAME_W, height = FRAME_H, row = 3 }),
    FALL = Animation.create_definition(sheet, 3, { ms_per_frame = 100, width = FRAME_W, height = FRAME_H, row = 4 }),
    LAND = Animation.create_definition(sheet, 1, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 5 }),
    RUN = Animation.create_definition(sheet, 6, { ms_per_frame = 100, width = FRAME_W, height = FRAME_H, row = 6 }),
    HIT = Animation.create_definition(sheet, 3, { ms_per_frame = 120, loop = false, width = FRAME_W, height = FRAME_H, row = 7 }),
    DEATH = Animation.create_definition(sheet, 11, { ms_per_frame = 100, loop = false, width = FRAME_W, height = FRAME_H, row = 8 }),
}

-- States (minimal for testing: idle, hit, death)
local states = {}

states.idle = {
    name = "idle",
    start = function(enemy)
        common.set_animation(enemy, ANIMATIONS.IDLE)
    end,
    update = function(enemy, _dt)
        if enemy.target_player then
            enemy.direction = common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end
    end,
    draw = draw_sprite,
}

states.hit = {
    name = "hit",
    start = function(enemy)
        common.set_animation(enemy, ANIMATIONS.HIT)
        enemy.vx = (enemy.hit_direction or -1) * 2
    end,
    update = function(enemy, dt)
        enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.animation:is_finished() then
            enemy:set_state(states.idle)
        end
    end,
    draw = draw_sprite,
}

states.death = {
    name = "death",
    start = function(enemy)
        common.set_animation(enemy, ANIMATIONS.DEATH)
        enemy.vx = (enemy.hit_direction or -1) * 4
        enemy.vy = 0
        enemy.gravity = 0
    end,
    update = function(enemy, dt)
        enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.animation:is_finished() then
            enemy.marked_for_destruction = true
        end
    end,
    draw = draw_sprite,
}

--- Custom on_spawn handler to register with coordinator.
---@param enemy table The valkyrie boss instance
---@param _spawn_data table Spawn data (unused)
local function on_spawn(enemy, _spawn_data)
    enemy.max_health = valkyrie.definition.max_health
    enemy.health = enemy.max_health
    enemy.animations = ANIMATIONS
    coordinator.register(enemy)
end

--- Custom on_hit handler that routes damage to coordinator's health pool.
---@param self table The valkyrie boss
---@param _source_type string Hit source type (unused)
---@param source table Hit source with damage, vx, x, is_crit
local function on_hit(self, _source_type, source)
    if self.invulnerable then return end

    -- Start encounter on first hit if not started by cinematic
    if not coordinator.is_active() then
        boss_health_bar.set_coordinator(coordinator)
        coordinator.start(self.target_player)
    end

    local damage = (source and source.damage) or 1
    local is_crit = source and source.is_crit

    -- Apply armor reduction, then crit multiplier
    damage = math.max(0, damage - self:get_armor())
    if is_crit then
        damage = damage * 2
    end

    Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage, is_crit)

    if damage <= 0 then
        audio.play_solid_sound()
        return
    end

    audio.play_squish_sound()

    -- Determine knockback direction
    if source and source.vx then
        self.hit_direction = source.vx > 0 and 1 or -1
    elseif source and source.x then
        self.hit_direction = source.x < self.x and 1 or -1
    else
        self.hit_direction = -1
    end

    -- Report damage to coordinator (may trigger victory/death)
    coordinator.report_damage(damage)

    -- Transition to hit state if not already dying
    if not self.marked_for_destruction and self.shape then
        if self.state ~= states.hit and self.state ~= states.death then
            self:set_state(states.hit)
        end
    end
end

--- Export enemy type definition
valkyrie.definition = {
    box = { w = 0.6875, h = 0.9375, x = 0.25, y = 0.625 },
    gravity = 1.5,
    max_fall_speed = 20,
    max_health = 100,
    armor = 1,
    damage = 1,
    loot = { xp = 50 },
    states = states,
    initial_state = "idle",
    on_spawn = on_spawn,
    on_hit = on_hit,
}

--- Trigger handler: Starts the valkyrie boss encounter cinematic.
--- Called when player enters the boss arena trigger zone.
---@param player table The player instance
function valkyrie.on_start(player)
    if player.defeated_bosses and player.defeated_bosses[coordinator.boss_id] then
        return
    end

    boss_health_bar.set_coordinator(coordinator)
    cinematic.start(player)
end

return valkyrie
