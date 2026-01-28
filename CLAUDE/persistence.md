# Persistence System

<!-- QUICK REFERENCE
- Save slots: SaveSlots.get(index), SaveSlots.set(index, data)
- 3 save slots using localStorage
- Playtime: Playtime.update(dt), Playtime.get(), Playtime.pause()
- Game flow: load_slot() -> start_new_game() or continue_from_checkpoint()
- Active slot tracking via active_slot variable (1-3)
-->

## Save Slot System

Multi-slot save system using localStorage with 3 save slots.

### Architecture

- Persistence layer in `SaveSlots/init.lua`
- In-memory cache of all slots loaded on init
- JSON encoding for localStorage
- Automatic migration from legacy `restore_point` data to slot 1

### Save Data Structure

```lua
{
    -- Required (position/level)
    x = player_x,                    -- Tile coordinate
    y = player_y,                    -- Tile coordinate
    level_id = "level1",             -- Level identifier
    direction = 1,                   -- Facing direction (-1 or 1)

    -- Metadata
    campfire_name = "Campfire",      -- Display name for UI
    playtime = 3600.5,               -- Total seconds played

    -- Player stats (restored via stat_keys in main.lua)
    max_health = 3,                  -- Current max HP
    level = 1,                       -- Player level (progression)
    experience = 0,                  -- XP toward next level
    gold = 0,                        -- Currency for purchases
    defense = 0,                     -- Reduces incoming damage
    strength = 5,                    -- Base damage multiplier
    critical_chance = 0,             -- Percent chance for critical hit

    -- Prop persistence (cross-level)
    prop_states = {},                -- Map of prop_key -> state_data
}
```

### Key Methods

```lua
SaveSlots.init()                    -- Load all 3 slots from localStorage
SaveSlots.get(slot_index)           -- Retrieve slot data (nil if empty)
SaveSlots.set(slot_index, data)     -- Save data to slot
SaveSlots.has_data(slot_index)      -- Check if slot has save
SaveSlots.clear(slot_index)         -- Delete slot data
SaveSlots.format_playtime(seconds)  -- Format HH:MM:SS display string
```

### LocalStorage Keys

- `"save_slot_1"`, `"save_slot_2"`, `"save_slot_3"`
- Legacy: `"restore_point"` (auto-migrated to slot 1 if found)

## Playtime System

Session-based playtime tracking that persists with save data.

### Architecture

- Singleton module in `Playtime/init.lua`
- Tracks elapsed seconds with pause/resume support
- Integrated with rest state and save system

### Key Methods

```lua
Playtime.reset()           -- Zero out playtime
Playtime.set(seconds)      -- Restore from save data
Playtime.get()             -- Current elapsed time
Playtime.update(dt)        -- Increment timer each frame
Playtime.pause()           -- Stop counting (during menus)
Playtime.resume()          -- Resume counting (during gameplay)
Playtime.is_paused()       -- Query pause state
```

## Game Flow

Main game loop integration for save/load and screen transitions.

### Startup Sequence

1. `on_start()` initializes all subsystems
2. Title screen shown automatically
3. "Play Game" -> Slot screen
4. Slot selection -> `load_slot(slot_index)`

### Load Slot Flow

```lua
load_slot(slot_index)              -- Store active_slot, check for data
start_new_game()                   -- Clear slot, spawn at level start
continue_from_checkpoint()         -- Restore position/stats/playtime
init_level(level, spawn, player_data)  -- Initialize level with optional save
cleanup_level()                    -- Remove colliders before reload
```

### Rest (Campfire) Flow

1. Player touches campfire -> enters `rest` state
2. `rest.start()` saves full state to active slot
3. `Playtime.pause()` stops timer
4. Rest screen shows with circular viewport
5. All enemies respawn via `Enemy.respawn()`
6. "Continue" -> `continue_from_checkpoint()` reloads level

### Active Slot Tracking

- `active_slot` variable (1-3) tracks current save slot
- All saves go to active slot
- Death "Continue" restores from active slot

## Key Files

- `SaveSlots/init.lua` - Save persistence layer (3 slots, localStorage)
- `Playtime/init.lua` - Session playtime tracking
- `RestorePoint/init.lua` - Legacy checkpoint (kept for backward compatibility)
- `main.lua` - Game flow functions (load_slot, init_level, cleanup_level)
