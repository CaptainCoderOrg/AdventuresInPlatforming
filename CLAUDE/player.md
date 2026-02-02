# Player System

<!-- QUICK REFERENCE
- State machine: start(), input(), update(dt), draw()
- States: idle, run, dash, air, wall_slide, wall_jump, climb, attack, throw, hammer, block, hit, death, rest
- Key file: player/init.lua, player/common.lua
- Stamina costs in player/common.lua
-->

## State Machine Pattern

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

## Learnable Abilities

Abilities are gated behind unlock flags (set via progression/items). Checked in `player/common.lua`.

| Ability | Unlock Flag | Checked In |
|---------|-------------|------------|
| Double Jump | `has_double_jump` | `handle_air_jump()` |
| Wall Slide | `has_wall_slide` | state transitions |
| Hammer | `has_hammer` | `handle_hammer()` |
| Shield/Block | `has_shield` | `handle_block()` |
| Dash | `can_dash` | `handle_dash()` |
| Axe Throw | `has_axe` | `is_projectile_unlocked()` |
| Shuriken | `has_shuriken` | `is_projectile_unlocked()` |

**Note:** `can_dash` is the unlock flag (progression). `has_dash` is a separate cooldown flag that resets when grounded.

**Secondary Items:** Up to 4 secondary items (throwables) can be equipped simultaneously. `player.active_secondary` tracks which one is currently in use. Cycle with 0 key or Gamepad SELECT.

## Combat System

Player combat abilities managed through state machine.

### Attack States

1. **Attack (Combo System)** - `player/attack.lua`
   - 3-hit combo chain (pattern: 1 → 2 → 3 → 2 → 3 → 2 → 3...)
   - Input queueing: can buffer next attack during current swing
   - Hold window: 0.16s after animation for combo input
   - Cooldown: 0.2s between combo chains
   - **Weapon Switching**: `player/weapon_sync.lua` manages equipped weapon
     - Cycle with 0 key or Gamepad SELECT
     - `player.active_weapon` tracks currently selected weapon item_id
     - Stats flow from `unique_item_registry.lua` via `weapon_sync.get_weapon_stats()`
   - **Per-Weapon Stats** (from equipped weapon):
     - `damage` - Damage per hit
     - `stamina_cost` - Stamina consumed per swing
     - `ms_per_frame` - Animation speed (lower = faster attacks)
     - `hitbox` - Width, height, y_offset in tiles
     - `animation` - Variant: "default", "short", or "wide"
   - **Active Frames**: Frame 2 to (frame_count - 2)
   - **Hit Tracking**: `attack_state.hit_enemies` prevents double-hits per swing

2. **Throw (Ability)** - `player/throw.lua`
   - Launches selected projectile on entry (Axe or Shuriken)
   - Can move horizontally during throw
   - Duration: animation length (7 frames, 33ms/frame)
   - **Secondary Cycling System:**
     - Up to 4 secondary items can be equipped simultaneously
     - `player.active_secondary` tracks currently selected secondary item_id
     - Cycle with 0 key or Gamepad SELECT via `weapon_sync.cycle_secondary()`
     - Uses `weapon_sync.get_equipped_secondaries()` to fetch all equipped
     - Uses `weapon_sync.get_active_secondary()` to get current selection
     - Uses `weapon_sync.get_secondary_spec()` to get projectile definition

3. **Hammer** - `player/hammer.lua`
   - Heavy stationary attack (7 frames, 150ms/frame)
   - Locks player movement (vx=0, vy=0)
   - 32px wide sprite

4. **Block** - `player/block.lua`, `player/block_move.lua`
   - Defensive stance (hold U or Gamepad RT)
   - Stops horizontal movement (block) or slows to 35% (block_move)
   - Shield logic centralized in `player/shield.lua`
   - **Perfect Block**: First 4 frames (~67ms) of stationary block allow perfect parry
     - No stamina cost on perfect block
     - Shows "Perfect Block" yellow text feedback
     - Triggers `enemy:on_perfect_blocked(player)` callback for custom reactions
     - Invalidated by: moving, attacking from block, or transitioning to block_move
     - 6-frame cooldown between perfect block opportunities
   - Normal block: drains stamina proportional to damage (reduced by 2x defense)
   - Guard break exits to idle when stamina depleted
   - Knockback applied when absorbing hits
   - Gravity still applies

