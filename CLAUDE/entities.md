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
- Update culling: `Enemy.update(dt, player, camera)` skips physics/AI for enemies 8+ tiles off-screen (animations still run)
- Draw culling: `Enemy.draw(camera)` skips rendering for enemies 2+ tiles off-screen

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
  - Perfect block: Instant death
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
- **Bat Eye** - Flying enemy that patrols between waypoints and dive-attacks
  - States: idle, patrol, alert, attack_start, attack, attack_recovery, hit, stun, death
  - Health: 2 HP, Contact damage: 2
  - Flying (no gravity), damages shield on contact
  - Patrol speed: 4 px/frame, attack speed: 12 px/frame
  - Detection: 5 tiles horizontal, 12 tiles vertical (below only, facing direction)
  - Attack behavior: Throttled LOS check (0.1s), locks target position, dives at player
  - Returns to patrol height at 3x patrol speed after attack
  - Shield collision stops attack and triggers recovery state
  - Pauses at waypoints for 1 second before reversing
  - Perfect block: Enters stun state, falls with gravity for 1 second
  - Spawned via paired `B` symbols on same row in level map
- **Zombie** - Slow, shambling undead that patrols within bounded area
  - States: idle, move, chase, attack, hit, stun, death
  - Health: 6 HP, Contact damage: 3
  - Patrol speed: 1.5 px/frame, chase speed: 6 px/frame
  - Detection: AABB check in facing direction within patrol bounds, 1.5 tiles vertical range
  - Attack: Triggers at 1.5 tiles, damage on frames 5-6 (0-indexed), 0.3s cooldown
  - Bounded patrol with waypoints (waypoint_a, waypoint_b)
  - Overshoot detection: idles after 0.5s if player passes behind
  - 70% bias toward patrol center when picking direction
  - Damages shield on contact
  - Perfect block: Takes 2 damage, strong knockback, stunned for 1 second
  - Spawned via paired `Z` symbols on same row in level map
- **Ghost Painting** - Haunted painting that attacks when player looks away
  - States: idle, wait, prep_attack, attack, reappear, fade_out, hit, death
  - Health: 4 HP, Armor: 1, Contact damage: 2 (only during prep_attack/attack)
  - Flying (no gravity), phases through walls
  - Detection range: 3 tiles, attack triggers when player leaves range while not facing ghost
  - Prep attack: Floats upward with shake effect for 1 second
  - Attack: Accelerates toward player (max 25 tiles/sec), continues until off-screen
  - Reappear: Teleports to random position 6 tiles from player, fades in over 1.5s
  - Fade out: Triggered by player hit or shield block, fades over 0.75s then reappears
  - Directional shield check (phases through collision shapes)
  - Perfect block: Instant death
  - Spawned via `P` symbol in level map
- **Magician** - Flying mage that casts homing projectiles and teleports to dodge
  - States: idle, attack, fly, disappear, unstuck, hit, return, death
  - Health: 6 HP, Armor: 0, No contact damage
  - Flying (no gravity), custom on_hit (no knockback)
  - Detection: 10 tiles (face player), 8 tiles + LOS (attack)
  - Attack: Casts homing MagicBolt (2 damage, 10 tiles/sec, 1.5 rad/sec homing)
  - Fly: Repositions 6-8 tiles from player at 4 tiles/sec
  - Disappear: Dodges player projectiles via fade-out teleport to opposite side
  - Return: Teleports to spawn when player out of range or LOS lost
  - Unstuck: Emergency teleport when stuck in wall geometry
  - Manages own projectile pool (MagicBolt) with trail and puff particle effects
  - Throttled expensive checks (dodge: 0.05s, wall: 0.15s, LOS: 0.12s, path: 0.08s)
  - Spawned via `M` symbol in level map
- **Guardian** - Heavy enemy with spiked club that jumps to engage
  - States: idle, alert, attack, back_away, reassess, hit, jump_away, jump_toward, land, charge, charge_and_jump, assess_charge, death
  - Health: 6 HP, Armor: 1, Body damage: 1, Club damage: 3
  - Detection: 12 tiles horizontal, 1.5 tiles vertical (facing direction only)
  - Two damage zones: body (hittable) and club (high damage)
  - Attack behavior: Alert animation, then jump toward or charge based on distance
  - Post-hit recovery: Jumps away from player after stun
  - Custom on_hit: No knockback (heavy enemy)
  - Frame-based club hitboxes during attack swing animation
  - Perfect block: Takes 2 damage, enters hit state (no knockback)
  - Spawned via `F` symbol in level map (`f` for flipped/facing right)
