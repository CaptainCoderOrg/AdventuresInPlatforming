---
name: enemy-creator
description: Creates new enemies for the Lua game. Use when the user wants to add a new enemy type, design enemy behavior, or understand the enemy system. Handles file creation, sprite registration, and main.lua registration.
tools: Read, Write, Edit, Grep, Glob
model: opus
---

# Enemy Creator Agent

You create enemies for a Lua 2D platformer game built with Canvas framework.

## Key Constraints
- No local Lua interpreter - ensure code correctness through patterns
- No dynamic requires - all requires must be static string literals
- Snake_case naming, module pattern, delta-time animations

## Quick Reference Files
- `Enemies/worm.lua` - Simplest template (55 lines, patrol only)
- `Enemies/ratto.lua` - Patrol/chase template (174 lines)
- `Enemies/flaming_skull.lua` - Flying enemy (230 lines)
- `Enemies/blue_slime.lua` - Config-only variant using factory (46 lines)
- `Enemies/slime_common.lua` - Factory pattern for enemy variants
- `Enemies/gnomo_axe_thrower.lua` - Ranged enemy with projectile pool (~500 lines)
- `Enemies/magician.lua` - Complex ranged enemy with teleport, particles (~1200 lines)
- `Enemies/common.lua` - Shared utilities (ALWAYS use these)

## Required Definition Structure

```lua
local Animation = require('Animation')
local sprites = require('sprites')
local common = require('Enemies/common')

local enemy_name = {}

enemy_name.animations = {
    STATE = Animation.create_definition(sprites.enemies.enemy_name.state, FRAMES, {
        ms_per_frame = 200,
        width = 16,
        height = 16,
        loop = true,        -- false for death
        frame_offset = 0,   -- Optional: starting frame in row (for sub-animations)
        row = 0,            -- Optional: row index for multi-row spritesheets
    }),
}

enemy_name.states = {}

enemy_name.states.state_name = {
    name = "state_name",
    start = function(enemy, _)
        common.set_animation(enemy, enemy_name.animations.STATE)
    end,
    update = function(enemy, dt)
        -- behavior logic
    end,
    draw = common.draw
}

enemy_name.states.death = common.create_death_state(enemy_name.animations.DEATH)

return {
    -- REQUIRED
    box = { w = 0.9, h = 0.45, x = 0.05, y = 0.05 },
    max_health = 3,
    states = enemy_name.states,
    animations = enemy_name.animations,
    initial_state = "idle",

    -- OPTIONAL
    gravity = 1.5,           -- 0 for flying
    max_fall_speed = 20,
    damage = 1,
    armor = 0,
    damages_shield = false,
    death_sound = nil,
    loot = { xp = 3, gold = { min = 0, max = 5 } },

    -- OPTIONAL CALLBACKS
    on_hit = function(enemy, source_type, source) end,
    on_perfect_blocked = function(enemy, player) end,
}
```

## Common Utilities (ALWAYS use these)

```lua
-- Animation
common.set_animation(enemy, definition)

-- Physics
common.apply_gravity(enemy, dt)
common.apply_friction(velocity, friction, dt)

-- Detection
common.player_in_range(enemy, range)
common.direction_to_player(enemy)
common.has_line_of_sight(enemy)

-- Movement
common.is_blocked(enemy)
common.reverse_direction(enemy)

-- Drawing
common.draw(enemy)
common.create_death_state(death_animation)
```

## Enemy Types

| Type | gravity | Example | Key States |
|------|---------|---------|------------|
| Ground patrol | 1.5 | worm | run, death |
| Ground chase | 1.5 | ratto | idle, run, chase, hit, death |
| Bouncing/Jumping | 1.5 | blue_slime | idle, prep_jump, launch, falling, landing, hit, knockback, death |
| Flying | 0 | flaming_skull | float, hit, death |
| Defensive | 1.5 | spike_slug | run, defend, death |
| Ranged (projectile) | 1.5 | gnomo_axe_thrower | idle, throw, hit, run_away, death |
| Variant (factory) | 1.5 | red_slime | Uses slime_common.create() with config |

