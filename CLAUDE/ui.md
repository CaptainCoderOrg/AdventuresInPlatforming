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

1. Audio/Controls/Settings dialogs
2. Pickup dialogue
3. Dialogue screen
4. Shop screen
5. Upgrade screen
6. Pause toggle (ESC/START)
7. Slot screen
8. Title screen
9. Game over / Rest screen

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
- Menu navigation with sub-panels: Status, Map, Journal, Fast Travel, Controls, Audio, Continue, Return to Title
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

## Journal Panel (`ui/journal_panel.lua`)

- Quest tracking panel shown in the rest/pause screen info area
- Displays journal entries grouped by hierarchy (parent-child) with active entries first, then complete
- Supports collapsible entry groups with expand/collapse icons
- Unread indicator: golden `*` on entries not yet viewed
- Description of selected entry shown in rest dialogue

```lua
journal_panel.show(journal_data, journal_read)  -- Open with player journal tables
journal_panel.hide()                             -- Close panel
journal_panel.is_active()                        -- Check if open
journal_panel.input()                            -- Returns {action = "back"} or nil
journal_panel.update(dt, local_mx, local_my, mouse_active)  -- Mouse hover
journal_panel.handle_click()                     -- Mouse click (toggle collapse)
journal_panel.draw(x, y, width, height)          -- Render in info panel area
journal_panel.get_selected_description()         -- Get selected entry description
journal_panel.has_unread(data, read_data)         -- Static: check for unread entries
```

## Journal Toast (`ui/journal_toast.lua`)

- Passive overlay notification when new journal entries are added
- Shows "New Journal Entry" with entry title in bottom-right corner
- Queue system for sequential display of multiple entries
- Pauses timer when overlay screens are active (dialogue, shop, rest, etc.)

```lua
journal_toast.push(entry_id)       -- Add entry to display queue
journal_toast.update(dt, paused)   -- Advance state machine
journal_toast.draw()               -- Render toast notification
```

**State machine:** `HIDDEN` -> `FADING_IN` (0.3s) -> `VISIBLE` (2.5s) -> `FADING_OUT` (0.5s) -> `HIDDEN`

## Upgrade Screen (`ui/upgrade_screen.lua`)

- Split-screen overlay for equipment upgrades at Zabarbra's shop
- Map view in top area, 9-slice dialogue box in bottom area
- Paginated item list (4 items per page) with left/right page navigation
- Typewriter text reveal for NPC messages (purchase results, errors)
- Mouse hover/click support with keyboard/gamepad navigation
- Camera shifts to show player in map view (same formula as dialogue/shop screens)

```lua
upgrade_screen.start(player, camera, restore_camera_y)  -- Open (3rd arg skips fade-in for overlay chaining)
upgrade_screen.is_active()                               -- Check if visible or transitioning
upgrade_screen.input()                                   -- Handle navigation and purchase
upgrade_screen.update(dt)                                -- Update state machine, typewriter, mouse
upgrade_screen.draw()                                    -- Render overlay
upgrade_screen.get_camera_offset_y()                     -- World render Y offset (0 when hidden)
```

**States:** `HIDDEN`, `FADING_IN`, `OPEN`, `FADING_OUT`

**Integration:** Started from witch NPC's `on_close` callback. Dialogue sets `open_upgrades` flag; witch NPC checks/clears it and calls `upgrade_screen.start()`. Uses `upgrade/registry.lua` for item lists, `upgrade/transactions.lua` for purchase validation/execution.

## Credits Screen (`ui/credits_screen.lua`)

- Full scrolling credits with multi-phase presentation
- Phases: fade to black → title hold → scroll to typewriter text → typewriter effect → scroll credits → hold end → fade out
- Animated enemy sprites along sides during scroll
- Accessible from title screen menu and rest/pause menu

```lua
credits_screen.init()              -- Initialize decoration sprite animations
credits_screen.show()              -- Show with fade-in
credits_screen.hide()              -- Hide with fade-out
credits_screen.is_active()         -- Check if blocking game input
credits_screen.set_on_close(fn)    -- Set callback for when screen closes
credits_screen.input()             -- Process input (skip/advance)
credits_screen.update(dt)          -- Update state machine, scroll, typewriter
credits_screen.draw()              -- Render credits
```

**Integration:** `hud.show_credits_screen()` triggers display. `hud.set_credits_close_callback(fn)` sets the close callback (e.g., return to title).

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

- Bottom HUD widget showing 6 fixed ability slots in a horizontal bar with end caps
- Each slot shows the assigned ability icon and per-slot keybind label via `control_icon`
- Empty slots rendered at 30% alpha
- Always renders (even with no abilities assigned)
- Position calculated dynamically: 8px margin after resource meters, 1px from HUD top

```lua
local widget = secondary_bar.create()
widget:update(dt, player)  -- No-op (prepared for future animation)
widget:draw(player)        -- Renders bar with 6 ability slots
```

**Key Features:**
- Reads directly from `player.ability_slots[1..6]` to display 6 fixed slots
- Shows item icons from `unique_item_registry` (static_sprite or first frame of animated_sprite)
- Scales with `config.ui.SCALE` (layout constants in 1x scale)
- Renders 6 fixed slots (auto-extends via `controls.ABILITY_SLOT_COUNT`)
- X position auto-calculated based on max(health, stamina, energy) meter width
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

- 5x3 grid for displaying collected unique items
- Items assigned to ability slots are excluded from the grid display
- Supports mouse hover and keyboard/gamepad navigation
- Equipment toggling with exclusive types (shield: 1 max)
- Secondary items delegate to ability slot assignment flow via `on_equip_secondary` callback
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
- `weapon` - Multiple weapons can be equipped (cycle with Swap Weapon key)
- `secondary` - Assigned to ability slots (1-6) via status_panel assignment flow (dash, shield, throwables, healing)
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
- `ui/secondary_bar.lua` - Secondary abilities HUD widget (6 fixed ability slots)
- `ui/status_panel.lua` - Player stats panel for rest screen
- `ui/ability_slots.lua` - Ability slot assignment component for status panel
- `ui/inventory_grid.lua` - 5x3 item grid component for status panel
- `ui/map_panel.lua` - Minimap panel with fog-of-war for rest/pause screen
- `ui/fast_travel_panel.lua` - Fast travel destination picker for rest screen
- `ui/journal_panel.lua` - Quest journal panel with hierarchical entries and unread indicators
- `ui/journal_toast.lua` - Toast notification for new journal entries
- `ui/credits_screen.lua` - Scrolling credits with typewriter effect and animated sprites
