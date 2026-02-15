# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

2D platformer game with combat mechanics built with Lua for the Canvas framework (web/HTML5 deployment). Entry point is `main.lua`. Game renders at variable resolution with 16px base tiles scaled 3x (48px tiles on screen).

## Environment

There is no `lua` or `luac` interpreter installed locally. Code cannot be executed or syntax-checked via the command line.

## Canvas API

The game uses the Canvas framework. API documentation is in `APIS/docs/canvas.md` with detailed docs in `APIS/docs/canvas/`. Key references:
- Drawing: `canvas.draw_text(x, y, text)`, `canvas.set_color()`, `canvas.fill_rect()`
- Text: `canvas.set_font_family()`, `canvas.set_font_size()`, `canvas.set_text_align()`
- Assets: `canvas.assets.load_image()`, `canvas.assets.load_font()`, `canvas.draw_image()`

## Running the Game

The game runs via the Canvas framework runtime. All debug keys require `config.DEV_MODE = true` in `config.lua`.

Debug controls:
- `P` - Toggle debug overlay (FPS, player state, bounding boxes)
  - Red boxes: Player hitbox
  - Yellow boxes: Projectile hitboxes / Patrol areas (filled)
  - Green boxes: World collision geometry
  - Cyan boxes: Enemy hitboxes / Bridge colliders
  - Magenta boxes: Rotated enemy combat hitboxes (slope-following enemies)
  - Orange boxes: Sign hitboxes / Spear projectile hitboxes
  - Blue boxes: Player shield collider
- `O` - Toggle profiler overlay (per-system timing breakdown)
- `Y` - Test hit state
- `H` - Grant Minor Healing and assign to first empty ability slot
- `F1`-`F7` - Toggle abilities (double jump, dash, wall slide, hammer, axe, shuriken, shield)
- `0` - Save to dev slot (localstorage)
- `9` - Copy slot 1 to slot 3
- `1`/`2` - Switch between level1/title music (non-debug mode only)

## Architecture

Detailed documentation for each system is in the `CLAUDE/` directory:

| Topic | File | Description |
|-------|------|-------------|
| Player | [CLAUDE/player.md](CLAUDE/player.md) | State machine, combat, stamina/energy, animation |
| Entities | [CLAUDE/entities.md](CLAUDE/entities.md) | Enemies, props, projectiles, effects |
| Audio | [CLAUDE/audio.md](CLAUDE/audio.md) | Sound pools, spatial audio, proximity system |
| Collision | [CLAUDE/collision.md](CLAUDE/collision.md) | HC library, combat indexing, bridges |
| UI | [CLAUDE/ui.md](CLAUDE/ui.md) | Screens, dialogs, HUD widgets |
| Persistence | [CLAUDE/persistence.md](CLAUDE/persistence.md) | Save slots, playtime, game flow |
| Levels | [CLAUDE/levels.md](CLAUDE/levels.md) | Level format, signs, camera system |

### Key Patterns

**State Machine:** Player, enemies, and props all use the same pattern:
```lua
states = {
  state_name = {
    start(entity)      -- called on state entry
    update(entity, dt) -- called each frame
    draw(entity)       -- called each frame
  }
}
```

**Object Pool:** Entities use pooled tables for efficient management:
- `Enemy.all`, `Prop.all`, `Projectile.all`, `Effects.all`

**Common Utilities:** Shared functions in `*/common.lua` files reduce duplication.

### Physics Constants

Defined in `player/common.lua`:
- Gravity: 1.5 px/frame²
- Jump velocity: 21 px/frame
- Max fall speed: 20 px/frame
- Move speed: 6 px/frame

## Controls

Unified input system in `controls.lua` supporting keyboard and gamepad.

**Combat:**
- Attack: Mouse Left / Gamepad WEST (combo)
- Ability 1: Q / Gamepad NORTH
- Ability 2: Mouse Right / Gamepad EAST
- Ability 3: E / Gamepad LB
- Ability 4: Z / Gamepad LT
- Ability 5: Shift / Gamepad RB
- Ability 6: F / Gamepad RT
- Swap Weapon: R / Gamepad SELECT (cycle equipped weapons)

**Interaction:**
- Interact: W / D-pad UP (rest at campfires, open chests, collect items, unlock doors)

**Movement:**
- WASD / D-pad / Left Stick
- Jump: Space / Gamepad SOUTH
- Climb drop: Jump + S while climbing (drops without jumping)

**Camera:**
- Right analog stick - Manual look (gamepad only)

## Key Files

### Core
- `main.lua` - Game loop (on_start, tick, draw)
- `config.lua` - Debug flags, UI scaling (`config.ui.TILE`, `config.ui.SCALE`), `DEV_MODE` gates debug shortcuts
- `controls.lua` - Unified keyboard/gamepad input handling
- `config/controls.lua` - Control action definitions, default bindings, display names
- `world.lua` - HC collision engine wrapper
- `combat.lua` - Combat spatial indexing
- `profiler.lua` - Per-system timing profiler
- `sprites/init.lua` - Sprite loading and pixel-alignment helpers
- `sprites/ui.lua` - UI sprite asset loader (HUD widgets, inventory, secondary bar)
- `sprites/items.lua` - Unique item sprite asset loader

