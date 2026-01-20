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
  - Cyan boxes: Enemy hitboxes / Bridge colliders
  - Orange boxes: Sign hitboxes
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

**States:** idle, run, dash, air, wall_slide, wall_jump, climb, attack, throw, hammer, block, hit, death, rest

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

### Enemy System

AI-controlled enemies with state machines and combat integration.

**Architecture:**
- Object pool pattern with `Enemy.all` table
- State machine identical to player (start, update, draw functions)
- Registration system: `Enemy.register(key, definition)` in main.lua
- Spawning from level data: `Enemy.spawn(type_key, x, y)`

**Enemy Properties:**
```lua
enemy = {
    x, y,                    -- Position in tile coordinates
    vx, vy,                  -- Velocity in pixels/frame
    direction,               -- Facing (-1 left, 1 right)
    health, max_health,      -- Health tracking
    damage,                  -- Contact damage to player
    is_enemy = true,         -- Collision filter flag
    states,                  -- State machine definition
    state,                   -- Current active state
}
```

**State Machine:**
Each enemy type defines states with the same pattern as player:
```lua
state = {
    name = "state_name",
    start = function(enemy, definition) end,
    update = function(enemy, dt) end,
    draw = function(enemy) end,
}
```

**Current Enemies:**
- **Ratto** - Rat enemy with patrol/chase AI
  - States: idle, run, chase, hit, death
  - Detection range: 5 tiles
  - Health: 5 HP, Contact damage: 1
  - Chase speed: 6 px/frame (faster than patrol)
- **Worm** - Simple patrol enemy
  - States: run, death
  - Health: 1 HP, Contact damage: 1
  - Patrol speed: 0.5 px/frame
  - Reverses at walls and platform edges
- **Spike Slug** - Defensive enemy with invincibility mechanic
  - States: run, defend, stop_defend, hit, death
  - Health: 3 HP, Contact damage: 1
  - Detection range: 6 tiles (triggers defense)
  - `is_defending` flag blocks all damage while in defend state

**Damage System:**
Enemies can take damage from multiple sources:
```lua
enemy:on_hit("weapon", { damage = player.weapon_damage, x = player.x })
enemy:on_hit("projectile", projectile)
```
- Knockback direction calculated from damage source
- Transitions to hit state, then death if health <= 0

**Player Contact:**
- `Enemy:check_player_overlap(player)` called each frame
- Deals `enemy.damage` to player on collision
- Player invincibility frames prevent rapid hits

**Common Utilities (`Enemies/common.lua`):**
Shared functions to reduce duplication across enemy types:
- `common.player_in_range(enemy, range)` - Distance check in tiles
- `common.direction_to_player(enemy)` - Returns -1 or 1 toward player
- `common.draw(enemy)` - Standard sprite rendering
- `common.is_blocked(enemy)` - Checks wall or edge in current direction
- `common.reverse_direction(enemy)` - Flip direction and animation
- `common.create_death_state(animation)` - Factory for standard death state

**Edge Detection:**
Enemies automatically detect platform edges to avoid falling:
- `enemy.edge_left` / `enemy.edge_right` - True if no ground ahead
- Uses `world.point_has_ground(x, y)` to probe for solid geometry
- Combined with `enemy.wall_left` / `wall_right` in `common.is_blocked()`

**Creating New Enemies:**
1. Create definition file in `Enemies/` (animations, states, properties)
2. Use `common.*` utilities for shared behaviors
3. Register in main.lua: `Enemy.register("name", require("Enemies/name"))`
4. Add spawn character to level format (R=ratto, W=worm, G=spike_slug)

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
   - **Sword Hitbox**: 1.0 tile wide, extends from player's front edge
   - **Active Frames**: Frame 2-3 (ATTACK_2 starts on frame 1)
   - **Damage**: `player.weapon_damage` (2.5) applied via `enemy:on_hit()`
   - **Hit Tracking**: `attack_state.hit_enemies` prevents double-hits per swing

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

