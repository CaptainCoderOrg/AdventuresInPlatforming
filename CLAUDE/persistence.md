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

    -- Player stats (PLAYER_STAT_KEYS in SaveSlots/init.lua)
    max_health = 3,                  -- Current max HP
    max_stamina = 5,                 -- Current max SP
    max_energy = 4,                  -- Current max EP
    level = 1,                       -- Player level (progression)
    experience = 0,                  -- XP toward next level
    gold = 0,                        -- Currency for purchases
    defense = 0,                     -- Reduces incoming damage
    recovery = 0,                    -- Bonus regeneration rate
    critical_chance = 0,             -- Percent chance for critical hit
    stat_upgrades = {},              -- Track upgrade counts {Health=2, Stamina=1, ...}
    unique_items = {},               -- Collected unique items
    stackable_items = {},            -- Consumable items with counts (item_id -> count)
    equipped_items = {},             -- Set of equipped item_ids {throwing_axe=true, ...}
    active_weapon = nil,             -- Currently active weapon item_id (for quick swap)
    ability_slots = {},              -- 6 ability slots {item_id or nil, ...}
    visited_campfires = {},          -- Fast travel locations {level_id:name -> {name, level_id, x, y}}
    defeated_bosses = {},            -- Set of defeated boss ids {boss_id -> true}
    dialogue_flags = {},             -- Dialogue condition flags {flag_name -> true}
    journal = {},                    -- Quest journal entries {entry_id -> "active"|"complete"}
    journal_read = {},               -- Read tracking for journal unread indicators {entry_id -> true}
    upgrade_tiers = {},              -- Equipment upgrade tiers purchased {item_id -> tier_number}
    difficulty = "normal",           -- Difficulty setting ("normal" or "easy")

    -- Prop persistence (cross-level)
    prop_states = {},                -- Map of prop_key -> state_data

    -- Map exploration
    visited_bounds = {},             -- Array of visited camera_bounds indices (fog-of-war)
}
```

**Transient State** (preserved during level transitions, reset at campfires):
```lua
SaveSlots.TRANSIENT_KEYS = { "damage", "energy_used", "stamina_used", "charge_state" }
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

### Deep Copy Handlers

`copy_stat_value()` has dedicated handlers for complex data types that require more than shallow copy:

- **`visited_map`** — Deep-copies nested array structure (each entry is array of bounds). Not in `SHALLOW_COPY_KEYS`.
- **`ability_slots`** — Creates 6-element array with `false` for nil entries (ensures correct JSON serialization of sparse arrays). Not in `SHALLOW_COPY_KEYS`.

### Dev Slots

Development save/load using localstorage with `"dev_slot_N"` keys. Only available when `config.DEV_MODE = true`.

```lua
SaveSlots.save_dev_slot(slot_num, data)  -- Save to dev slot
SaveSlots.load_dev_slot(slot_num)        -- Load from dev slot (returns data or nil)
```

Debug keys: `0` saves to dev slot, `9` copies slot 1 to slot 3.

### LocalStorage Keys

- `"save_slot_1"`, `"save_slot_2"`, `"save_slot_3"`
- `"dev_slot_N"` — Dev save slots (DEV_MODE only)
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
2. `Prop.reset_all()` resets non-persistent props to initial states
3. `Prop.reapply_persistent_effects()` re-fires persistent prop callbacks (e.g. buttons re-disable targets)
4. `rest.start()` saves full state to active slot
5. `Playtime.pause()` stops timer
6. Rest screen shows with circular viewport
7. All enemies respawn via `Enemy.respawn()`
8. "Continue" -> `continue_from_checkpoint()` reloads level

### Active Slot Tracking

- `active_slot` variable (1-3) tracks current save slot
- All saves go to active slot
- Death "Continue" restores from active slot

## Key Files

- `SaveSlots/init.lua` - Save persistence layer (3 slots, localStorage)
- `Playtime/init.lua` - Session playtime tracking
- `RestorePoint/init.lua` - Legacy checkpoint (kept for backward compatibility)
- `main.lua` - Game flow functions (load_slot, init_level, cleanup_level)
