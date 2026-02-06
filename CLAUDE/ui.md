# UI System

<!-- QUICK REFERENCE
- State pattern: HIDDEN, FADING_IN, OPEN, FADING_OUT
- Input priority: Audio/Controls > Slot > Title > GameOver > Rest
- Title: title_screen.show(), set callbacks for menu items
- Slot: slot_screen.show(), set_slot_callback()
- Rest: rest_screen.show(x, y, camera, player) or show_pause()
-->

## State Machine Pattern

All screens use identical states: `HIDDEN`, `FADING_IN`, `OPEN`, `FADING_OUT`
- Fade animations using delta-time
- Configurable fade durations (typically 0.25s)
- Mouse/keyboard input with priority blocking

## Input Priority (highest to lowest)

1. Audio/Controls dialogs
2. Slot screen
3. Title screen
4. Game over screen
5. Rest screen (includes pause mode)

## Title Screen (`ui/title_screen.lua`)

- Main menu with "Play Game", "Audio", and "Controls" options
- Animated cursor using player idle sprite
- Callbacks for menu selections

```lua
title_screen.show()                      -- Display with fade-in
title_screen.input()                     -- Handle navigation
title_screen.update(dt, block_mouse)     -- Update animations
title_screen.draw()                      -- Render menu
title_screen.set_play_game_callback(fn)  -- "Play Game" callback
title_screen.set_audio_callback(fn)      -- "Audio" callback
title_screen.set_controls_callback(fn)   -- "Controls" callback
```

## Slot Screen (`ui/slot_screen.lua`)

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

## Rest Screen (`ui/rest_screen.lua`)

- Dual mode: Rest (campfire) and Pause (ESC/START during gameplay)
- Circular viewport effect centered on campfire (rest mode only)
- Menu navigation with sub-panels: Status, Map, Controls, Audio, Continue, Return to Title
- Integrated audio sliders and keybind panel
- Confirmation dialog for Return to Title

```lua
rest_screen.show(world_x, world_y, camera, player)  -- Show rest mode at campfire
rest_screen.show_pause(player, camera)              -- Show pause mode during gameplay
rest_screen.update(dt)                              -- Update animations
rest_screen.draw()                                  -- Render screen
rest_screen.trigger_continue()                      -- Initiate fade-out
rest_screen.is_pause_mode()                         -- Check if in pause vs rest mode
rest_screen.is_in_submenu()                         -- Check if viewing a sub-panel
rest_screen.set_continue_callback(fn)               -- Callback after rest continue
rest_screen.set_return_to_title_callback(fn)        -- Callback for title return
```

**Navigation Modes:** `MENU` (main buttons), `SETTINGS` (map/controls/audio panels), `CONFIRM` (return to title dialog), `FAST_TRAVEL` (campfire teleport panel)

**Extended States:** `HIDDEN` -> `FADING_IN` -> `OPEN` -> `FADING_OUT` -> `RELOADING` -> `FADING_BACK_IN` -> `HIDDEN`

### Visual Effects (rest mode)

- Circular clipping with `evenodd` fill rule
- Radial gradient vignette
- Sine wave pulse (2 Hz, +/-8% radius variation)
- Glow ring with orange/yellow gradient

## Map Panel (`ui/map_panel.lua`)

- Minimap overlay shown in the rest/pause screen Map sub-panel
- Renders wall outlines as 3x3px rects, campfires as 4x4 sprites, player as blinking green dot
- Player-centered view with WASD/DPad scrolling support
- Fog-of-war: only visited camera_bounds regions are rendered
- Visited state persisted in save data (`visited_bounds` array)

```lua
map_panel.build(width, height, camera_bounds)  -- Cache wall/campfire data (call after props spawn)
map_panel.mark_visited(px, py)                 -- Track exploration (called per-frame in main.lua)
map_panel.get_visited()                        -- Get visited indices for save
map_panel.set_visited(visited_indices)          -- Restore from save data
map_panel.scroll(dx, dy, dt)                   -- Pan map view
map_panel.reset_scroll()                       -- Re-center on player
map_panel.draw(x, y, w, h, player, elapsed)   -- Render minimap in panel
```

