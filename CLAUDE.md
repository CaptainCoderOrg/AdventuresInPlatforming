# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

2D platformer game with combat mechanics built with Lua for the Canvas framework (web/HTML5 deployment). Entry point is `main.lua`. Game renders at variable resolution with 16px base tiles scaled 3x (48px tiles on screen).

## Running the Game

The game runs via the Canvas framework runtime. Debug controls:
- `P` - Toggle debug overlay (FPS, player state, bounding boxes)
  - Red boxes: Player hitbox
  - Yellow boxes: Projectile hitboxes
  - Green boxes: World collision geometry
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
  update(player, dt)    -- called each frame for logic (delta-time based)
  draw(player)          -- called each frame for rendering
}
```

**States:** idle, run, dash, air, wall_slide, wall_jump, climb, attack, throw, hammer, block, hit, death

States are registered in `player/init.lua`. Common utilities (gravity, jump, collision checks, ability handlers) are in `player/common.lua`.

### Animation System

Centralized animation system in `Animation/init.lua` using delta-time for frame-rate independence.

**Two-tier Architecture:**
- **Definitions** (`Animation.create_definition`): Shared animation templates with frame count, timing, dimensions
- **Instances** (`Animation.new`): Per-entity animation state with current frame, elapsed time, playback control

**Usage Pattern:**
```lua
-- Define animation (in player/common.lua)
IDLE = Animation.create_definition("player_idle", 6, {
    ms_per_frame = 200,  -- Milliseconds per frame
    width = 16,
    height = 16,
    loop = true
})

-- Create instance (in state)
player.animation = Animation.new(common.animations.IDLE)

