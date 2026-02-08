# Player System

<!-- QUICK REFERENCE
- State machine: start(), input(), update(dt), draw()
- States: idle, run, dash, air, wall_slide, wall_jump, climb, attack, throw, hammer, block, block_move, hit, death, rest, stairs_up, stairs_down, cinematic
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

**States:** idle, run, dash, air, wall_slide, wall_jump, climb, attack, throw, hammer, block, block_move, hit, death, rest, stairs_up, stairs_down, cinematic

States are registered in `player/init.lua`. Common utilities (gravity, jump, collision checks, ability handlers) are in `player/common.lua`.

## Learnable Abilities

Abilities are gated behind unlock flags (set via progression/items). Checked in `player/common.lua`.

| Ability | Unlock Flag | Checked In |
|---------|-------------|------------|
| Double Jump | `has_double_jump` | `handle_air_jump()` |
| Wall Slide | `has_wall_slide` | state transitions |
| Hammer | `has_hammer` | `handle_ability()` / `weapon_sync.is_secondary_unlocked()` |
| Shield/Block | `has_shield` | `handle_block()` |
| Dash | `can_dash` | `handle_dash()` |
| Axe Throw | `has_axe` | `weapon_sync.is_secondary_unlocked()` |
| Shuriken | `has_shuriken` | `weapon_sync.is_secondary_unlocked()` |

**Note:** `can_dash` is the unlock flag (derived from `dash_slot` presence). Dash uses the charge system (`max_charges=1, recharge=1s`) instead of a ground-reset cooldown.

**Secondary Items:** Up to 6 secondary items can be assigned to ability slots (`player.ability_slots[1..6]`). Each slot is bound to a dedicated key (`ability_1` through `ability_6`). `player.active_ability_slot` tracks which slot triggered the current throw/heal/dash action. Secondaries come in several types:
- **Throwable** (e.g., throwing axe, shuriken): Press the slot's ability key to launch a projectile. `weapon_sync.get_secondary_spec(player, slot)` returns the projectile spec, or nil for non-throwable secondaries.
- **Channeled** (e.g., minor healing): Hold the slot's ability key to continuously activate. Channeling logic in `player/heal_channel.lua` loops all 6 slots each frame during `Player:update()`.
- **Dash** (dash_amulet): Press the slot's ability key to dash. Uses dedicated `handle_dash()` handler (not the generic ability flow). Charge-based cooldown.
- **Shield** (shield): Hold the slot's ability key to block. Uses dedicated `handle_block()` handler. No charges.

**Charge System:** Throwable secondaries have limited charges that recharge over time. Defined in `unique_item_registry.lua` via `max_charges` and `recharge` fields. Runtime state tracked in `player.charge_state` (per-item `used_charges` and `recharge_timer`). Charges managed by `weapon_sync`: `has_throw_charges(player, slot)`, `consume_charge(player)`, `update_charges(dt)`, `get_charge_info()`. Charges reset on rest.

## Combat System

Player combat abilities managed through state machine.

### Attack States

1. **Attack (Combo System)** - `player/attack.lua`
   - 3-hit combo chain (pattern: 1 → 2 → 3 → 2 → 3 → 2 → 3...)
   - Input queueing: can buffer next attack during current swing
   - Hold window: 0.16s after animation for combo input
   - Cooldown: 0.2s between combo chains
   - **Weapon Switching**: `player/weapon_sync.lua` manages equipped weapon
     - Cycle with E key or Gamepad SELECT
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
   - **Ability Slot System:**
     - 6 ability slots (`player.ability_slots[1..6]`) with dedicated keybindings
     - `player.active_ability_slot` tracks which slot triggered the current throw
     - Uses `weapon_sync.get_slot_secondary(player, slot)` for slot lookup
     - Uses `weapon_sync.get_secondary_spec(player, slot)` for projectile definition
   - **Charge System:**
     - Throwable secondaries have limited charges (e.g., throwing axe: 2 charges, 2s recharge; shuriken: 2 charges, 5s recharge)
     - `weapon_sync.has_throw_charges(player, slot)` gates throw attempts
     - `weapon_sync.consume_charge(player)` called in `throw.start()` (uses `player.active_ability_slot`)
     - `weapon_sync.update_charges(player, dt)` ticks recharge timers each frame
     - Shows "Cooldown" text when attempting throw with 0 charges
     - Charges reset at campfires (`rest.start()`)