## Fast Travel Panel (`ui/fast_travel_panel.lua`)

- Destination picker shown when using Orb of Teleportation at a campfire
- Displays all previously visited campfires (excluding the current one)
- Supports keyboard/gamepad navigation and mouse hover/click
- Grouped by level with display name mapping
- Only available in REST mode (not pause mode)

```lua
fast_travel_panel.show(visited_campfires, current_key)  -- Open with campfire data
fast_travel_panel.hide()                                 -- Close panel
fast_travel_panel.is_active()                            -- Check if open
fast_travel_panel.input()                                -- Returns {action, destination} or nil
fast_travel_panel.update(dt, local_mx, local_my, mouse)  -- Mouse hover detection
fast_travel_panel.handle_click()                         -- Mouse click handling
fast_travel_panel.draw(x, y, width, height)              -- Render in info panel area
```

## Audio Dialog (`ui/audio_dialog.lua`)

- Standalone dialog for volume settings (Master, Music, SFX sliders)
- Accessible from title screen "Audio" option
- Hold-to-repeat slider adjustment

## Controls Dialog (`ui/controls_dialog.lua`)

- Standalone dialog for keybind settings
- Accessible from title screen "Controls" option
- Uses keybind_panel for two-column layout

## Projectile Selector Widget (`ui/projectile_selector.lua`)

- Bottom-left HUD widget showing equipped weapon and resource meters
- Three horizontal meters: HP (red), SP (green/orange), EP (blue)
- Shows attack control icon on weapon slot
- Shows swap weapon control icon (bottom-left) when multiple weapons equipped
- Smooth lerp transitions for meter changes (8 units/second)
- Fatigue visualization: pulsing orange->red when stamina negative (2 Hz)
- Energy flash: flickering white overlay when throw fails due to low energy (8 Hz, 0.5s)

```lua
local widget = projectile_selector.create({ x = 8, y = 8, alpha = 0.7 })
widget:update(dt, player)  -- Lerp meter values, check energy_flash_requested
widget:draw(player)        -- Render widget with flash overlay
widget:flash_energy()      -- Manually trigger energy bar flash
```

## Secondary Bar Widget (`ui/secondary_bar.lua`)

- Bottom HUD widget showing all equipped secondary items (abilities)
- Displays 1-4 secondary abilities in a horizontal bar with end caps
- Selection highlight shows currently active secondary (via `player.active_secondary`)
- Shows ability control icon on active secondary slot
- Shows "Swap:" hint with control icon when multiple secondaries equipped
- Position calculated dynamically: 8px margin after resource meters, 1px from HUD top

```lua
local widget = secondary_bar.create()
widget:update(dt, player)  -- No-op (prepared for future animation)
widget:draw(player)        -- Renders bar with equipped secondaries
```

**Key Features:**
- Uses `weapon_sync.get_equipped_secondaries()` to fetch all equipped secondaries
- Shows item icons from `unique_item_registry` (static_sprite or first frame of animated_sprite)
- Scales with `config.ui.SCALE` (layout constants in 1x scale)
- X position auto-calculated based on max(health, stamina, energy) meter width
- Only renders when at least one secondary is equipped
- Charge display for charge-based secondaries:
  - Grey-out (30% alpha) when all charges depleted
  - Charge count digit overlay (white when available, red when depleted)
  - Clockwise red recharge progress outline while recharging
  - Uses `weapon_sync.get_charge_info()` for charge state

## Boss Health Bar (`ui/boss_health_bar.lua`)

- Top-center HUD widget for boss encounters
- Sprite-based frame with red health fill underneath
- Intro animation: health bar fills from 0 to full over ~0.7s
- Title/subtitle text fades in centered, then fades out after 2.5s
- Smooth health drain animation (8 units/second) with faded "drain" portion

```lua
boss_health_bar.set_coordinator(coordinator)  -- Set active boss coordinator
boss_health_bar.get_coordinator()             -- Get current coordinator
boss_health_bar.update(dt)                    -- Update fade, health animation, text timer
boss_health_bar.draw()                        -- Render health bar and text
boss_health_bar.reset()                       -- Clear state on level cleanup
```