5. **Hit** - `player/hit.lua`
   - Entered when player takes damage
   - Knockback away from damage source (2 px/frame)
   - Animation duration: 240ms (3 frames @ 80ms)
   - Uses centralized input queue for buffering

**Input Queuing System:**
Centralized input buffering for locked states (hit, throw, hammer, attack).

- **Queue Storage**: `player.input_queue` tracks pending inputs (jump, attack, throw)
- **During Locked States**: `common.queue_inputs(player)` captures button presses
- **On State Exit**: `common.process_input_queue(player)` executes queued actions
- **Priority Order**: Attack > Throw > Jump
- **Cooldown Handling**: Attack/throw persist in queue until cooldown expires
- **Cooldown Check**: `common.check_cooldown_queues(player)` in idle/run/air states

**Key Functions (`player/common.lua`):**
```lua
common.queue_input(player, "attack")     -- Add input to queue
common.clear_input_queue(player)         -- Clear all queued inputs
common.queue_inputs(player)              -- Capture current button presses
common.process_input_queue(player)       -- Execute queued actions (returns true if transitioned)
common.check_cooldown_queues(player)     -- Check for cooldown-blocked inputs
```

**Invincibility System:**
- **Duration**: 1.2 seconds after hit animation completes
- **Visual Feedback**: Alpha blinking (oscillates 0.5-1.0)
- **Check**: `Player:is_invincible()` returns true during immunity
- Prevents rapid consecutive hits from enemies

**Player Properties:**
```lua
self.max_health = 3             -- Starting health
self.damage = 0                 -- Cumulative damage taken
self.invincible_time = 0        -- Invincibility countdown (seconds)
self.weapon_damage = 2.5        -- Damage per sword hit
self.attacks = 3                -- Max combo hits
self.attack_cooldown = 0        -- Countdown timer (attack)
self.throw_cooldown = 0         -- Countdown timer (throw)
self.level = 1                  -- Player level (progression)
self.experience = 0             -- XP toward next level
self.gold = 0                   -- Currency for purchases
self.defense = 0                -- Reduces incoming damage
self.strength = 5               -- Base damage multiplier
self.critical_chance = 0        -- Percent chance for critical hit
self.attack_state = {           -- Combo tracking
    count, next_anim_ix, remaining_time, queued, hit_enemies
}
self.hit_state = {              -- Hit stun tracking
    knockback_speed, remaining_time
}
self.input_queue = {            -- Centralized input buffering
    jump, attack, throw         -- Boolean flags for pending inputs
}
```

### Collision System

Uses HC library (`APIS/hc.lua`) with spatial hashing. Key patterns:
- Separated X/Y collision passes to prevent tunneling
- Ground probing for slope walking (`world.ground_probe()`)
- Trigger volumes for ladders and hit zones
- One-way platform support

**Entity Filtering:**
- Players and enemies pass through each other (no physical collision)
- `should_skip_collision()` in world.lua handles filtering
- Enemies also pass through other enemies
- Contact damage handled separately via `Enemy:check_player_overlap()`

**Trigger Movement:**
- `world.move_trigger(obj)` - Sweeping collision for trigger objects (projectiles)
- Moves shape and detects first collision along path
- Prioritizes enemy collisions over solid geometry
- Returns `{other, x, y}` collision info or nil

**Ground Probing:**
- `world.point_has_ground(x, y)` - Checks if solid ground exists at point
- Used for enemy edge detection (avoid walking off platforms)
- Filters out triggers and enemy colliders

**Raycasting:**
- `world.raycast_down(player, max_distance)` - Finds solid ground below player
- Used by camera to predict landing during falls
- Filters out player collider and triggers
- Returns landing Y position (in tiles) or nil

### Bridge System

One-way platforms that can be jumped through from below or dropped through from above.

**Architecture:**
- Stored in `platforms/bridges.lua` with separate state in `platforms/bridges_state.lua`
- Thin colliders (0.2 tile height) at top of tile for landing
- Auto-merges adjacent horizontal bridges into single colliders
- Sprite selection: left/middle/right based on neighbors and walls