- **Flaming Skull** - Bouncing flying skull that drains energy on contact
  - States: float, hit, death
  - Health: 40 HP, Contact damage: 1, Energy drain: 1
  - Flying (no gravity), damages shield on contact
  - Bounces off walls, floors, ceilings, and bridges
  - Vertical speed is half of horizontal for flatter trajectory
  - Custom on_hit: Enters hit state without knockback, preserves velocity direction
  - Configurable spawn properties from Tiled:
    - `speed`: Movement speed in tiles/sec (default: 2)
    - `start_direction`: Initial direction - NE, SE, SW, NW (default: NE)
    - `health`: Override max health for difficulty scaling
  - Spawned via Tiled object layer with type "enemy" and key "flaming_skull"

### Spawn Data Properties

Optional properties passed via `spawn_data` during enemy creation (set in Tiled object properties):
- `flip` - Initial facing direction (true = right, default = left)
- `waypoints` - Patrol bounds `{a, b}` in tile coordinates (auto-detected from patrol_area)
- `speed` - Custom movement speed (enemy-specific interpretation)
- `start_direction` - Initial movement direction string (enemy-specific, e.g., NE/SE/SW/NW)
- `health` - Override max_health for difficulty scaling or testing

### Damage System

Enemies can take damage from multiple sources:
```lua
enemy:on_hit("weapon", { damage = player.weapon_damage, x = player.x })
enemy:on_hit("projectile", projectile)
```
- Knockback direction calculated from damage source
- Transitions to hit state, then death if health <= 0

### Perfect Block Callback

Enemies can react to player perfect blocks via the `on_perfect_blocked` callback:
```lua
--- Called when player performs a perfect block against this enemy.
---@param enemy table Self
---@param player table The player who perfect blocked
function enemy:on_perfect_blocked(player)
    -- Default: no reaction (defined in Enemies/init.lua)
end
```

Enemy definitions can override this for custom reactions:
- **Ratto**: Instant death (weak enemy)
- **Bat Eye**: Enters stun state, falls to ground with gravity for 1 second
- **Zombie**: Takes 2 damage, strong knockback, stunned for 1 second
- **Guardian**: Takes 2 damage, enters hit state (no knockback - heavy enemy)
- **Ghost Painting**: Instant death

### Player Contact

- `Enemy:check_player_overlap(player)` called each frame
- Deals `enemy.damage` to player on collision
- Player invincibility frames prevent rapid hits

### Common Utilities (`Enemies/common.lua`)

Shared functions to reduce duplication across enemy types:
- `common.apply_gravity(enemy, dt)` - Frame-rate independent gravity application
- `common.apply_friction(velocity, friction, dt)` - Frame-rate independent velocity damping
- `common.player_in_range(enemy, range)` - Distance check in tiles (squared distance for perf)
- `common.direction_to_player(enemy)` - Returns -1 or 1 toward player
- `common.has_line_of_sight(enemy)` - Raycast from enemy to player, filtering non-solid shapes
- `common.draw(enemy)` - Standard sprite rendering with slope rotation support
- `common.is_blocked(enemy)` - Checks wall or edge in current direction
- `common.reverse_direction(enemy)` - Flip direction and animation
- `common.create_death_state(animation)` - Factory for standard death state
- `common.update_slope_rotation(enemy, dt)` - Smooth lerp toward ground normal rotation
- `common.get_slope_rotation(enemy)` - Get current rotation angle for drawing
- `common.get_slope_y_offset(enemy)` - Get Y offset to keep rotated sprite grounded

### Edge Detection

Enemies automatically detect platform edges to avoid falling:
- `enemy.edge_left` / `enemy.edge_right` - True if no ground ahead
- Uses `world.point_has_ground(x, y)` to probe for solid geometry
- Combined with `enemy.wall_left` / `wall_right` in `common.is_blocked()`

### Creating New Enemies

