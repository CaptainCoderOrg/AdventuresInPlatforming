# Entities System

<!-- QUICK REFERENCE
- Enemy registration: Enemy.register(key, definition) in main.lua
- Enemy spawning: Enemy.spawn(type_key, x, y)
- Prop registration: Prop.register(key, definition) in main.lua
- Object pools: Enemy.all, Prop.all, Projectile.all, Effects.all
- Common utilities: Enemies/common.lua, Prop/common.lua
-->

## Enemy System

AI-controlled enemies with state machines and combat integration.

### Architecture

- Object pool pattern with `Enemy.all` table
- State machine identical to player (start, update, draw functions)
- Registration system: `Enemy.register(key, definition)` in main.lua
- Spawning from level data: `Enemy.spawn(type_key, x, y)`

### Enemy Properties

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

### State Machine

Each enemy type defines states with the same pattern as player:
```lua
states = {
    state_name = {
        start = function(enemy, definition) end,
        update = function(enemy, dt) end,
        draw = function(enemy) end,
    }
}
```

### Current Enemies

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

### Damage System

Enemies can take damage from multiple sources:
```lua
enemy:on_hit("weapon", { damage = player.weapon_damage, x = player.x })
enemy:on_hit("projectile", projectile)
```
- Knockback direction calculated from damage source
- Transitions to hit state, then death if health <= 0

### Player Contact

- `Enemy:check_player_overlap(player)` called each frame
- Deals `enemy.damage` to player on collision
- Player invincibility frames prevent rapid hits

### Common Utilities (`Enemies/common.lua`)

Shared functions to reduce duplication across enemy types:
- `common.player_in_range(enemy, range)` - Distance check in tiles
- `common.direction_to_player(enemy)` - Returns -1 or 1 toward player
- `common.draw(enemy)` - Standard sprite rendering
- `common.is_blocked(enemy)` - Checks wall or edge in current direction
- `common.reverse_direction(enemy)` - Flip direction and animation
- `common.create_death_state(animation)` - Factory for standard death state

### Edge Detection

Enemies automatically detect platform edges to avoid falling:
- `enemy.edge_left` / `enemy.edge_right` - True if no ground ahead
- Uses `world.point_has_ground(x, y)` to probe for solid geometry
- Combined with `enemy.wall_left` / `wall_right` in `common.is_blocked()`

### Creating New Enemies

1. Create definition file in `Enemies/` (animations, states, properties)
2. Use `common.*` utilities for shared behaviors
3. Register in main.lua: `Enemy.register("name", require("Enemies/name"))`
4. Add spawn character to level format (R=ratto, W=worm, G=spike_slug)

## Prop System

Unified management for interactive objects (buttons, campfires, spike traps). Mirrors the Enemy system pattern.

### Architecture

- Object pool pattern with `Prop.all` table
- Registration system: `Prop.register(key, definition)` in main.lua
- Spawning: `Prop.spawn(type_key, x, y, options)`
- State machine support with `skip_callback` for group actions
- Group system for coordinated behavior

### Prop Definition

```lua
definition = {
    box = { x = 0, y = 0, w = 1, h = 1 },  -- Bounding box (tile coords)
    debug_color = "#FFFFFF",
    initial_state = "unpressed",
    on_spawn = function(prop, def, options) end,
    states = { ... }
}
```

### State Machine

Props support states identical to enemies/player:
```lua
states = {
    state_name = {
        start = function(prop, def, skip_callback) end,
        update = function(prop, dt, player) end,
        draw = function(prop) end,
    }
}
```

**Note:** Props may define a shared `draw` function at the definition level instead of per-state when all states share identical draw logic. The Prop system falls back to `definition.draw(prop)` if no state-level draw exists.

### Skip Callback Pattern

The `skip_callback` parameter prevents callback recursion during group actions:
```lua
-- Button's on_press calls group_action to press all buttons in group
-- group_action passes skip_callback=true to prevent infinite recursion
Prop.set_state(prop, "pressed", true)  -- Callbacks won't fire
```

### Group System

Props can be assigned to named groups for coordinated actions:
```lua
-- Spawn with group assignment
Prop.spawn("button", x, y, { group = "spike_buttons", on_press = callback })

-- Trigger action on all group members
Prop.group_action("spike_buttons", "pressed")  -- Transitions all to "pressed" state
```

### Key Methods

- `Prop.register(key, definition)` - Register prop type
- `Prop.spawn(type_key, x, y, options)` - Create instance
- `Prop.set_state(prop, state_name, skip_callback)` - State transition
- `Prop.group_action(group_name, action)` - Trigger group-wide state change
- `Prop.check_hit(type_key, hitbox, filter)` - Hitbox overlap detection
- `Prop.get_pressure_plate_lift(entity)` - Get cached lift amount for entity

### Pressure Plate Lift Pattern

Entities standing on pressure plates are visually raised to simulate plate depression. The pattern avoids spatial queries during draw by caching lift on entities:

1. Player/Enemy `update()` clears `pressure_plate_lift = 0` before Prop.update()
2. Pressure plates set `entity.pressure_plate_lift` during their `update()`
3. Entity draw functions read via `Prop.get_pressure_plate_lift(entity)` (O(1) lookup)

```lua
-- In draw functions:
local lift = Prop.get_pressure_plate_lift(entity)
animation:draw(x, y - lift)
```

### Current Props

- **Button** - Binary state (unpressed/pressed), triggers `on_press` callback
- **Campfire** - Sets player restore point, transitions to lit state
- **Spike Trap** - 5-state hazard (extended, extending, retracted, retracting, disabled)
  - Modes: "static" (always extended) or "alternating" (cycles on timer)
  - Configurable: `extend_time`, `retract_time`, `alternating_offset`
  - `disable()` permanently retracts and disables the trap
  - Proximity audio within 8 tiles