**Player Interaction:**
- Jump up through bridges from below (no collision from bottom)
- Drop through by pressing down while standing on bridge
- `player.standing_on_bridge` tracks when on bridge surface
- `player.wants_drop_through` triggers pass-through mode

**Level Symbol:** `-` (hyphen)

### Sign System

Interactive text displays triggered by player proximity.

**Architecture:**
- Object pool in `Sign/init.lua` with state in `Sign/state.lua`
- Proximity detection via bounding box overlap
- Alpha fade in/out (0.25s duration)
- Variable substitution for control bindings

**Variable Substitution:**
Signs support `{action_id}` placeholders replaced with bound keys/buttons:
```lua
["1"] = { type = "sign", text = "Press {jump} to jump!" }
-- Displays "Press SPACE to jump!" on keyboard
-- Displays "Press A to jump!" on gamepad
```

**Usage:**
```lua
Sign.new(x, y, "Press {attack} to attack!")
Sign.update(dt, player)  -- Check proximity, update fade
Sign.draw()              -- Render signs and text popups
Sign.clear()             -- Reset for level reload
```

**Level Symbol:** Configurable via `symbols` table with `type = "sign"` and `text` property.

### Prop System

Unified management for interactive objects (buttons, campfires, spike traps). Mirrors the Enemy system pattern.

**Architecture:**
- Object pool pattern with `Prop.all` table
- Registration system: `Prop.register(key, definition)` in main.lua
- Spawning: `Prop.spawn(type_key, x, y, options)`
- State machine support with `skip_callback` for group actions
- Group system for coordinated behavior

**Prop Definition:**
```lua
definition = {
    box = { x = 0, y = 0, w = 1, h = 1 },  -- Bounding box (tile coords)
    debug_color = "#FFFFFF",
    initial_state = "unpressed",
    on_spawn = function(prop, def, options) end,
    states = { ... }
}
```

**State Machine:**
Props support states identical to enemies/player:
```lua
state = {
    name = "state_name",
    start = function(prop, def, skip_callback) end,
    update = function(prop, dt, player) end,
    draw = function(prop) end,
}
```

**Skip Callback Pattern:**
The `skip_callback` parameter prevents callback recursion during group actions:
```lua
-- Button's on_press calls group_action to press all buttons in group
-- group_action passes skip_callback=true to prevent infinite recursion
Prop.set_state(prop, "pressed", true)  -- Callbacks won't fire
```

**Group System:**
Props can be assigned to named groups for coordinated actions:
```lua
-- Spawn with group assignment
Prop.spawn("button", x, y, { group = "spike_buttons", on_press = callback })

-- Trigger action on all group members
Prop.group_action("spike_buttons", "pressed")  -- Transitions all to "pressed" state
```

**Key Methods:**
- `Prop.register(key, definition)` - Register prop type
- `Prop.spawn(type_key, x, y, options)` - Create instance
- `Prop.set_state(prop, state_name, skip_callback)` - State transition
- `Prop.group_action(group_name, action)` - Trigger group-wide state change
- `Prop.check_hit(type_key, hitbox, filter)` - Hitbox overlap detection

**Current Props:**
- **Button** - Binary state (unpressed/pressed), triggers `on_press` callback
- **Campfire** - Sets player restore point, transitions to lit state
- **Spike Trap** - Togglable hazard, damages player when active

### Save Slot System

Multi-slot save system using localStorage with 3 save slots.

**Architecture:**
- Persistence layer in `SaveSlots/init.lua`
- In-memory cache of all slots loaded on init
- JSON encoding for localStorage
- Automatic migration from legacy `restore_point` data to slot 1

