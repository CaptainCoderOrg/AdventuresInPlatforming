--- Gnomo Boss: A colored gnomo variant for the boss encounter.
--- Each gnomo has individual health but contributes to a combined boss bar.
--- States come from phase modules controlled by the coordinator.
local Animation = require('Animation')
local sprites = require('sprites')
local coordinator = require('Enemies/Bosses/gnomo/coordinator')
local cinematic = require('Enemies/Bosses/gnomo/cinematic')
local common = require('Enemies/Bosses/gnomo/common')
local phase0 = require('Enemies/Bosses/gnomo/phase0')
local Effects = require('Effects')
local audio = require('audio')

local gnomo_boss = {}

--- Get the sprite sheet for a given color
---@param color string Color identifier (green/blue/magenta/red)
---@return string Sprite sheet asset key
local function get_sheet_for_color(color)
    local sheets = sprites.enemies.gnomo_boss
    return sheets[color] or sheets.green
end

--- Create animation definitions for a specific color
---@param color string Color identifier
---@return table Animation definitions
local function create_animations(color)
    local sheet = get_sheet_for_color(color)
    return {
        ATTACK = Animation.create_definition(sheet, 8, { ms_per_frame = 60, loop = false }),
        IDLE = Animation.create_definition(sheet, 5, { ms_per_frame = 150, row = 1 }),
        JUMP = Animation.create_definition(sheet, 9, { ms_per_frame = 80, loop = false, row = 2 }),
        RUN = Animation.create_definition(sheet, 6, { ms_per_frame = 100, row = 3 }),
        HIT = Animation.create_definition(sheet, 5, { ms_per_frame = 120, loop = false, row = 4 }),
        DEATH = Animation.create_definition(sheet, 6, { ms_per_frame = 100, loop = false, row = 5 }),
    }
end

--- Custom on_spawn handler to register with coordinator and set up color
---@param enemy table The gnomo boss instance
---@param spawn_data table Spawn data with gnomo_color field
local function on_spawn(enemy, spawn_data)
    -- Support both "color" and "gnomo_color" property names (Tiled uses gnomo_color)
    enemy.color = spawn_data and (spawn_data.gnomo_color or spawn_data.color) or "green"

    -- Create color-specific animations and store on enemy
    enemy.animations = create_animations(enemy.color)

    -- Set max_health early so coordinator.register can read it
    -- (on_spawn is called before Enemy.spawn sets combat properties)
    enemy.max_health = gnomo_boss.definition.max_health
    enemy.health = enemy.max_health

    -- Register with coordinator (encounter starts on first hit)
    coordinator.register(enemy, enemy.color)

    -- Claim initial platform based on spawn position
    local platform_index = common.find_closest_platform(enemy.x, enemy.y)
    coordinator.claim_platform(platform_index, enemy.color)
    enemy._platform_index = platform_index
end

--- Custom on_hit handler that routes damage to shared health pool.
--- Individual gnomos don't track health - coordinator manages phase transitions.
---@param self table The gnomo boss
---@param _source_type string Hit source type (unused)
---@param source table Hit source with damage, vx, x, is_crit
local function on_hit(self, _source_type, source)
    if self.invulnerable then return end

    -- Start encounter on first hit
    if not coordinator.is_active() then
        coordinator.start()
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

    -- Determine knockback direction (before report_damage, which may trigger death)
    if source and source.vx then
        self.hit_direction = source.vx > 0 and 1 or -1
    elseif source and source.x then
        self.hit_direction = source.x < self.x and 1 or -1
    else
        self.hit_direction = -1
    end

    -- Report damage to shared health pool (coordinator handles phase transitions)
    -- This may trigger die() which sets death state
    coordinator.report_damage(damage, self)

    -- Transition to hit state only if not already dying or in hit state
    -- (report_damage may have triggered death via phase transition)
    if self.states.hit and not self.marked_for_destruction and self.shape then
        if self.state ~= self.states.hit then
            self:set_state(self.states.hit)
        end
    end
end

--- Export enemy type definition
gnomo_boss.definition = {
    box = { w = 0.775, h = 0.775, x = 0.1125, y = 0.175 },
    gravity = 1.5,
    max_fall_speed = 20,
    max_health = 10,  -- Higher than regular gnomo (5)
    damage = 0.25,  -- Low contact damage; axes deal full damage
    loot = { xp = 20 },
    states = phase0.states,  -- Initial states, coordinator switches these on phase change
    initial_state = "idle",
    on_spawn = on_spawn,
    on_hit = on_hit,
}

--- Trigger handler: Starts the gnomo boss encounter cinematic.
--- Called when player enters the boss arena trigger zone.
--- Skipped if the boss has already been defeated.
---@param player table The player instance
function gnomo_boss.on_start(player)
    -- Skip if boss already defeated
    if player.defeated_bosses and player.defeated_bosses[coordinator.boss_id] then
        return
    end
    cinematic.start(player)
end

return gnomo_boss