- **Pressure Plate** - Trigger activated by player/enemy standing on it
  - States: unpressed, pressed, release
  - Callbacks: `on_pressed` (when fully pressed), `on_release` (when entity leaves)
  - Lift effect: entities standing on plate are visually raised 0-3px based on animation frame
  - Uses combat spatial indexing for entity detection
- **Spear Trap** - Wall-mounted trap that fires damaging spears
  - States: idle, firing, cooldown
  - Configurable: `fire_delay`, `cooldown_time`, `initial_offset`, `auto_fire`, `enabled`
  - `fire()` triggers manually, `enable()`/`disable()` control state
  - Proximity audio within 16 tiles
  - Manages internal Spear projectile pool with combat integration
- **Locked Door** - Blocks passage until unlocked
  - States: locked, unlock, unlocked
  - Unlock methods: player has `required_key` item + down+attack, or `group_action("unlock")`
  - Shows "Open" prompt when player has the required key
  - "Locked" feedback with 5s debounce when player lacks key
  - Removes world collider when unlocked (door becomes passable and invisible)
- **Unique Item** - Permanent collectible that persists across saves
  - States: idle, collect, collected
  - Items stored in `player.unique_items` for gameplay checks (e.g., locked doors)
  - `should_spawn` callback prevents respawning if player already has item
  - Collection via down+attack input
  - Configurable: `item_id` (e.g., "gold_key")

### Common Utilities (`Prop/common.lua`)

Shared functions to reduce duplication across prop types:
```lua
common.draw(prop)                    -- Standard animation rendering
common.player_touching(prop, player) -- Uses combat spatial indexing for overlap
common.damage_player(prop, player, damage)  -- Consolidated hazard damage
```

`common.damage_player()` handles the full damage pattern: touch check, invincibility check, health check, and `player:take_damage()` call.

## Projectile System

Physics-based throwable objects with collision detection.

### Architecture

- Object pool with `Projectile.all` table
- Full physics: velocity (vx, vy), gravity scaling
- Collision via sweeping trigger movement (`world.move_trigger`)
- Auto-cleanup on collision or out-of-bounds
- Custom hit effect callbacks per projectile type

### Projectile Properties

- Position in tile coordinates
- Box hitbox (0.5x0.5 tiles)
- Velocity in pixels/frame
- Direction-aware (for rendering and effects)

### Physics

```lua
-- Example: Axe projectile
velocity_x = direction * 16  -- pixels/frame
velocity_y = -3              -- upward arc
gravity = 20                 -- gravity scale
```

Projectiles only collide with solid world geometry (walls, platforms, slopes). Filtered to ignore triggers and player.

### Projectile Switching

- Player can toggle between projectile types (0 key or Gamepad SELECT)
- Available: `Projectile.get_axe()`, `Projectile.get_shuriken()`
- Current projectile stored in `player.projectile`

### Current Projectiles

- `AXE` - Throwing axe (8x8px, 4-frame spin, 100ms/frame, gravity-affected arc)
- `SHURIKEN` - Throwing star (8x8px, 5-frame spin, 24 px/frame velocity, no gravity)

### Custom Effect Callbacks

Projectiles support custom hit effects via factory pattern:
```lua
Projectile.new(x, y, direction, spec, Effects.create_shuriken_hit)
```

## Effects System

Visual feedback system for transient particle effects. Manages one-shot animations that auto-cleanup when finished.

### Architecture

- Object pool pattern with `Effects.all` table
- Factory methods for specific effects (e.g., `Effects.create_hit()`)
- Integrated into main loop via `Effects.update(dt)` and `Effects.draw()`
- Uses Animation system for rendering

### Current Effects

- `HIT` - Impact effect (16x16px, 4 frames, 80ms/frame, non-looping)
- `SHURIKEN_HIT` - Shuriken impact (8x8px, 6 frames, non-looping)

### Usage

```lua
Effects.create_hit(x, y, direction)          -- Generic hit effect
Effects.create_shuriken_hit(x, y, direction) -- Shuriken-specific effect
```

Effects are positioned in tile coordinates and converted to screen pixels for rendering.

### Creating Custom Effects

Effects use the object pool pattern. New effect types require:
1. Animation definition in `Effects/init.lua`
2. Factory method (e.g., `Effects.create_shuriken_hit`)

## Key Files

- `Enemies/init.lua` - Enemy manager and base class
- `Enemies/common.lua` - Shared enemy utilities (draw, is_blocked, create_death_state)
- `Enemies/ratto.lua` - Ratto enemy (patrol/chase AI)
- `Enemies/worm.lua` - Worm enemy (simple patrol)
- `Enemies/spike_slug.lua` - Spike slug enemy (defensive behavior)
- `Prop/init.lua` - Prop system manager (spawn, groups, state transitions)
- `Prop/common.lua` - Shared prop utilities (draw, player_touching, damage_player)
- `Prop/button.lua` - Button prop (unpressed/pressed states)
- `Prop/campfire.lua` - Campfire prop (restore point)
- `Prop/spike_trap.lua` - Spike trap prop (5-state hazard with alternating mode)
- `Prop/pressure_plate.lua` - Pressure plate prop (entity-triggered with lift effect)
- `Prop/locked_door.lua` - Locked door prop (key-based or group-action unlock)
- `Prop/unique_item.lua` - Unique item prop (permanent collectibles)
- `Projectile/init.lua` - Throwable projectiles with physics
- `Effects/init.lua` - Visual effects manager (hit effects, particles)