-- Update and draw (every frame)
player.animation:play(dt)
player.animation:draw(x * sprites.tile_size, y * sprites.tile_size)
```

**Key Methods:**
- `play(dt)` - Advances animation by delta time (seconds)
- `draw(x, y)` - Renders at screen coordinates with flipping support
- `pause()`/`resume()` - Control playback
- `reset()` - Return to frame 0
- `is_finished()` - Check if non-looping animation completed

Animation definitions in `player/common.lua` specify timing in milliseconds (e.g., 80ms = 12.5 fps, 240ms = 4.2 fps).

### Effects System

Visual feedback system for transient particle effects. Manages one-shot animations that auto-cleanup when finished.

**Architecture:**
- Object pool pattern with `Effects.all` table
- Factory methods for specific effects (e.g., `Effects.create_hit()`)
- Integrated into main loop via `Effects.update(dt)` and `Effects.draw()`
- Uses Animation system for rendering

**Current Effects:**
- `HIT` - Impact effect (16×16px, 4 frames, 80ms/frame, non-looping)
- `SHURIKEN_HIT` - Shuriken impact (8×8px, 6 frames, non-looping)

**Usage:**
```lua
Effects.create_hit(x, y, direction)          -- Generic hit effect
Effects.create_shuriken_hit(x, y, direction) -- Shuriken-specific effect
```

Effects are positioned in tile coordinates and converted to screen pixels for rendering.

**Creating Custom Effects:**
Effects use the object pool pattern. New effect types require:
1. Animation definition in `Effects/init.lua`
2. Factory method (e.g., `Effects.create_shuriken_hit`)

### Projectile System

Physics-based throwable objects with collision detection.

**Architecture:**
- Object pool with `Projectile.all` table
- Full physics: velocity (vx, vy), gravity scaling
- Collision via sweeping trigger movement (`world.move_trigger`)
- Auto-cleanup on collision or out-of-bounds
- Custom hit effect callbacks per projectile type

**Projectile Properties:**
- Position in tile coordinates
- Box hitbox (0.5×0.5 tiles)
- Velocity in pixels/frame
- Direction-aware (for rendering and effects)

**Physics:**
```lua
-- Example: Axe projectile
velocity_x = direction * 16  -- pixels/frame
velocity_y = -3              -- upward arc
gravity = 20                 -- gravity scale
```

Projectiles only collide with solid world geometry (walls, platforms, slopes). Filtered to ignore triggers and player.

**Projectile Switching:**
- Player can toggle between projectile types (0 key or Gamepad SELECT)
- Available: `Projectile.get_axe()`, `Projectile.get_shuriken()`
- Current projectile stored in `player.projectile`

**Current Projectiles:**
- `AXE` - Throwing axe (8×8px, 4-frame spin, 100ms/frame, gravity-affected arc)
- `SHURIKEN` - Throwing star (8×8px, 5-frame spin, 24 px/frame velocity, no gravity)

**Custom Effect Callbacks:**
Projectiles support custom hit effects via factory pattern:
```lua
Projectile.new(x, y, direction, spec, Effects.create_shuriken_hit)
```

### Camera System

Complete camera management system in `Camera/init.lua` with entity following and dynamic framing.

**Architecture:**
- Entity following with smooth interpolation
- State-based vertical framing (default, falling, climbing)
- Horizontal look-ahead in movement direction
- Manual look control via right analog stick
- Epsilon snapping to prevent floating-point drift

**Framing Modes:**
- **Default**: Player at 2/3 from top (shows more below)
- **Falling**: Player at 10% from top (uses raycast to predict landing)
- **Climbing**: Varies with direction (0.333 down, 0.5 idle)

**Key Methods:**
```lua
Camera.new(viewport_w, viewport_h, world_w, world_h)
Camera:set_target(target)           -- Follow an entity
Camera:update(tile_size, dt, lerp)  -- Call each frame
Camera:apply_transform(tile_size)   -- Apply before drawing world
Camera:get_visible_bounds(tile_size) -- For culling
```

**Features:**
- **Look-ahead**: Camera leads 3 tiles in movement direction
- **Manual Look**: Right analog stick adjusts view (0.333 to 0.833 vertical range)
- **Falling Lerp Ramp**: Camera follows fall progressively faster (0.08 → 0.25 over 0.5s)

Configuration in `config/camera.lua` (lerp speeds, framing ratios, look-ahead distance).

### Combat System

Player combat abilities managed through state machine.

**Attack States:**

1. **Attack (Combo System)** - `player/attack.lua`
   - 3-hit combo chain (ATTACK_0 → ATTACK_1 → ATTACK_2)
   - Input queueing: can buffer next attack during current swing
   - Hold window: 0.16s after animation for combo input
   - Cooldown: 0.2s between combo chains
   - Frame speeds increase per hit: 50ms → 67ms → 83ms
   - All attacks 5 frames, 32px wide, non-looping

2. **Throw** - `player/throw.lua`
   - Launches selected projectile on entry (Axe or Shuriken)
   - Can move horizontally during throw
   - Duration: animation length (7 frames, 33ms/frame)

3. **Hammer** - `player/hammer.lua`
   - Heavy stationary attack (7 frames, 150ms/frame)
   - Locks player movement (vx=0, vy=0)
   - 32px wide sprite

4. **Block** - `player/block.lua`
   - Defensive stance (hold U or Gamepad RT)
   - Stops horizontal movement when grounded
   - Gravity still applies

**Player Properties:**
```lua
self.attacks = 3                -- Max combo hits
self.attack_cooldown = 0        -- Countdown timer
self.attack_state = {           -- Combo tracking
    count, next_anim_ix, remaining_time, queued
}
```

### Collision System

Uses HC library (`APIS/hc.lua`) with spatial hashing. Key patterns:
- Separated X/Y collision passes to prevent tunneling
- Ground probing for slope walking (`world.ground_probe()`)
- Trigger volumes for ladders and hit zones
- One-way platform support

**Trigger Movement:**
- `world.move_trigger(obj)` - Sweeping collision for trigger objects (projectiles)
- Moves shape and detects first collision along path
- Returns `{other, x, y}` collision info or nil

**Raycasting:**
- `world.raycast_down(player, max_distance)` - Finds solid ground below player
- Used by camera to predict landing during falls
- Filters out player collider and triggers
- Returns landing Y position (in tiles) or nil

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

## Controls

Unified input system in `controls.lua` supporting keyboard and gamepad.

**Combat Actions:**
- **Attack** - J key or Gamepad WEST (combo system)
- **Throw** - L key or Gamepad NORTH (projectile)
- **Hammer** - I key or Gamepad EAST (heavy attack)
- **Block** - U key or Gamepad RT (hold to defend)
- **Switch Projectile** - 0 key or Gamepad SELECT (toggle Axe/Shuriken)

**Movement:**
- Arrow keys or Gamepad D-pad/Left Stick
- Space or Gamepad SOUTH for jump

**Camera:**
- Right analog stick - Manual camera look (gamepad only, 0.15 deadzone)

**Debug:**
- P - Toggle debug overlay (FPS, state info, collision boxes)
- Y - Test hit state
- 1/2 - Switch music tracks

## Key Files

- `main.lua` - Game loop (on_start, game tick, draw)
- `player/init.lua` - Player state registry and core logic
- `player/common.lua` - Shared physics and collision utilities
- `Animation/init.lua` - Delta-time animation system
- `Effects/init.lua` - Visual effects manager (hit effects, particles)
- `Projectile/init.lua` - Throwable projectiles with physics
- `Camera/init.lua` - Camera system with following and framing
- `player/attack.lua` - Combat combo system
- `player/throw.lua` - Projectile throwing state
- `player/hammer.lua` - Heavy attack state
- `player/block.lua` - Defensive stance
- `world.lua` - HC collision engine wrapper (includes raycast)
- `platforms/init.lua` - Level geometry loader
- `sprites.lua` - Asset loading
- `controls.lua` - Unified keyboard/gamepad input
- `config.lua` - Debug flags, game settings, UI scaling
  - `config.ui.TILE` - Base tile size (16px)
  - `config.ui.SCALE` - Display scale multiplier (3x = 48px tiles on screen)
- `config/camera.lua` - Camera configuration (lerp, framing, look-ahead)

## Conventions

- Lua doc comments with `---@param` and `---@return`
- Module pattern (files return tables with functions)
- Snake_case for functions and variables
- Delta-time based animation (milliseconds per frame)
- Object pool pattern for entities (Effects, Projectiles)
- Tile coordinates for game logic (converted to pixels for rendering)
- Directional rendering via `flipped` property (1 = right, -1 = left)