1. Create definition file in `Enemies/` (animations, states, properties)
2. Use `common.*` utilities for shared behaviors
3. Register in main.lua: `Enemy.register("name", require("Enemies/name"))`
4. Add spawn character to level format (R=ratto, W=worm, G=spike_slug, B=bat_eye, Z=zombie, P=ghost_painting, M=magician, F=guardian) or use Tiled object layer for enemies without map symbols (flaming_skull)
5. If the enemy manages its own projectile pool, expose a cleanup function in the definition export and call it from `cleanup_level()` in main.lua to prevent orphaned colliders (see magician's `clear_bolts`)

## Prop System

Unified management for interactive objects (buttons, campfires, spike traps). Mirrors the Enemy system pattern.

### Architecture

- Object pool pattern with `Prop.all` table
- Registration system: `Prop.register(key, definition)` in main.lua
- Spawning: `Prop.spawn(type_key, x, y, options)`
- State machine support with `skip_callback` for group actions
- Group system for coordinated behavior
- Viewport culling: `Prop.draw(camera)` skips off-screen entities
- Global draw hooks: `Prop.register_global_draw(fn)` for sub-entity pools that manage their own visibility culling

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
        interact = function(prop) end,  -- Optional: called when player interacts
    }
}
```

The `interact` function is optional and used by interactive props (lever, locked_door, unique_item). Return `true` to indicate the interaction was consumed.

**Note:** Props may define a shared `draw` function at the definition level instead of per-state when all states share identical draw logic. The Prop system falls back to `definition.draw(prop)` if no state-level draw exists.

### Manual Animation Control

Props that require precise animation-to-logic synchronization (e.g., spawning a projectile on an exact visual frame) can manually advance their animation before frame checks:

```lua
update = function(prop, dt, player)
    prop.animation:play(dt)
    prop._skip_animation_this_frame = true  -- Prevents Prop.update from double-advancing

    -- Now check animation.frame for exact timing
    if prop.animation.frame >= 6 then
        -- Spawn projectile on exact visual frame
    end
