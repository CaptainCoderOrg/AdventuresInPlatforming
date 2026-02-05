# Collision System

<!-- QUICK REFERENCE
- HC library: APIS/hc.lua with spatial hashing
- World collision: world.lua (move, ground_probe, raycast)
- Combat indexing: combat.lua (separate HC world)
- Filtering: should_skip_collision(), is_non_solid()
- Probe shapes: is_probe = true for non-colliding queries
-->

## HC Library Usage

Uses HC library (`APIS/hc.lua`) with spatial hashing. Key patterns:
- Separated X/Y collision passes to prevent tunneling
- Ground probing for slope walking (`world.ground_probe()`)
- Trigger volumes for ladders and hit zones
- One-way platform support
- Probe shapes for non-colliding queries

## Entity Filtering

- Players and enemies pass through each other (no physical collision)
- `should_skip_collision()` in world.lua handles filtering
- Enemies also pass through other enemies
- Contact damage handled separately via combat system
- `is_non_solid()` helper consolidates trigger/probe filtering

## Probe Shapes

- Shapes with `is_probe = true` are skipped in collision resolution
- Used for persistent query shapes (ground probing optimization)
- Avoids per-frame shape allocation overhead

## Combat Spatial Indexing (`combat.lua`)

Separate HC world dedicated to combat hit detection:
```lua
combat.world = HC.new(100)  -- 100px cell size for combat hitboxes
```

### Key Methods

```lua
combat.add(entity)           -- Register entity hitbox (x, y, box properties)
combat.remove(entity)        -- Remove from combat world
combat.update(entity, y_off) -- Update hitbox position (supports slope rotation)
combat.query_rect(x, y, w, h, filter)  -- Spatial query for overlapping entities
combat.collides(e1, e2)      -- Check if two entities overlap
combat.clear()               -- Level cleanup
```

### Query Optimization

- Persistent query shape reused across frames (recreated only on size change)
- O(1) average lookup via spatial hashing
- Used for sword hitbox queries, enemy overlap detection

## Trigger Movement

- `world.move_trigger(obj)` - Sweeping collision for trigger objects (projectiles)
- Moves shape and detects first collision along path
- Prioritizes enemy collisions over solid geometry
- Returns `{other, x, y}` collision info or nil

## Ground Probing

- `world.point_has_ground(x, y)` - Checks if solid ground exists at point
- Used for enemy edge detection (avoid walking off platforms)
- Filters out triggers and enemy colliders

## Raycasting

- `world.raycast_down(player, max_distance)` - Finds solid ground below player
- Used by camera to predict landing during falls
- Filters out player collider and triggers
- Returns landing Y position (in tiles) or nil

## Bridge System

One-way platforms that can be jumped through from below or dropped through from above.

### Architecture

- Stored in `platforms/bridges.lua` with separate state in `platforms/bridges_state.lua`
- Thin colliders (0.2 tile height) at top of tile for landing
- Auto-merges adjacent horizontal bridges into single colliders
- Sprite selection: left/middle/right based on neighbors and walls

### Player Interaction

- Jump up through bridges from below (no collision from bottom)
- Drop through by pressing down while standing on bridge
- `player.standing_on_bridge` tracks when on bridge surface
- `player.wants_drop_through` triggers pass-through mode

**Level Symbol:** `-` (hyphen)

**Tiled Object:** Rectangle with `type = "one_way_platform"` (invisible, arbitrary width)

**Collision Behavior:** Bridges and one-way platforms only collide in the Y direction. Players and enemies pass through them horizontally, allowing seamless movement from the sides.

## World Collider Types

The world module manages several collider types beyond basic physics shapes:

### Shield Colliders
Solid barriers for the player's shield that block enemy movement:
```lua
world.add_shield(player, shield_box)    -- Create shield collider
world.update_shield(player, shield_box) -- Update position/direction
world.remove_shield(player)             -- Remove shield
```
- Idempotent: `add_shield` removes existing shield before creating new one
- Position based on player direction (front edge)
- Enemies collide with shields; players pass through their own

### Combat Hitboxes
Separate from physics shapes, used for hit detection with support for rotation:
```lua
world.add_hitbox(obj)              -- Create combat hitbox
world.update_hitbox(obj, y_offset) -- Update position and rotation
world.remove_hitbox(obj)           -- Remove hitbox
```
- Supports slope rotation via `obj.slope_rotation`
- Used by slope-following enemies for accurate hit detection

### Projectile Colliders
Blocks projectiles without taking damage (e.g., boss shields):
```lua
world.add_projectile_collider(owner, x, y, w, h)    -- Create collider
world.update_projectile_collider(owner, x, y, w, h) -- Update (moves or recreates)
world.remove_projectile_collider(owner)             -- Remove collider
```
- Optimizes position-only updates (moves shape instead of recreating)

## Key Files

- `world.lua` - HC collision engine wrapper (includes raycast, probe shapes, filtering)
- `combat.lua` - Combat spatial indexing (separate HC world for hit detection)
- `platforms/init.lua` - Level geometry loader
- `platforms/bridges.lua` - One-way platform system
- `APIS/hc.lua` - HC spatial hashing library