**Save Data Structure:**
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
}
```

**Key Methods:**
```lua
SaveSlots.init()                    -- Load all 3 slots from localStorage
SaveSlots.get(slot_index)           -- Retrieve slot data (nil if empty)
SaveSlots.set(slot_index, data)     -- Save data to slot
SaveSlots.has_data(slot_index)      -- Check if slot has save
SaveSlots.clear(slot_index)         -- Delete slot data
SaveSlots.format_playtime(seconds)  -- Format HH:MM:SS display string
```

**LocalStorage Keys:**
- `"save_slot_1"`, `"save_slot_2"`, `"save_slot_3"`
- Legacy: `"restore_point"` (auto-migrated to slot 1 if found)

### Playtime System

Session-based playtime tracking that persists with save data.

**Architecture:**
- Singleton module in `Playtime/init.lua`
- Tracks elapsed seconds with pause/resume support
- Integrated with rest state and save system

**Key Methods:**
```lua
Playtime.reset()           -- Zero out playtime
Playtime.set(seconds)      -- Restore from save data
Playtime.get()             -- Current elapsed time
Playtime.update(dt)        -- Increment timer each frame
Playtime.pause()           -- Stop counting (during menus)
Playtime.resume()          -- Resume counting (during gameplay)
Playtime.is_paused()       -- Query pause state
```

### UI Screens

Overlay screens for game flow with consistent state machine pattern.

**State Machine Pattern:**
All screens use identical states: `HIDDEN`, `FADING_IN`, `OPEN`, `FADING_OUT`
- Fade animations using delta-time
- Configurable fade durations (typically 0.25s)
- Mouse/keyboard input with priority blocking

**Input Priority (highest to lowest):**
1. Settings menu
2. Slot screen
3. Title screen
4. Game over screen
5. Rest screen

**Title Screen** (`ui/title_screen.lua`):
- Main menu with "Play Game" and "Settings" options
- Animated cursor using player idle sprite
- Callbacks for menu selections

```lua
title_screen.show()                     -- Display with fade-in
title_screen.input()                    -- Handle navigation
title_screen.update(dt, block_mouse)    -- Update animations
title_screen.draw()                     -- Render menu
title_screen.set_play_game_callback(fn) -- "Play Game" callback
title_screen.set_settings_callback(fn)  -- "Settings" callback
```

**Slot Screen** (`ui/slot_screen.lua`):
- Save slot selection with 3 slot cards
- Delete functionality with confirmation dialog
- Shows playtime and campfire name per slot

```lua
slot_screen.show()                  -- Display with fade-in
slot_screen.input()                 -- Handle keyboard/gamepad/mouse
slot_screen.update(dt, block_mouse) -- Update animations and hover
slot_screen.draw()                  -- Render slot cards
slot_screen.set_slot_callback(fn)   -- Callback when slot selected
slot_screen.set_back_callback(fn)   -- Callback when Back pressed
```

**Modes:** `SELECTING` (browse slots), `CONFIRMING_DELETE` (delete confirmation)

**Rest Screen** (`ui/rest_screen.lua`):
- Circular viewport effect centered on campfire
- Pulsing glow ring and vignette
- Player stats display (level, exp, gold, HP, DEF, STR, CRIT, playtime)
- "Continue" button to resume gameplay

```lua
rest_screen.show(world_x, world_y, camera, player)  -- Show centered on campfire
rest_screen.update(dt)                              -- Update animations
rest_screen.draw()                                  -- Render circular viewport
rest_screen.trigger_continue()                      -- Initiate fade-out
rest_screen.set_continue_callback(fn)               -- Callback after fade completes
```

**Extended States:** `HIDDEN` → `FADING_IN` → `OPEN` → `FADING_OUT` → `RELOADING` → `FADING_BACK_IN` → `HIDDEN`

**Visual Effects:**
- Circular clipping with `evenodd` fill rule
- Radial gradient vignette
- Sine wave pulse (2 Hz, ±8% radius variation)
- Glow ring with orange/yellow gradient

### Game Flow

Main game loop integration for save/load and screen transitions.

**Startup Sequence:**
1. `on_start()` initializes all subsystems
2. Title screen shown automatically
3. "Play Game" → Slot screen
4. Slot selection → `load_slot(slot_index)`

**Load Slot Flow:**
```lua
load_slot(slot_index)              -- Store active_slot, check for data
start_new_game()                   -- Clear slot, spawn at level start
continue_from_checkpoint()         -- Restore position/stats/playtime
init_level(level, spawn, player_data)  -- Initialize level with optional save
cleanup_level()                    -- Remove colliders before reload
```

**Rest (Campfire) Flow:**
1. Player touches campfire → enters `rest` state
2. `rest.start()` saves full state to active slot
3. `Playtime.pause()` stops timer
4. Rest screen shows with circular viewport
5. All enemies respawn via `Enemy.respawn()`
6. "Continue" → `continue_from_checkpoint()` reloads level

**Active Slot Tracking:**
- `active_slot` variable (1-3) tracks current save slot
- All saves go to active slot
- Death "Continue" restores from active slot

### Level Format

Levels in `levels/` use ASCII tile maps with configurable symbol definitions.

**Reserved Geometry Symbols (hardcoded):**
- `#` = solid wall
- `X` = isolated tile
- `/` = right-leaning slope
- `\` = left-leaning slope
- `H` = ladder segment
- `-` = bridge (one-way platform)

**Entity Symbols (configurable per level):**
Levels define a `symbols` table mapping characters to entity definitions:

```lua
return {
    map = { ... },
    symbols = {
        S = { type = "spawn" },
        R = { type = "enemy", key = "ratto" },
        W = { type = "enemy", key = "worm" },
        G = { type = "enemy", key = "spike_slug" },
    }
}
```

**Symbol Types:**
- `type = "spawn"` - Player spawn point (only one per level)
- `type = "enemy"` - Enemy spawn, requires `key` matching registered enemy type
- `type = "sign"` - Interactive sign, requires `text` property (supports `{action_id}` variables)

This allows levels to define custom symbols for entities without modifying the parser.

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
- `Enemies/init.lua` - Enemy manager and base class
- `Enemies/common.lua` - Shared enemy utilities (draw, is_blocked, create_death_state)
- `Enemies/ratto.lua` - Ratto enemy (patrol/chase AI)
- `Enemies/worm.lua` - Worm enemy (simple patrol)
- `Enemies/spike_slug.lua` - Spike slug enemy (defensive behavior)
- `player/attack.lua` - Combat combo system (includes sword hitbox)
- `player/throw.lua` - Projectile throwing state
- `player/hammer.lua` - Heavy attack state
- `player/block.lua` - Defensive stance
- `player/hit.lua` - Hit stun with invincibility and input queueing
- `world.lua` - HC collision engine wrapper (includes raycast, enemy filtering)
- `platforms/init.lua` - Level geometry loader
- `platforms/bridges.lua` - One-way platform system
- `Sign/init.lua` - Interactive sign system
- `Prop/init.lua` - Prop system manager (spawn, groups, state transitions)
- `Prop/button.lua` - Button prop (unpressed/pressed states)
- `Prop/campfire.lua` - Campfire prop (restore point)
- `Prop/spiketrap.lua` - Spike trap prop (togglable hazard)
- `SaveSlots/init.lua` - Save persistence layer (3 slots, localStorage)
- `Playtime/init.lua` - Session playtime tracking
- `RestorePoint/init.lua` - Legacy checkpoint (kept for backward compatibility)
- `player/rest.lua` - Rest state (campfire interaction, save trigger)
- `ui/title_screen.lua` - Title menu with animated cursor
- `ui/slot_screen.lua` - Save slot selection with delete confirmation
- `ui/rest_screen.lua` - Circular viewport rest interface
- `ui/hud.lua` - UI screen aggregator and input/draw coordinator
- `ui/game_over.lua` - Game over screen
- `ui/settings_menu.lua` - Settings menu overlay
- `sprites/init.lua` - Asset loading (submodules: player, enemies, effects, projectiles, ui, environment)
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
- Object pool pattern for entities (Effects, Projectiles, Enemies)
- Tile coordinates for game logic (converted to pixels for rendering)
- Directional rendering via `flipped` property (1 = right, -1 = left)