end
```

Without this pattern, `Prop.update()` advances animations *after* state updates, causing a 1-frame delay between the visual frame and logic that depends on it.

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
- `Prop.register_global_draw(fn)` - Register a draw function called every frame regardless of prop visibility (receives camera)
- `Prop.get_pressure_plate_lift(entity)` - Get cached lift amount for entity
- `Prop.get_persistent_states()` - Merge current level's props into accumulator and return all persistent states
- `Prop.restore_persistent_states(states)` - Initialize accumulator and restore prop states from save data
- `Prop.clear_persistent_states()` - Reset accumulator (new game)

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
  - States: locked, jiggle, unlock, unlocked
  - Unlock methods: player has `required_key` item + up, or `group_action("unlock")`
  - Shows "Open" prompt when player has the required key
  - "Jiggle" feedback animation when player lacks required key
  - Removes world collider when unlocked (door becomes passable and invisible)
- **Unique Item** - Permanent collectible that persists across saves
  - States: idle, collect, collected
  - Items stored in `player.unique_items` for gameplay checks (e.g., locked doors)
  - Equipped items tracked in `player.equipped_items` (set of item_ids)
  - `should_spawn` callback prevents respawning if player already has item
  - Collection via up input shows pickup dialogue with "Equip" and "Add to Inventory" options
  - Non-equippable items (type = "no_equip") are added to inventory immediately without dialogue
  - Configurable: `item_id` (e.g., "gold_key")
  - Equipment types (see `unique_item_registry.lua`):
    - `shield` - Only one equipped at a time
    - `weapon` - Only one equipped at a time
    - `secondary` - Only one equipped at a time (throwables)
    - `accessory` - Any number can be equipped
    - `no_equip` - Cannot be equipped (e.g., keys)
- **Stackable Item** - Consumable collectibles that stack in inventory (keys, etc.)
  - States: idle, collect, collected
  - Items stored in `player.stackable_items` as counts (item_id -> count)
  - Persistence: `collected` state saved per-position to prevent re-collection within same playthrough
  - Collection via up input adds to count and displays item name
  - Consumed when used (e.g., unlocking doors/chests) with floating text feedback
  - Configurable: `item_id` (e.g., "dungeon_key"), `count` (default: 1)
  - Visual: Silver debug color to distinguish from gold unique items, floating bob animation
  - Registry: `Prop/stackable_item_registry.lua` defines item names, sprites, sounds, max_stack
- **Lever** - Toggleable switch that fires callbacks on state changes
  - States: left, right, toggling
  - Configurable: `initial_state`, `on_left`, `on_right` callbacks, `text` prompt
  - Can be toggled by: player interaction (up input), sword attack, hammer attack, projectile hit
  - Shows text prompt when player is nearby
- **Appearing Bridge** - One-way platform that fades in/out with sequenced animation
  - States: hidden, appearing, visible, disappearing
  - Triggered via `Prop.group_action()` with `appear` or `disappear` actions
  - Per-tile delay creates cascading fade effect (left-to-right for appear, right-to-left for disappear)
  - Configurable: `FADE_DURATION` (0.15s), `TILE_DELAY` (0.08s)
  - Auto-detects sprite type (left/middle/right) based on adjacent group members
  - Collider added immediately on appear (for walkability), removed immediately on disappear (for fall-through)
- **Decoy Painting** - Decorative painting that visually matches ghost_painting enemy
  - No collision (box is 0x0), purely visual
  - Uses ghost_painting static sprite with -0.5 tile Y offset
  - Used to disguise real ghost_painting enemies or as decoration
  - Spawned via `p` symbol in level map
- **Witch NPC** - Interactable merchant NPC with dialogue
  - Shows "Talk" prompt when player approaches
  - Displays dialogue text on interaction
  - 2-tile collision box, 10-frame idle animation
- **Explorer NPC** - Interactable NPC with dialogue
  - 1-tile collision box, 5-frame idle animation
- **Adept NPC** - Interactable NPC with dialogue
  - 1-tile collision box, 6-frame reading animation
- **Decoration** - Non-interactive visual props rendered from Tiled tilesets
  - No collision (box is 0x0), purely visual
  - No state machine (uses simple draw function)
  - Supports both collection tiles (individual images) and image-based tileset tiles
  - Supports horizontal flip via Tiled gid flags
  - Automatically created for typeless tile objects in Tiled Props layer

### NPC Factory Pattern (`Prop/npc_common.lua`)

NPCs share identical behavior (proximity prompt, interaction dialogue) with different visuals. The `npc_common.create(config)` factory generates prop definitions from configuration:

```lua
return npc_common.create({
    sprite = sprites.npcs.explorer_idle,
    frame_count = 5,
    ms_per_frame = 150,
    width = 16,
    height = 16,
    dialogue = "The dungeon lies ahead...",
    box_size = 1,      -- Optional, default 1
    draw_width = 1,    -- Optional, default box_size
})
```

Adding a new NPC requires only a configuration file using this factory.

### Common Utilities (`Prop/common.lua`)

Shared functions to reduce duplication across prop types:
```lua
common.draw(prop)                              -- Standard animation rendering
common.player_touching(prop, player)           -- Uses combat spatial indexing for overlap
common.damage_player(prop, player, damage)     -- Consolidated hazard damage
common.check_lever_hit(hitbox)                 -- Check if hitbox overlaps lever and toggle it
common.player_has_item(player, item_id)        -- Check both stackable and unique items
common.add_stackable_item(player, id, count)   -- Add stackable item to inventory
common.consume_stackable_item(player, id, count) -- Consume stackable item, shows text effect
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
- Viewport culling: `Projectile.draw(camera)` skips off-screen entities (1 tile margin)

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

Visual feedback system for transient effects including animations, floating text, and particles. Manages one-shot effects that auto-cleanup when finished.

### Architecture

- Object pool pattern with separate pools: `state.all` (animations), `state.damage_texts`, `state.status_texts`, `state.fatigue_particles`, `state.collect_particles`
- Factory methods for specific effects
- Integrated into main loop via `Effects.update(dt)` and `Effects.draw()`
- Text width cached at creation to avoid per-frame measurement

### Current Effects

**Visual Effects:**
- `HIT` - Impact effect (16x16px, 4 frames, 80ms/frame, non-looping)
- `SHURIKEN_HIT` - Shuriken impact (8x8px, 6 frames, non-looping)

**Floating Text:**
- Damage text - Shows damage numbers above enemies (red, floats upward)
- Status text - Shows player state messages (TIRED, Low Energy, No Energy, Locked, Perfect Block)
- Gold/XP text - Accumulating pickup feedback that follows player

**Particles:**
- Fatigue particles - Sweat droplets when stamina exhausted
- Collect particles - Gold/yellow burst when collecting unique items

