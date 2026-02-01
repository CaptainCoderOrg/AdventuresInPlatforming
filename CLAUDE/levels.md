# Levels and Camera

<!-- QUICK REFERENCE
- Level files: levels/*.lua (ASCII) or Tilemaps/*.lua (Tiled export)
- ASCII geometry: # (wall), X (isolated), / \ (slopes), H (ladder), - (bridge)
- Tiled: Layer/tile type property determines collision behavior
- Entity symbols: configurable via symbols table (ASCII) or object properties (Tiled)
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

## Tiled Format

The loader auto-detects Tiled exports (Lua format) via `tilesets` and `layers` arrays. Export from Tiled using File > Export As > Lua.

### Format Detection

```lua
-- Auto-detected as Tiled format if both exist:
level_data.tilesets ~= nil and level_data.layers ~= nil
```

### Layer Types

| Layer Type | Purpose |
|------------|---------|
| `tilelayer` | Tile-based geometry (walls, bridges, ladders, decorative) |
| `objectgroup` | Entity placement (spawn, enemies, props, patrol areas) |
| `imagelayer` | Background images with parallax |

### Collision Type Priority

Collision behavior is determined by the `type` property:

1. **Tile type** (from tileset) - Checked first, overrides layer type
2. **Layer type** (from layer properties) - Fallback if tile has no type
3. **No type** - Tiles render as decorative (no collision)

Valid type values: `wall`, `platform`, `bridge`, `ladder`

### Object Layer Properties

Objects use custom properties for entity configuration:

| Property | Type | Description |
|----------|------|-------------|
| `type` | string | Entity type: `spawn`, `enemy`, `sign`, `patrol_area`, or prop type |
| `key` | string | Enemy key (if type=enemy), e.g., `ratto`, `zombie` |
| `text` | string | Sign text (if type=sign) |
| `flip` | bool | Face left instead of right |
| `offset_x` | number | X offset in tiles (for sprite alignment) |
| `offset_y` | number | Y offset in tiles (for sprite alignment) |

Property merging: Tileset properties are merged with object instance properties. Instance properties override tileset properties.

### Patrol Areas

Rectangle objects with `type = "patrol_area"` define patrol bounds for enemies:

1. Create a rectangle object in Tiled covering the patrol zone
2. Set custom property `type = "patrol_area"`
3. Place enemy tile objects inside the rectangle
4. Enemies automatically use the containing patrol area for waypoints

Debug: Press `P` to visualize patrol areas as yellow rectangles.

### Image Layer Backgrounds

Image layers support parallax scrolling and tiling:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `parallaxx` | number | 1 | Horizontal parallax factor (0 = fixed, 1 = normal scroll) |
| `parallaxy` | number | 1 | Vertical parallax factor |
| `repeatx` | bool | false | Tile horizontally |
| `repeaty` | bool | false | Tile vertically |
| `offsetx` | number | 0 | X offset in pixels |
| `offsety` | number | 0 | Y offset in pixels |

### Coordinate Normalization

Tiled maps with negative coordinates (infinite maps) are automatically normalized to start at (0,0). All tile and object positions are adjusted accordingly.

### Tileset Setup

1. Create tileset in Tiled (File > New > New Tileset)
2. Set tile `type` property for collision tiles (wall, bridge, ladder)
3. Export tileset as Lua (File > Export As > Lua)
4. Place exported `.lua` file in `Tilemaps/` directory

### Collection Tilesets

Tiled supports two tileset types:

| Type | Description | Rendering |
|------|-------------|-----------|
| Image-based | Single image containing all tiles (e.g., `tileset_dungeon`) | Uses `gid_to_tilemap()` to find tile coordinates |
| Collection | Individual images per tile (e.g., `decorations`) | Draws images directly with height offset |

**Detection:** Tilesets with a top-level `image` property are image-based. Collection tilesets have `image` on individual tiles instead (and `columns = 0`).

**Height Offset:** Collection tiles taller than 16px are offset upward since Tiled uses bottom-left origin:
```lua
height_offset = (tile_image.height / BASE_TILE - 1) * tile_size
```

**Typed vs Typeless Collection Tiles:**
- **Typed tiles** (wall, bridge, ladder): Use fallback sprite rendering, image not loaded
- **Typeless tiles** (decorations): Store image info, rendered via `draw_collection_tile()`

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
- `Tilemaps/*.lua` - Tiled map exports (levels and tilesets)
- `platforms/init.lua` - Level geometry loader (format auto-detection)
- `platforms/tiled_loader.lua` - Tiled format parser
- `Sign/init.lua` - Interactive sign system
- `Sign/state.lua` - Sign state management
- `Camera/init.lua` - Camera system with following and framing
- `config/camera.lua` - Camera configuration (lerp, framing, look-ahead)