3. **Hammer** - `player/hammer.lua`
   - Heavy stationary attack (7 frames, 150ms/frame)
   - Locks player movement (vx=0, vy=0)
   - 32px wide sprite

4. **Block** - `player/block.lua`, `player/block_move.lua`
   - Defensive stance (hold shield's ability slot key)
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

- **Queue Storage**: `player.input_queue` tracks pending inputs (jump, attack, ability_slot)
- **During Locked States**: `common.queue_inputs(player)` captures button presses
- **On State Exit**: `common.process_input_queue(player)` executes queued actions
- **Priority Order**: Attack > Ability > Jump
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

- `max_stamina = 3` - Maximum stamina pool
- `stamina_used` - Tracks consumption (can exceed max for fatigue)
- `stamina_regen_rate = 3` - Regeneration per second
- `stamina_regen_cooldown = 0.5s` - Delay before regen starts
- `fatigue_remaining` - Seconds remaining in fatigue state (0 = not fatigued)

### Stamina Costs (`player/common.lua`)

```lua
ATTACK_STAMINA_COST = 2      -- Per sword swing
AIR_JUMP_STAMINA_COST = 1    -- Double jump
DASH_STAMINA_COST = 2.5      -- Dash ability
WALL_JUMP_STAMINA_COST = 1   -- Wall jump
-- Hammer stamina cost (5) is defined in unique_item_registry.hammer.stats
```

### Fatigue System

Triggered when `stamina_used > max_stamina` (timer-based, 1.5s fixed duration):
- **Duration**: 1.5 seconds (`common.FATIGUE_DURATION` in `player/common.lua`)
- **Speed Penalty**: 75% movement speed while fatigued
- **Stamina Lock**: Cannot use stamina-costing abilities while fatigued
- **Regen**: Normal stamina regeneration continues during fatigue
- **Visual Feedback**: TIRED effect, sweat particles, pulsing orange/red meter

**Key Methods:**
```lua
player:use_stamina(amount)   -- Consume stamina, returns false if fatigued; triggers fatigue if overspent
player:is_fatigued()         -- True if fatigue_remaining > 0 (timer active)
player:get_speed()           -- Returns speed with fatigue penalty applied
```

### Energy System

- `max_energy = 3` - Ability resource pool
- `energy_used` - Tracks energy consumption
- Used by throwable secondaries (1 per throw) and channeled secondaries (continuous drain)
- **Heal Channeling**: Minor Healing converts energy to health at 1:1 ratio (1 HP/sec). Channels during idle, run, and air states. Managed by `player/heal_channel.lua`.
- **Visual Feedback**: "Low Energy" or "No Energy" text appears when ability attempted with insufficient energy
- **UI Flash**: `energy_flash_requested` triggers energy bar flash on failed throw

## Level Progression System

Player leveling at campfire rest screen via stat upgrades.

### Per-Stat XP Costs

Each stat has its own fibonacci-like XP cost sequence (`ui/status_panel.lua`). Each upgrade increases player level by 1.

| Stat     | Seeds             | First 5 costs         |
|----------|-------------------|-----------------------|
| Health   | 3, 8, 20, 30     | 3, 8, 20, 30, 50     |
| Stamina  | 5, 15, 25        | 5, 15, 25, 40, 65    |
| Energy   | 25, 50           | 25, 50, 75, 125, 200 |
| Defence  | 20, 30           | 20, 30, 50, 80, 130  |
| Recovery | 20, 40           | 20, 40, 60, 100, 160 |
| Critical | 50, 100          | 50, 100, 150, 250, 400 |

### Levelable Stats

| Stat     | Property Affected   | Per-Point Bonus |
|----------|---------------------|-----------------|
| Health   | `max_health`        | +1 HP           |
| Stamina  | `max_stamina`       | +1 SP           |
| Energy   | `max_energy`        | +1 EP           |
| Defence  | `defense`           | Diminishing returns (see below) |
| Recovery | `recovery`          | Diminishing returns (see below) |
| Critical | `critical_chance`   | Diminishing returns (see below) |

**Diminishing Returns (`player/stats.lua`):**

Per-stat progression curves where early points grant more benefit. Default is 2.5% per point beyond the defined tiers.

| Stat     | Tiers (% per point)            |
|----------|--------------------------------|
| Defence  | 5, 5, 5, 3, 3, 3, 3, 3, 2.5   |
| Recovery | 10, 7.5, 5, 5, 2.5, 2.5, 2.5  |
| Critical | 2.5 (flat, no diminishing)     |

### Upgrade Flow

1. Open rest screen at campfire
2. Navigate to Status panel
3. Highlight a stat and click/press to queue upgrade (if XP available)
4. Confirm to apply all pending upgrades, or cancel to discard
5. Player level increases by total upgrades applied

**Key Methods (`ui/status_panel.lua`):**
```lua
panel:can_level_up()           -- True if player can afford any stat upgrade
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
self.ability_slots = { nil, nil, nil, nil, nil, nil }  -- 6 ability slots, each holds item_id or nil
self.active_ability_slot = nil  -- Which slot (1-6) triggered current throw/heal
self.attack_cooldown = 0        -- Countdown timer (attack)
self.throw_cooldown = 0         -- Countdown timer (throw)
self.level = 0                  -- Player level (sum of all stat upgrades)
self.experience = 0             -- XP spent on stat upgrades
self.gold = 0                   -- Currency for purchases
self.defense = 0                -- Reduces incoming damage
self.critical_chance = 2        -- Percent chance for critical hit (2 points = 5% base)
self.recovery = 0               -- Bonus regeneration rate
self.stat_upgrades = {}         -- Tracks upgrade counts per stat {Health=2, Stamina=1, ...}
self.upgrade_tiers = {}         -- Equipment upgrade tiers (item_id -> tier_number), managed by upgrade/effects.lua
self.defeated_bosses = {}       -- Set of defeated boss ids (boss_id -> true), persisted on rest
self.visited_campfires = {}     -- Visited campfires keyed by "level_id:name" -> {name, level_id, x, y}
self.dialogue_flags = {}        -- Dialogue condition flags (flag_name -> true), managed by dialogue/manager.lua
self.journal = {}               -- Quest journal entries (entry_id -> "active"|"complete")
self.journal_read = {}          -- Read tracking for journal unread indicators (entry_id -> true)
self.difficulty = "normal"      -- Difficulty setting ("normal" or "easy")
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
    jump,                       -- boolean
    attack,                     -- boolean
    ability_slot,               -- number (1-6) or nil
}
self.max_stamina = 3            -- Maximum stamina points
self.stamina_used = 0           -- Consumed stamina (can exceed max for fatigue)
self.stamina_regen_rate = 3     -- Stamina regenerated per second
self.stamina_regen_cooldown = 0.5  -- Seconds before regen begins after use
self.stamina_regen_timer = 0    -- Time since last stamina use
self.fatigue_remaining = 0      -- Seconds remaining in fatigue state (0 = not fatigued)
self.max_energy = 3             -- Maximum energy points (for projectiles)
self.energy_used = 0            -- Consumed energy
self.charge_state = {}          -- Runtime charge state per secondary item
                                -- { item_id = { used_charges, recharge_timer } }
self._heal_channeling = false   -- True while actively converting energy to health
self._heal_no_energy_shown = false -- Prevents repeated "No Energy" text per button hold
self._heal_particle_timer = 0   -- Accumulator for heal particle spawn interval
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
    width = 16,          -- Frame width (default: 16)
    height = 16,         -- Frame height (default: 16)
    loop = true,         -- Loop animation (default: true)
    frame_offset = 0,    -- Starting frame index in row (default: 0)
    row = 0              -- Row index for multi-row spritesheets (default: 0)
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

**Multi-row Spritesheets:** Use `row` to select which row of a combined spritesheet contains the animation frames. This allows multiple animations to be stored in a single image file (e.g., gnomo enemy uses rows 0-5 for attack, idle, jump, run, hit, death).

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
- `player/heal_channel.lua` - Heal channeling system (hold ability to convert energy to health)
- `player/throw.lua` - Projectile throwing state
- `player/hammer.lua` - Heavy attack state
- `player/block.lua` - Defensive stance
- `player/shield.lua` - Shield lifecycle, damage blocking, knockback physics
- `player/hit.lua` - Hit stun with invincibility and input queueing
- `player/rest.lua` - Rest state (campfire interaction, save trigger)
- `Animation/init.lua` - Delta-time animation system
