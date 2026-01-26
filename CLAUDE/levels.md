# Levels and Camera

<!-- QUICK REFERENCE
- Level files: levels/*.lua with ASCII tile maps
- Geometry symbols: # (wall), X (isolated), / \ (slopes), H (ladder), - (bridge)
- Entity symbols: configurable via symbols table
- Camera: Camera/init.lua with entity following
- Signs: Sign/init.lua with {action_id} variable substitution
-->

## Level Format

Levels in `levels/` use ASCII tile maps with configurable symbol definitions.

### Reserved Geometry Symbols (hardcoded)

- `#` = solid wall
- `X` = isolated tile
- `/` = right-leaning slope
- `\` = left-leaning slope
- `H` = ladder segment
- `-` = bridge (one-way platform)

### Entity Symbols (configurable per level)

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

### Symbol Types

- `type = "spawn"` - Player spawn point (only one per level)
- `type = "enemy"` - Enemy spawn, requires `key` matching registered enemy type
- `type = "sign"` - Interactive sign, requires `text` property (supports `{action_id}` variables)

This allows levels to define custom symbols for entities without modifying the parser.

### Waypoint-Based Enemies

Some enemies use multiple markers to define patrol routes:

**Bat Eye (`bat_eye`):** Place two `B` symbols on the same row to define patrol waypoints. The enemy spawns at the left position and patrols between them.

```lua
symbols = {
    B = { type = "enemy", key = "bat_eye" },
}
```

```
-- Level map example:
B          B    -- Bat patrols horizontally between these points
#############
```

- Two markers on same row: Creates patrolling bat_eye
- Single marker: Creates stationary bat_eye
- 3+ markers on same row: Warning logged, markers ignored

## Sign System

Interactive text displays triggered by player proximity.

### Architecture

- Object pool in `Sign/init.lua` with state in `Sign/state.lua`
- Proximity detection via bounding box overlap
- Alpha fade in/out (0.25s duration)
- Variable substitution for control bindings

### Variable Substitution

Signs support `{action_id}` placeholders replaced with bound keys/buttons:
```lua
["1"] = { type = "sign", text = "Press {jump} to jump!" }
-- Displays "Press SPACE to jump!" on keyboard
-- Displays "Press A to jump!" on gamepad
```

### Usage

```lua
Sign.new(x, y, "Press {attack} to attack!")
Sign.update(dt, player)  -- Check proximity, update fade
Sign.draw()              -- Render signs and text popups
Sign.clear()             -- Reset for level reload
```

**Level Symbol:** Configurable via `symbols` table with `type = "sign"` and `text` property.

## Camera System

Complete camera management system in `Camera/init.lua` with entity following and dynamic framing.

### Architecture

- Entity following with smooth interpolation
- State-based vertical framing (default, falling, climbing)
- Horizontal look-ahead in movement direction
- Manual look control via right analog stick
- Epsilon snapping to prevent floating-point drift

### Framing Modes

- **Default**: Player at 2/3 from top (shows more below)
- **Falling**: Player at 10% from top (uses raycast to predict landing)
- **Climbing**: Varies with direction (0.333 down, 0.5 idle)

### Key Methods

```lua
Camera.new(viewport_w, viewport_h, world_w, world_h)
Camera:set_target(target)           -- Follow an entity
Camera:update(tile_size, dt, lerp)  -- Call each frame
Camera:apply_transform(tile_size)   -- Apply before drawing world
Camera:get_visible_bounds(tile_size, margin) -- Get visible tile bounds
Camera:is_visible(entity, tile_size, margin) -- Check if entity is in viewport (default margin: 2 tiles)
```

### Features

- **Look-ahead**: Camera leads 3 tiles in movement direction
- **Manual Look**: Right analog stick adjusts view (0.333 to 0.833 vertical range)
- **Falling Lerp Ramp**: Camera follows fall progressively faster (0.08 -> 0.25 over 0.5s)

Configuration in `config/camera.lua` (lerp speeds, framing ratios, look-ahead distance).

## Key Files

- `levels/*.lua` - Level definitions with ASCII maps
- `platforms/init.lua` - Level geometry loader
- `Sign/init.lua` - Interactive sign system
- `Sign/state.lua` - Sign state management
- `Camera/init.lua` - Camera system with following and framing
- `config/camera.lua` - Camera configuration (lerp, framing, look-ahead)