**Coordinator Interface:**
The coordinator must implement:
- `is_active()` - Returns true when encounter is in progress
- `get_health_percent()` - Returns 0-1 for bar fill
- `get_boss_name()` - Returns title string
- `get_boss_subtitle()` - Returns subtitle string

**Integration (main.lua):**
```lua
local boss_coordinator = require("Enemies/Bosses/{boss}/coordinator")
boss_health_bar.set_coordinator(boss_coordinator)
```

**Visual Features:**
- Orange/gold title with black outline (16pt scaled)
- White subtitle with black outline (10pt scaled)
- Health bar: full opacity for current health, 30% opacity for drain portion
- Fade in/out at 3 alpha/second
- Auto-triggers intro animation when coordinator.is_active() becomes true

## Status Panel (`ui/status_panel.lua`)

- Stats display with level-up functionality for rest screen
- Shows: Level, Exp, Gold, HP/SP/EP, DEF, Recovery, CRIT, Playtime
- Supports stat upgrades at campfires (see [Level Progression](player.md#level-progression-system))
- Integrates inventory grid for equipment management

```lua
local panel = status_panel.create({ x, y, width, height, player })
panel:set_player(player)        -- Update player reference
panel:can_level_up()            -- Check if XP available for upgrade
panel:add_pending_upgrade()     -- Queue upgrade for highlighted stat
panel:confirm_upgrades()        -- Apply pending upgrades
panel:cancel_upgrades()         -- Discard pending upgrades
panel:get_description()         -- Get hovered stat/item description
panel:draw()                    -- Render stats text
```

## Inventory Grid (`ui/inventory_grid.lua`)

- 5x5 grid for displaying collected unique items
- Supports mouse hover and keyboard/gamepad navigation
- Equipment toggling with exclusive types (shield: 1 max, secondary: 4 max)
- Auto-activates secondary when equipped (sets `player.active_secondary`)
- Integrated into status_panel for rest screen display

```lua
local grid = inventory_grid.create({ x, y, items = {}, equipped = {} })
grid:set_items(player.unique_items)       -- Set items array
grid:set_equipped(player.equipped_items)  -- Set equipped set
grid:get_hovered_item()                   -- Get currently selected/hovered item_id
grid:toggle_equipped(item_id)             -- Toggle equip state
grid:update(dt, local_mx, local_my, mouse_active)
grid:draw()
```

**Equipment Types:**
- `shield` - Only one shield equipped at a time
- `weapon` - Multiple weapons can be equipped (cycle with Swap Weapon key)
- `secondary` - Up to 4 secondaries can be equipped (cycle with Swap Ability key, `player.active_secondary` tracks current)
- `accessory` - Any number of accessories can be equipped
- `no_equip` - Cannot be equipped (e.g., keys)
- `usable` - Triggers `on_use_item` callback instead of equipping (e.g., Orb of Teleportation)

## Key Files

- `ui/title_screen.lua` - Title menu with animated cursor
- `ui/slot_screen.lua` - Save slot selection with delete confirmation
- `ui/rest_screen.lua` - Circular viewport rest interface
- `ui/hud.lua` - UI screen aggregator and input/draw coordinator
- `ui/game_over.lua` - Game over screen
- `ui/boss_health_bar.lua` - Boss encounter health bar with intro animation
- `ui/audio_dialog.lua` - Audio settings dialog with volume sliders
- `ui/controls_dialog.lua` - Controls settings dialog with keybind panel
- `ui/control_icon.lua` - Shared control icon rendering utility for HUD widgets
- `ui/projectile_selector.lua` - Resource meters HUD widget (HP/SP/EP)
- `ui/secondary_bar.lua` - Secondary abilities HUD widget (equipped throwables)
- `ui/status_panel.lua` - Player stats panel for rest screen
- `ui/inventory_grid.lua` - 5x5 item grid component for status panel
- `ui/map_panel.lua` - Minimap panel with fog-of-war for rest/pause screen
- `ui/fast_travel_panel.lua` - Fast travel destination picker for rest screen
