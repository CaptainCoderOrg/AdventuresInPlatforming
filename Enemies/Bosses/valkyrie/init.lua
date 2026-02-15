--- Valkyrie Boss: A single-entity boss encounter in the viking lair.
--- Phase-based fight with arena hazards. Phases swap the enemy state machine.
local coordinator = require('Enemies/Bosses/valkyrie/coordinator')
local cinematic = require('Enemies/Bosses/valkyrie/cinematic')
local common = require('Enemies/Bosses/valkyrie/common')
local enemy_common = require('Enemies/common')
local Effects = require('Effects')
local audio = require('audio')
local boss_health_bar = require('ui/boss_health_bar')

local valkyrie = {}

--- Custom on_spawn handler to register with coordinator.
---@param enemy table The valkyrie boss instance
---@param _spawn_data table Spawn data (unused)
local function on_spawn(enemy, _spawn_data)
    enemy.max_health = valkyrie.definition.max_health
    enemy.health = enemy.max_health
    enemy.animations = common.ANIMATIONS
    coordinator.register(enemy)
end

--- Custom on_hit handler that routes damage to coordinator's health pool.
--- Transitions to the current phase's hit state.
---@param self table The valkyrie boss
---@param _source_type string Hit source type (unused)
---@param source table Hit source with damage, vx, x, is_crit
local function on_hit(self, _source_type, source)
    if self.invulnerable then
        Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, 0, false)
        audio.play_solid_sound()
        return
    end

    -- Start encounter on first hit if not started by cinematic
    if not coordinator.is_active() then
        boss_health_bar.set_coordinator(coordinator)
        coordinator.start(self.target_player)
        coordinator.start_phase1()  -- Skip phase 0 intro when hit directly
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

    -- Report damage to coordinator (may trigger phase transition or victory)
    coordinator.report_damage(damage)

    -- Transition to current phase's hit state if not already dying
    if not self.marked_for_destruction and self.shape then
        local hit_state = self.states and self.states.hit
        local death_state = self.states and self.states.death
        if hit_state and self.state ~= hit_state and self.state ~= death_state then
            self:set_state(hit_state)
        end
    end
end

-- Default states (used as initial_state before phases are applied)
local default_states = {}

default_states.idle = {
    name = "idle",
    start = function(enemy)
        enemy_common.set_animation(enemy, common.ANIMATIONS.IDLE)
    end,
    update = function(enemy, _dt)
        if enemy.target_player then
            enemy.direction = enemy_common.direction_to_player(enemy)
            enemy.animation.flipped = enemy.direction
        end
    end,
    draw = common.draw_sprite,
}

default_states.hit = common.create_hit_state(function()
    return default_states.idle
end)

default_states.death = common.create_death_state()

--- Export enemy type definition
valkyrie.definition = {
    box = { w = 0.6875, h = 0.9375, x = 0.25, y = 0.625 },
    gravity = 1.5,
    max_fall_speed = 20,
    max_health = 75,
    armor = 1.5,
    damage = 1,
    forces_drop_through = true,
    loot = { xp = 1000, gold = { min = 1000, max = 1000 } },
    states = default_states,
    initial_state = "idle",
    on_spawn = on_spawn,
    on_hit = on_hit,
}

--- Trigger handler: Starts the valkyrie boss encounter cinematic.
--- Called when player enters the boss arena trigger zone.
--- Uses peaceful apology path if player has valkyrie_apology item.
---@param player table The player instance
function valkyrie.on_start(player)
    if player.defeated_bosses and player.defeated_bosses[coordinator.boss_id] then
        return
    end

    -- Check for apology item - peaceful resolution path
    if player.unique_items then
        for _, item in ipairs(player.unique_items) do
            if item == "valkyrie_apology" then
                local apology_path = require("Enemies/Bosses/valkyrie/apology_path")
                apology_path.start(player)
                return
            end
        end
    end

    boss_health_bar.set_coordinator(coordinator)
    cinematic.start(player)
end

return valkyrie