5. **Hit** - `player/hit.lua`
   - Entered when player takes damage
   - Knockback away from damage source (2 px/frame)
   - Animation duration: 240ms (3 frames @ 80ms)
   - Uses centralized input queue for buffering

### Input Queuing System

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

### Invincibility System

- **Duration**: 1.2 seconds after hit animation completes
- **Visual Feedback**: Alpha blinking (oscillates 0.5-1.0)
- **Check**: `Player:is_invincible()` returns true during immunity
- Prevents rapid consecutive hits from enemies

## Stamina/Energy System

Resource management for abilities with fatigue mechanic.

### Stamina Properties

- `max_stamina = 5` - Maximum stamina pool
- `stamina_used` - Tracks consumption (can exceed max for fatigue)
- `stamina_regen_rate = 5` - Regeneration per second (normal)
- `stamina_regen_cooldown = 0.5s` - Delay before regen starts

### Stamina Costs (`player/common.lua`)

```lua
ATTACK_STAMINA_COST = 2      -- Per sword swing
HAMMER_STAMINA_COST = 5      -- Full bar (heavy attack)
AIR_JUMP_STAMINA_COST = 1    -- Double jump
DASH_STAMINA_COST = 2.5      -- Dash ability
WALL_JUMP_STAMINA_COST = 1   -- Wall jump
```

### Fatigue System

Triggered when `stamina_used > max_stamina`:
- **Entry Penalty**: +1 stamina debt added on entering fatigue
- **Speed Penalty**: 75% movement speed while fatigued
- **Regen Penalty**: 25% regeneration rate (1.25/second vs 5/second)
- **Visual Feedback**: TIRED effect, sweat particles, pulsing orange/red meter

**Key Methods:**
```lua
player:use_stamina(amount)   -- Consume stamina, returns false if fatigued
player:is_fatigued()         -- True if stamina_used > max_stamina
player:get_speed()           -- Returns speed with fatigue penalty applied
```

### Energy System

- `max_energy = 4` - Projectile ammunition pool
- `energy_used` - Tracks projectile consumption
- Currently used for throw ability resource tracking
- **Visual Feedback**: "Low Energy" or "No Energy" text appears when throw attempted with insufficient energy
- **UI Flash**: `energy_flash_requested` triggers energy bar flash on failed throw

## Level Progression System

Player leveling at campfire rest screen via stat upgrades.

### Experience Requirements

Fibonacci-like sequence: each level requires the sum of the previous two levels' XP.

| Level | XP Required |
|-------|-------------|
| 1     | 10          |
| 2     | 20          |
| 3     | 30          |
| 4     | 50          |
| 5     | 80          |
| 6     | 130         |
| ...   | (continues to level 100) |

### Levelable Stats

Each stat upgrade costs XP equal to the "Next Level" requirement and increases player level by 1:

| Stat     | Property Affected   | Per-Point Bonus |
|----------|---------------------|-----------------|
| Health   | `max_health`        | +1 HP           |
| Stamina  | `max_stamina`       | +1 SP           |
| Energy   | `max_energy`        | +1 EP           |
| Defence  | `defense`           | Diminishing returns (see below) |
| Recovery | `recovery`          | Diminishing returns (see below) |
| Critical | `critical_chance`   | Diminishing returns (see below) |

**Diminishing Returns (`player/stats.lua`):**

Defence, Recovery, and Critical use per-stat progression curves where early points grant more benefit:

| Stat     | Point 1 | Point 2 | Point 3 | Point 4 | Point 5 | Point 6+ |
|----------|---------|---------|---------|---------|---------|----------|
| Defence  | 5%      | 5%      | 5%      | 3%      | 3%      | 3%/2.5%  |
| Recovery | 5%      | 5%      | 5%      | 5%      | 5%      | 2.5%     |
| Critical | 5%      | 4%      | 3%      | 2.5%    | 2.5%    | 2.5%     |