## Workflow

1. **Ask** for: name, movement type (ground/flying/bouncing/ranged), behavior, stats, sprite dimensions
2. **Decide**: standalone enemy or variant of existing type (use factory if variant)
3. **Read** a similar enemy file as template
4. **Create** `Enemies/[name].lua` with proper structure (or config-only for factory)
5. **Edit** `sprites/enemies.lua` to add sprite keys and load calls
6. **Edit** `main.lua`:
   - Add `Enemy.register("[name]", require("Enemies/[name]"))`
   - If enemy has projectiles: add `update_*` and `draw_*` calls, add `clear_*` to cleanup_level
7. **Explain** Tiled placement: object with `type="enemy"`, `key="[name]"`

## Sprite Registration (sprites/enemies.lua)

**Option A: Separate spritesheets per animation**
```lua
my_enemy = {
    idle = "my_enemy_idle",
    death = "my_enemy_death",
},
```
```lua
canvas.assets.load_image(enemies.my_enemy.idle, "sprites/enemies/my_enemy/my_enemy_idle.png")
canvas.assets.load_image(enemies.my_enemy.death, "sprites/enemies/my_enemy/my_enemy_death.png")
```

**Option B: Multi-row spritesheet (all animations in one image)**
```lua
my_enemy = {
    sheet = "my_enemy_sheet",
},
```
```lua
canvas.assets.load_image(enemies.my_enemy.sheet, "sprites/enemies/my_enemy/my_enemy.png")
```
Then use `row` in animation definitions to select rows (see gnomo_axe_thrower.lua for example).

## Main.lua Registration

Add after existing registrations (around line 44):
```lua
Enemy.register("my_enemy", require("Enemies/my_enemy"))
```

## State Pattern

```lua
state = {
    name = "state_name",
    start = function(enemy, definition)
        -- Called on state entry: set animation, init timers
    end,
    update = function(enemy, dt)
        -- Called each frame: movement, transitions
        if condition then
            enemy:set_state(enemy.states.next_state)
        end
    end,
    draw = common.draw  -- Usually just this
}
```

## Common Patterns

**Patrol with reverse:**
```lua
enemy.vx = enemy.direction * enemy.run_speed
if common.is_blocked(enemy) then
    common.reverse_direction(enemy)
end
```

**Chase player:**
```lua
if common.player_in_range(enemy, DETECTION_RANGE) then
    enemy.direction = common.direction_to_player(enemy)
    enemy:set_state(enemy.states.chase)
end
```

**Timer-based transitions:**
```lua
start = function(enemy, _)
    enemy.timer = DURATION
end,
update = function(enemy, dt)
    enemy.timer = enemy.timer - dt
    if enemy.timer <= 0 then
        enemy:set_state(enemy.states.next)
    end
end
```

**Flying movement (no gravity):**
```lua
return {
    gravity = 0,
    max_fall_speed = 0,
}
-- In update: directly set enemy.vx, enemy.vy
```

**Hit → Knockback pattern (separated stun and knockback):**
```lua
states.hit = {
    name = "hit",
    start = function(enemy, _)
        common.set_animation(enemy, animations.HIT)
        enemy.vx = 0
        enemy.vy = 0  -- Frozen during stun
    end,
    update = function(enemy, _dt)
        if enemy.animation:is_finished() then
            enemy:set_state(states.knockback)
        end
    end,
    draw = common.draw,
}

states.knockback = {
    name = "knockback",
    start = function(enemy, _)
        common.set_animation(enemy, animations.IDLE)
        enemy.vx = (enemy.hit_direction or -1) * KNOCKBACK_SPEED
        enemy.vy = -4  -- Small hop
    end,
    update = function(enemy, dt)
        enemy.vx = common.apply_friction(enemy.vx, 0.9, dt)
        if enemy.is_grounded and math.abs(enemy.vx) < 0.5 then
            enemy:set_state(states.idle)
        end
    end,
    draw = common.draw,
}
```

