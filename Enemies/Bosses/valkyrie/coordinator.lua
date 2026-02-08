--- Valkyrie Boss Coordinator: Manages state for the single-entity valkyrie boss encounter.
--- Implements the interface needed by boss_health_bar (is_active, get_health_percent, etc).
local boss_health_bar = require("ui/boss_health_bar")
local music = require("audio/music")
local Prop = require("Prop")

local MAX_HEALTH = 100

-- Lazy-loaded to avoid circular dependency
local audio = nil

local coordinator = {
    active = false,
    total_max_health = MAX_HEALTH,
    total_health = MAX_HEALTH,
    enemy = nil,
    player = nil,
    boss_id = "valkyrie_boss",
    boss_name = "The Valkyrie",
    boss_subtitle = "Shieldmaiden of the Crypts",
    victory_pending = false,
    victory_timer = 0,
}

--- Register the valkyrie enemy with the coordinator.
---@param enemy table The valkyrie enemy instance
function coordinator.register(enemy)
    coordinator.enemy = enemy
    enemy.coordinator = coordinator
end

--- Start the boss encounter.
---@param player table Player reference
function coordinator.start(player)
    if coordinator.active then return end

    coordinator.active = true
    coordinator.player = player

    -- TODO: Replace with valkyrie-specific boss music when available
    audio = audio or require("audio")
    audio.play_music(audio.gnomo_boss)
end

--- Report damage dealt to the valkyrie.
---@param damage number Amount of damage dealt
function coordinator.report_damage(damage)
    coordinator.total_health = math.max(0, coordinator.total_health - damage)

    if coordinator.total_health <= 0 and coordinator.active then
        coordinator.trigger_victory()
    end
end

--- Get combined health as a percentage (0-1).
---@return number Health percentage
function coordinator.get_health_percent()
    if coordinator.total_max_health <= 0 then return 0 end
    return coordinator.total_health / coordinator.total_max_health
end

--- Get the boss name for display.
---@return string Boss name
function coordinator.get_boss_name()
    return coordinator.boss_name
end

--- Get the boss subtitle for display.
---@return string Boss subtitle
function coordinator.get_boss_subtitle()
    return coordinator.boss_subtitle
end

--- Check if the encounter is active.
---@return boolean True if boss fight is in progress
function coordinator.is_active()
    return coordinator.active
end

--- Trigger victory - kill the valkyrie and start defeated sequence.
function coordinator.trigger_victory()
    coordinator.active = false

    -- Kill the enemy
    if coordinator.enemy and not coordinator.enemy.marked_for_destruction then
        coordinator.enemy:die()
    end

    -- Fade out boss music
    music.fade_out(1)

    -- Show defeated animation
    boss_health_bar.show_defeated()

    -- Start victory timer to wait for defeated animation
    coordinator.victory_pending = true
    coordinator.victory_timer = 0
end

--- Update victory sequence state.
---@param dt number Delta time in seconds
function coordinator.update(dt)
    if not coordinator.victory_pending then return end

    coordinator.victory_timer = coordinator.victory_timer + dt

    if boss_health_bar.is_defeated_complete() then
        -- Mark boss as defeated
        local player = coordinator.player
        if player and player.defeated_bosses then
            player.defeated_bosses[coordinator.boss_id] = true
        end

        -- Open the boss door
        local door = Prop.find_by_id("valkrie_boss_door")
        if door and not door.marked_for_destruction then
            Prop.set_state(door, "opening")
        end

        coordinator.victory_pending = false
    end
end

--- Check if the victory sequence is complete.
---@return boolean True if defeated animation finished
function coordinator.is_sequence_complete()
    if coordinator.victory_pending then return false end
    return (coordinator.player
        and coordinator.player.defeated_bosses
        and coordinator.player.defeated_bosses[coordinator.boss_id]) == true
end

--- Set references needed by sub-modules.
---@param player table Player instance
---@param _camera table Camera instance (unused for valkyrie)
function coordinator.set_refs(player, _camera)
    coordinator.player = player
end

--- Reset coordinator state for level cleanup.
function coordinator.reset()
    coordinator.active = false
    coordinator.total_max_health = MAX_HEALTH
    coordinator.total_health = MAX_HEALTH
    coordinator.enemy = nil
    coordinator.player = nil
    coordinator.victory_pending = false
    coordinator.victory_timer = 0

    local cinematic = require("Enemies/Bosses/valkyrie/cinematic")
    cinematic.reset()
end

return coordinator