### Upgrade Flow

1. Open rest screen at campfire
2. Navigate to Status panel
3. Highlight a stat and click/press to queue upgrade (if XP available)
4. Confirm to apply all pending upgrades, or cancel to discard
5. Player level increases by total upgrades applied

**Key Methods (`ui/status_panel.lua`):**
```lua
panel:can_level_up()           -- True if player has enough XP for next level
panel:add_pending_upgrade()    -- Queue upgrade for highlighted stat
panel:remove_pending_upgrade() -- Remove queued upgrade
panel:confirm_upgrades()       -- Apply all pending upgrades
panel:cancel_upgrades()        -- Discard pending upgrades
```

## Player Properties Reference

```lua
self.max_health = 3             -- Starting health
self.damage = 0                 -- Cumulative damage taken
self.invincible_time = 0        -- Invincibility countdown (seconds)
self.active_weapon = nil        -- Currently equipped weapon item_id (synced via weapon_sync)
self.active_secondary = nil     -- Currently active secondary item_id (for ability swap)
self.attack_cooldown = 0        -- Countdown timer (attack)
self.throw_cooldown = 0         -- Countdown timer (throw)
self.level = 1                  -- Player level (progression)
self.experience = 0             -- XP toward next level
self.gold = 0                   -- Currency for purchases
self.defense = 0                -- Reduces incoming damage
self.strength = 5               -- Base damage multiplier
self.critical_chance = 0        -- Percent chance for critical hit
self.recovery = 0               -- Bonus regeneration rate
self.stat_upgrades = {}         -- Tracks upgrade counts per stat {Health=2, Stamina=1, ...}
self.attack_state = {           -- Combo tracking
    count, next_anim_ix, remaining_time, queued, hit_enemies
}
self.hit_state = {              -- Hit stun tracking
    knockback_speed, remaining_time
}
self.block_state = {            -- Shield and perfect block tracking
    knockback_velocity,         -- Current knockback velocity from blocked hits
    perfect_window,             -- nil = fresh session, 0 = invalidated, >0 = active window
    cooldown,                   -- Time until next perfect block allowed
}
self.input_queue = {            -- Centralized input buffering
    jump, attack, throw         -- Boolean flags for pending inputs
}
self.max_stamina = 5            -- Maximum stamina points
self.stamina_used = 0           -- Consumed stamina (can exceed max for fatigue)
self.stamina_regen_rate = 5     -- Stamina regenerated per second
self.stamina_regen_cooldown = 0.5  -- Seconds before regen begins after use
self.stamina_regen_timer = 0    -- Time since last stamina use
self.max_energy = 4             -- Maximum energy points (for projectiles)
self.energy_used = 0            -- Consumed energy
```

## Animation System

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

## Rendering

Player states should use `common.draw(player)` for rendering, which applies pressure plate lift offset automatically:

```lua
function state.draw(player)
    common.draw(player)  -- Handles pressure plate lift
end
```

**Special cases:**
- `common.draw_blocking(player)` - For block states (includes shield debug rendering)
- Manual draw with custom Y offset (e.g., rest state with `REST_Y_OFFSET`)

## Key Files

- `player/init.lua` - Player state registry and core logic
- `player/common.lua` - Shared physics, collision utilities, stamina costs, rendering helpers
- `player/stats.lua` - Stat percentage calculations with diminishing returns (O(1) lookup)
- `player/attack.lua` - Combat combo system (includes weapon hitbox)
- `player/weapon_sync.lua` - Equipped weapon management, cycling, and ability flag sync
- `player/throw.lua` - Projectile throwing state
- `player/hammer.lua` - Heavy attack state
- `player/block.lua` - Defensive stance
- `player/shield.lua` - Shield lifecycle, damage blocking, knockback physics
- `player/hit.lua` - Hit stun with invincibility and input queueing
- `player/rest.lua` - Rest state (campfire interaction, save trigger)
- `Animation/init.lua` - Delta-time animation system
