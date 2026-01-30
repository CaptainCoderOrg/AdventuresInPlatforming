# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

2D platformer game with combat mechanics built with Lua for the Canvas framework (web/HTML5 deployment). Entry point is `main.lua`. Game renders at variable resolution with 16px base tiles scaled 3x (48px tiles on screen).

## Environment

There is no `lua` or `luac` interpreter installed locally. Code cannot be executed or syntax-checked via the command line.

## Running the Game

The game runs via the Canvas framework runtime. Debug controls:
- `P` - Toggle debug overlay (FPS, player state, bounding boxes)
  - Red boxes: Player hitbox
  - Yellow boxes: Projectile hitboxes
  - Green boxes: World collision geometry
  - Cyan boxes: Enemy hitboxes / Bridge colliders
  - Magenta boxes: Rotated enemy combat hitboxes (slope-following enemies)
  - Orange boxes: Sign hitboxes / Spear projectile hitboxes
  - Blue boxes: Player shield collider
- `O` - Toggle profiler overlay (per-system timing breakdown)
- `Y` - Test hit state
- `1`/`2` - Switch between level1/title music

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
- Attack: J / Gamepad WEST (combo)
- Throw: L / Gamepad NORTH
- Hammer: I / Gamepad EAST
- Block: U / Gamepad RT (hold)
- Switch Projectile: 0 / Gamepad SELECT

**Interaction:**
- Interact: Up Arrow / D-pad UP (rest at campfires, open chests, collect items, unlock doors)

**Movement:**
- Arrow keys / D-pad / Left Stick
- Jump: Space / Gamepad SOUTH

**Camera:**
- Right analog stick - Manual look (gamepad only)

## Key Files

### Core
- `main.lua` - Game loop (on_start, tick, draw)
- `config.lua` - Debug flags, UI scaling (`config.ui.TILE`, `config.ui.SCALE`)
- `controls.lua` - Unified keyboard/gamepad input
- `world.lua` - HC collision engine wrapper
- `combat.lua` - Combat spatial indexing
- `profiler.lua` - Per-system timing profiler
- `sprites/init.lua` - Sprite loading and pixel-alignment helpers

### Player
- `player/init.lua` - State registry and core logic
- `player/common.lua` - Physics, collision, stamina costs
- `player/shield.lua` - Shield lifecycle, blocking, knockback
- `player/stats.lua` - Stat percentage calculations (diminishing returns)
- `Animation/init.lua` - Delta-time animation system

### Entities
- `Enemies/init.lua` - Enemy manager
- `Prop/init.lua` - Prop system manager
- `Projectile/init.lua` - Throwable projectiles
- `Effects/init.lua` - Visual effects

### Audio
- `audio/init.lua` - Main audio with pools
- `proximity_audio/init.lua` - Distance-based volume

### UI
- `ui/hud.lua` - Screen aggregator
- `ui/title_screen.lua`, `ui/slot_screen.lua`, `ui/rest_screen.lua`

### Persistence
- `SaveSlots/init.lua` - 3-slot save system
- `Playtime/init.lua` - Session timer

### World
- `platforms/init.lua` - Level geometry loader
- `Camera/init.lua` - Camera following
- `Sign/init.lua` - Interactive signs

## Conventions

- Lua doc comments with `---@param` and `---@return`
- Module pattern (files return tables with functions)
- Snake_case for functions and variables
- Delta-time based animation (milliseconds per frame)
- Object pool pattern for entities
- Tile coordinates for game logic (converted to pixels for rendering)
  - `sprites.px(tiles)` - Converts to pixel-aligned screen coordinate
  - `sprites.stable_y(entity, tiles, offset)` - Pixel-aligned Y with hysteresis to prevent jitter (use for player/enemies)
- Directional rendering via `flipped` property (1 = right, -1 = left)