### Player
- `player/init.lua` - State registry and core logic
- `player/common.lua` - Physics, collision, stamina costs
- `player/shield.lua` - Shield lifecycle, blocking, knockback
- `player/stats.lua` - Stat percentage calculations (diminishing returns)
- `player/weapon_sync.lua` - Equipped weapon/secondary management and ability sync
- `player/heal_channel.lua` - Heal channeling system (energy-to-health conversion)
- `player/dash.lua` - Dash state and ghost trail visual system (object-pooled translucent snapshots)
- `Animation/init.lua` - Delta-time animation system

### Entities
- `Enemies/init.lua` - Enemy manager
- `Enemies/Bosses/gnomo/` - Gnomo boss encounter (coordinator, phases 0-4, cinematic, victory)
- `Enemies/Bosses/valkyrie/` - Valkyrie boss encounter (coordinator, phases 0-4, cinematic, victory, apology_path)
- `Prop/init.lua` - Prop system manager
- `Prop/npc_common.lua` - NPC factory for dialogue NPCs
- `Prop/unique_item_registry.lua` - Item definitions and equipment types
- `Prop/boss_block.lua` - Dynamic wall prop for boss encounters (appear/disappear with collider toggling)
- `Projectile/init.lua` - Throwable projectiles
- `Effects/init.lua` - Visual effects
- `Collectible/init.lua` - Loot collectibles (gold, XP, health, energy particles)
- `sprites/npcs.lua` - NPC sprite asset loader

### Audio
- `audio/init.lua` - Main audio with pools
- `proximity_audio/init.lua` - Distance-based volume

### UI
- `ui/hud.lua` - Screen aggregator
- `ui/boss_health_bar.lua` - Boss encounter health bar with intro animation
- `ui/title_screen.lua`, `ui/slot_screen.lua`, `ui/rest_screen.lua`
- `ui/status_panel.lua` - Player stats and inventory panel
- `ui/inventory_grid.lua` - 5x3 item grid with equipment management
- `ui/ability_slots.lua` - Ability slot assignment component for status panel
- `ui/secondary_bar.lua` - Secondary abilities HUD widget (6 fixed ability slots)
- `ui/pickup_dialogue.lua` - Equip/inventory dialogue for collectible items
- `ui/simple_dialogue.lua` - 9-slice dialogue box with keybinding sprites
- `ui/map_panel.lua` - Minimap panel with fog-of-war for rest/pause screen
- `ui/fast_travel_panel.lua` - Fast travel destination panel for rest screen
- `ui/journal_panel.lua` - Quest journal panel for rest/pause screen
- `ui/journal_toast.lua` - Toast notification for new journal entries
- `ui/upgrade_screen.lua` - Equipment upgrade workshop UI (split-screen with NPC)
- `ui/credits_screen.lua` - Scrolling credits with typewriter effect and animated sprites

### Upgrade
- `upgrade/registry.lua` - Upgrade tier definitions (costs, materials, effects per item)
- `upgrade/effects.lua` - Centralized stat lookups for upgrade bonuses (weapon damage, stamina cost, attack speed, projectile damage, energy cost, max charges, heal rate, recharge)
- `upgrade/transactions.lua` - Purchase validation and execution for equipment upgrades

### Persistence
- `SaveSlots/init.lua` - 3-slot save system
- `Playtime/init.lua` - Session timer

### Journal
- `journal/entries.lua` - Static registry of journal entry definitions (title, description, parent, sort_order)
- `dialogue/manager.lua` - Dialogue flag/condition system with journal_add/journal_complete actions

### World
- `platforms/init.lua` - Level geometry loader
- `platforms/tiled_loader.lua` - Tiled map format parser
- `triggers/init.lua` - Event trigger zone manager
- `triggers/registry.lua` - Static mapping of trigger names to handler functions
- `Camera/init.lua` - Camera following
- `Sign/init.lua` - Interactive signs

## Conventions

- **No dynamic requires** - Canvas does static analysis to determine which files to include in exports. Never compute require paths at runtime:
  ```lua
  -- BAD: Canvas cannot trace this
  local module = require("Maps/" .. map_name)

  -- GOOD: Use a registry with static requires
  local registry = require("Maps/registry")
  local module = registry[map_name]
  ```
  Registries exist at `platforms/tileset_registry.lua` and `Maps/registry.lua`. When adding new tilesets or maps, update the corresponding registry.
- **Never modify `Tilemaps/`** - All files in this directory are generated by exporting from Tiled. Edit the `.tsx` source files in Tiled, then re-export.
- Lua doc comments with `---@param` and `---@return`
- Module pattern (files return tables with functions)
- Snake_case for functions and variables
- Delta-time based animation (milliseconds per frame)
- Object pool pattern for entities
- Tile coordinates for game logic (converted to pixels for rendering)
  - `sprites.px(tiles)` - Converts to pixel-aligned screen coordinate
  - `sprites.stable_y(entity, tiles, offset)` - Pixel-aligned Y with hysteresis to prevent jitter (use for player/enemies)
- Directional rendering via `flipped` property (1 = right, -1 = left)
