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
- Menu navigation with sub-panels: Status, Audio, Controls, Continue, Return to Title
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

**Navigation Modes:** `MENU` (main buttons), `SETTINGS` (audio/controls panels), `CONFIRM` (return to title dialog)

**Extended States:** `HIDDEN` -> `FADING_IN` -> `OPEN` -> `FADING_OUT` -> `RELOADING` -> `FADING_BACK_IN` -> `HIDDEN`

### Visual Effects (rest mode)

- Circular clipping with `evenodd` fill rule
- Radial gradient vignette
- Sine wave pulse (2 Hz, +/-8% radius variation)
- Glow ring with orange/yellow gradient

## Audio Dialog (`ui/audio_dialog.lua`)

- Standalone dialog for volume settings (Master, Music, SFX sliders)
- Accessible from title screen "Audio" option
- Hold-to-repeat slider adjustment

## Controls Dialog (`ui/controls_dialog.lua`)

- Standalone dialog for keybind settings
- Accessible from title screen "Controls" option
- Uses keybind_panel for two-column layout

## Projectile Selector Widget (`ui/projectile_selector.lua`)

- Bottom-left HUD widget showing current throwable and resource meters
- Three horizontal meters: HP (red), SP (green/orange), EP (blue)
- Smooth lerp transitions for meter changes (8 units/second)
- Fatigue visualization: pulsing orange->red when stamina negative (2 Hz)
- Energy flash: flickering white overlay when throw fails due to low energy (8 Hz, 0.5s)

```lua
local widget = projectile_selector.create({ x = 8, y = 8, alpha = 0.7 })
widget:update(dt, player)  -- Lerp meter values, check energy_flash_requested
widget:draw(player)        -- Render widget with flash overlay
widget:flash_energy()      -- Manually trigger energy bar flash
```

## Status Panel (`ui/status_panel.lua`)

- Stats display with level-up functionality for rest screen
- Shows: Level, Exp, Next Level, Gold, HP/SP/EP, DEF, Recovery, CRIT, Playtime
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
- Equipment toggling with exclusive types (only one shield/weapon/secondary at a time)
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
- `weapon` - Only one weapon equipped at a time
- `secondary` - Only one secondary (throwable) equipped at a time
- `accessory` - Any number of accessories can be equipped
- `no_equip` - Cannot be equipped (e.g., keys)

## Key Files

- `ui/title_screen.lua` - Title menu with animated cursor
- `ui/slot_screen.lua` - Save slot selection with delete confirmation
- `ui/rest_screen.lua` - Circular viewport rest interface
- `ui/hud.lua` - UI screen aggregator and input/draw coordinator
- `ui/game_over.lua` - Game over screen
- `ui/audio_dialog.lua` - Audio settings dialog with volume sliders
- `ui/controls_dialog.lua` - Controls settings dialog with keybind panel
- `ui/projectile_selector.lua` - Resource meters HUD widget (HP/SP/EP)
- `ui/status_panel.lua` - Player stats panel for rest screen
- `ui/inventory_grid.lua` - 5x5 item grid component for status panel