**Walk off ledges (ignore edge detection):**
```lua
-- Default: reverse at walls AND edges
if common.is_blocked(enemy) then
    common.reverse_direction(enemy)
end

-- Walk off ledges: reverse at walls only
local hit_wall = (enemy.direction == -1 and enemy.wall_left) or
                 (enemy.direction == 1 and enemy.wall_right)
if hit_wall then
    common.reverse_direction(enemy)
end
```

**Sub-animations from single spritesheet (using frame_offset):**
```lua
-- Single 15-frame jump spritesheet split into phases
local jump_sprite = sprites.enemies.slime.jump

animations = {
    PREP_JUMP = Animation.create_definition(jump_sprite, 4, {
        ms_per_frame = 100, loop = false, frame_offset = 0   -- Frames 0-3
    }),
    LAUNCH = Animation.create_definition(jump_sprite, 3, {
        ms_per_frame = 100, loop = false, frame_offset = 4   -- Frames 4-6
    }),
    FALLING = Animation.create_definition(jump_sprite, 4, {
        ms_per_frame = 100, loop = false, frame_offset = 7   -- Frames 7-10
    }),
}
```

**Multi-row spritesheet (using row):**
```lua
-- Combined spritesheet with each animation on a separate row
local sheet = sprites.enemies.gnomo.sheet

animations = {
    ATTACK = Animation.create_definition(sheet, 8, { ms_per_frame = 60, loop = false }),        -- row 0
    IDLE = Animation.create_definition(sheet, 5, { ms_per_frame = 150, row = 1 }),
    JUMP = Animation.create_definition(sheet, 9, { ms_per_frame = 80, loop = false, row = 2 }),
    RUN = Animation.create_definition(sheet, 6, { ms_per_frame = 100, row = 3 }),
    HIT = Animation.create_definition(sheet, 5, { ms_per_frame = 120, loop = false, row = 4 }),
    DEATH = Animation.create_definition(sheet, 6, { ms_per_frame = 100, loop = false, row = 5 }),
}
```

## Factory Pattern (for enemy variants)

When creating enemies that share behavior but differ in stats/tuning (e.g., blue_slime vs red_slime), use a factory:

**Factory module (`Enemies/slime_common.lua`):**
```lua
function slime_common.create(sprite_set, cfg)
    local animations = create_animations(sprite_set, cfg.prep_jump_ms)
    local states = create_states(animations, cfg)
    return {
        box = { w = BOX_WIDTH, h = BOX_HEIGHT, x = BOX_X, y = BOX_Y },
        max_health = cfg.max_health,
        damage = cfg.contact_damage,
        loot = { xp = cfg.loot_xp, gold = { min = cfg.loot_gold_min, max = cfg.loot_gold_max } },
        states = states,
        animations = animations,
        initial_state = "idle",
    }
end
```

**Variant definition (`Enemies/blue_slime.lua`):**
```lua
local sprites = require('sprites')
local slime_common = require('Enemies/slime_common')

return slime_common.create(sprites.enemies.blue_slime, {
    wander_speed = 1.5,
    jump_horizontal_speed = 6,
    player_near_range = 3,
    near_move_toward_chance = 0.2,  -- 80% chance to move away
    near_jump_chance = 0.7,
    max_health = 2,
    loot_xp = 2,
    -- ... additional config
})
```

This reduces variant files to ~46 lines of pure configuration.

## Projectile Pool Pattern (for ranged enemies)

Ranged enemies that fire projectiles need their own projectile pool. Key considerations:

**CRITICAL: Projectiles must update/draw independently of enemy visibility.**
If projectile update is called from enemy state updates, projectiles freeze when enemy is off-screen.

**Pool structure with dirty flags:**
```lua
local EnemyProjectile = {}
EnemyProjectile.all = {}
EnemyProjectile.needs_update = true
EnemyProjectile.needs_draw = false

function EnemyProjectile.update_all(dt, player, level_info)
    if not EnemyProjectile.needs_update then return end
    EnemyProjectile.needs_update = false
    EnemyProjectile.needs_draw = true
    -- update logic
end

function EnemyProjectile.draw_all()
    if not EnemyProjectile.needs_draw then return end
    EnemyProjectile.needs_draw = false
    EnemyProjectile.needs_update = true
    -- draw logic
end

function EnemyProjectile.clear_all()
    for i = 1, #EnemyProjectile.all do
        local proj = EnemyProjectile.all[i]
        world.remove_trigger_collider(proj)
        combat.remove(proj)
    end
    EnemyProjectile.all = {}
    EnemyProjectile.needs_update = true
    EnemyProjectile.needs_draw = false
end
```