### Usage

```lua
-- Visual effects
Effects.create_hit(x, y, direction)           -- Generic hit effect
Effects.create_shuriken_hit(x, y, direction)  -- Shuriken-specific effect

-- Floating text
Effects.create_damage_text(x, y, damage)      -- Floating damage number
Effects.create_fatigue_text(x, y)             -- "TIRED" status
Effects.create_energy_text(x, y, current)     -- "Low Energy" or "No Energy"
Effects.create_locked_text(x, y, player)      -- "Locked" for doors
Effects.create_perfect_block_text(x, y)       -- "Perfect Block" (yellow)

-- Accumulating text (follows player)
Effects.create_gold_text(x, y, amount, player)-- Accumulating gold pickup
Effects.create_xp_text(x, y, amount, player)  -- Accumulating XP pickup

-- Particles
Effects.create_fatigue_particle(x, y)         -- Sweat particle
Effects.create_collect_particles(x, y)        -- Item collection burst
```

Effects are positioned in tile coordinates and converted to screen pixels for rendering.

### Creating Custom Effects

Effects use the object pool pattern. New effect types require:
1. Animation definition or text configuration in `Effects/init.lua`
2. Factory method (e.g., `Effects.create_energy_text`)

## Key Files

- `Enemies/init.lua` - Enemy manager and base class
- `Enemies/common.lua` - Shared enemy utilities (draw, is_blocked, create_death_state)
- `Enemies/ratto.lua` - Ratto enemy (patrol/chase AI)
- `Enemies/worm.lua` - Worm enemy (simple patrol)
- `Enemies/spike_slug.lua` - Spike slug enemy (defensive behavior)
- `Enemies/bat_eye.lua` - Bat eye enemy (waypoint patrol, flying)
- `Enemies/zombie.lua` - Zombie enemy (bounded patrol, chase, attack)
- `Enemies/ghost_painting.lua` - Ghost painting enemy (look-away attack, phasing)
- `Enemies/magician.lua` - Magician enemy (flying mage, homing projectiles, teleport dodge)
- `Enemies/guardian.lua` - Guardian enemy (heavy club wielder, jump attacks, no knockback)
- `Enemies/flaming_skull.lua` - Flaming skull enemy (bouncing flyer, energy drain)
- `Prop/init.lua` - Prop system manager (spawn, groups, state transitions)
- `Prop/state.lua` - Persistent state tables for hot reload (types, all, groups, global_draws, accumulated_states)
- `Prop/common.lua` - Shared prop utilities (draw, player_touching, damage_player)
- `Prop/button.lua` - Button prop (unpressed/pressed states)
- `Prop/campfire.lua` - Campfire prop (restore point)
- `Prop/spike_trap.lua` - Spike trap prop (5-state hazard with alternating mode)
- `Prop/pressure_plate.lua` - Pressure plate prop (entity-triggered with lift effect)
- `Prop/locked_door.lua` - Locked door prop (key-based or group-action unlock)
- `Prop/unique_item.lua` - Unique item prop (permanent collectibles)
- `Prop/unique_item_registry.lua` - Unique item definitions (sprites, sounds, equipment types, weapon stats)
- `Prop/stackable_item.lua` - Stackable item prop (consumable collectibles)
- `Prop/stackable_item_registry.lua` - Stackable item definitions (keys, consumables)
- `Prop/lever.lua` - Lever prop (toggleable switch with callbacks)
- `Prop/appearing_bridge.lua` - Appearing bridge prop (group-triggered fade-in/out platform)
- `Prop/decoy_painting.lua` - Decoy painting prop (visual-only ghost_painting lookalike)
- `Prop/spear_trap.lua` - Spear trap prop (wall-mounted projectile trap with internal Spear pool)
- `Prop/npc_common.lua` - NPC factory for creating dialogue-enabled NPCs
- `Prop/witch_npc.lua` - Witch merchant NPC definition
- `Prop/explorer_npc.lua` - Explorer NPC definition
- `Prop/adept_npc.lua` - Adept NPC definition
- `Prop/decoration.lua` - Decoration prop (non-interactive visual tiles)
- `Projectile/init.lua` - Throwable projectiles with physics
- `Effects/init.lua` - Visual effects manager (hit effects, particles)
- `Effects/state.lua` - Persistent state tables for hot reload
