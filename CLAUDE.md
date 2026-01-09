# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

2D platformer game built with Lua for the Canvas framework (web/HTML5 deployment). Entry point is `main.lua`. Game renders at 512x512 pixels with 16px tiles scaled 2x.

## Running the Game

The game runs via the Canvas framework runtime. Debug controls:
- `P` - Toggle debug overlay (FPS, player state, bounding boxes)
- `Y` - Test hit state
- `1`/`2` - Switch between level1/title music

## Architecture

### Player State Machine

The player uses a state machine pattern. Each state in `player/` is a table with 4 required functions:

```lua
state = {
  name = "state_name",
  start(player)         -- called on state entry
  input(player)         -- called each frame for input
  update(player, dt)    -- called each frame for logic
  draw(player)          -- called each frame for rendering
}
```

States are registered in `player/init.lua`. Common utilities (gravity, jump, collision checks) are in `player/common.lua`.

### Collision System

Uses HC library (`APIS/hc.lua`) with spatial hashing. Key patterns:
- Separated X/Y collision passes to prevent tunneling
- Ground probing for slope walking (`world.ground_probe()`)
- Trigger volumes for ladders and hit zones
- One-way platform support

### Level Format

Levels in `levels/` use ASCII tile maps:
- `#` = solid wall
- `X` = isolated tile
- `/` = right-leaning slope
- `\` = left-leaning slope
- `H` = ladder segment
- `S` = spawn point

### Physics Constants

Defined in `player/common.lua`:
- Gravity: 1.5 px/frame²
- Jump velocity: 21 px/frame
- Max fall speed: 20 px/frame
- Move speed: 6 px/frame

## Key Files

- `main.lua` - Game loop (on_start, game tick, draw)
- `player/init.lua` - Player state registry and core logic
- `player/common.lua` - Shared physics and collision utilities
- `world.lua` - HC collision engine wrapper
- `platforms/init.lua` - Level geometry loader
- `sprites.lua` - Asset loading and animation system
- `controls.lua` - Unified keyboard/gamepad input
- `config.lua` - Debug flags and game settings

## Conventions

- Lua doc comments with `---@param` and `---@return`
- Module pattern (files return tables with functions)
- Snake_case for functions and variables
- Animations use frame-based timing with flip-based directional rendering