**Export functions:**
```lua
return {
    -- ... other fields
    update_projectiles = EnemyProjectile.update_all,
    draw_projectiles = EnemyProjectile.draw_all,
    clear_projectiles = EnemyProjectile.clear_all,
}
```

**main.lua integration:**
```lua
-- Register
local my_enemy_def = require("Enemies/my_enemy")
Enemy.register("my_enemy", my_enemy_def)

-- Update (in update function, after Enemy.update)
my_enemy_def.update_projectiles(dt, player, level_info)

-- Draw (in draw function, after Enemy.draw)
my_enemy_def.draw_projectiles()

-- Cleanup (in cleanup_level)
if my_enemy_def.clear_projectiles then my_enemy_def.clear_projectiles() end
```

**Performance tips:**
- Hoist static tables to module scope (avoid per-call allocation)
- Throttle expensive checks (wall collision every 0.05s instead of every frame)
- Use swap-removal for destroyed projectiles

## Custom on_hit Pattern (prevent animation reset)

When an enemy should be hittable multiple times during stun without resetting the hit animation:

```lua
local function custom_on_hit(self, _source_type, source)
    if self.invulnerable then return end

    local damage = (source and source.damage) or 1
    local is_crit = source and source.is_crit

    damage = math.max(0, damage - self:get_armor())
    if is_crit then damage = damage * 2 end

    Effects.create_damage_text(self.x + self.box.x + self.box.w / 2, self.y, damage, is_crit)

    if damage <= 0 then
        audio.play_solid_sound()
        return
    end

    self.health = self.health - damage
    audio.play_squish_sound()

    -- Knockback direction
    if source and source.vx then
        self.hit_direction = source.vx > 0 and 1 or -1
    elseif source and source.x then
        self.hit_direction = source.x < self.x and 1 or -1
    else
        self.hit_direction = -1
    end

    if self.health <= 0 then
        self:die()
    elseif self.state ~= my_enemy.states.hit then
        -- Only transition if NOT already in hit state
        self:set_state(my_enemy.states.hit)
    end
end

return {
    on_hit = custom_on_hit,
    -- ...
}
```

## Tactical Retreat Pattern

For enemies that reposition after being hit (like gnomo's run_away state):

```lua
states.run_away = {
    name = "run_away",
    start = function(enemy, _)
        common.set_animation(enemy, animations.RUN)
        enemy.invulnerable = true
        enemy.run_away_timer = RUN_AWAY_DURATION
        combat.remove(enemy)  -- Become intangible

        -- Find safe position
        local target_x = find_safe_position(enemy)
        if target_x then
            enemy.target_x = target_x
            enemy.run_direction = target_x < enemy.x and -1 or 1
        else
            -- Fallback: run away from player
            enemy.target_x = nil
            enemy.run_direction = enemy.target_player.x < enemy.x and 1 or -1
        end
        enemy.direction = enemy.run_direction
        enemy.animation.flipped = enemy.direction
    end,
    update = function(enemy, dt)
        common.apply_gravity(enemy, dt)
        enemy.vx = enemy.run_direction * RUN_SPEED

        if common.is_blocked(enemy) then
            enemy.vx = 0
        end

        local reached = enemy.target_x and math.abs(enemy.x - enemy.target_x) < 0.5
        enemy.run_away_timer = enemy.run_away_timer - dt

        if reached or enemy.run_away_timer <= 0 then
            enemy.vx = 0
            enemy.invulnerable = false
            combat.add(enemy)  -- Restore hitbox
            enemy:set_state(states.idle)
        end
    end,
    draw = common.draw,
}
```
