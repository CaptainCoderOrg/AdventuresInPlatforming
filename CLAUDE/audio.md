# Audio System

<!-- QUICK REFERENCE
- Main entry: audio/init.lua
- Sound pools: audio/pool.lua (round-robin, random modes)
- Music: audio.play_music(track) with crossfade
- Spatial: audio.update_spatial_sound(id, volume)
- Death sounds: audio.play_death_sound(enemy_key)
- Proximity: proximity_audio.register(emitter, config)
-->

## Architecture Overview

Modular audio architecture in `audio/` folder with sound pools, spatial audio, and music crossfade.

- Modular folder structure replacing monolithic `audio.lua`
- Sound pool system with round-robin and random playback modes
- Spatial audio for looping ambient sounds (campfire, etc.)
- Dual-channel music crossfade system

## Sound Pools (`audio/pool.lua`)

Factory pattern for reusable sound management:
```lua
pool.create({
    channel = "footsteps_channel",
    path_format = "sfx/landing/%d.ogg",
    name_format = "footstep_%d",
    start_index = 0, end_index = 8,
    mode = "random",  -- or "round_robin" (default)
    volume = pool.BASE_VOLUME
})
```
- Skips playback if channel already playing (prevents overlap)
- Volume constants: `BASE_VOLUME = 0.15`, `HIT_VOLUME = 0.1725`

## Music System (`audio/music.lua`)

- Dual-channel crossfade (5s fade-in, 2s fade-out)
- Smooth transitions between tracks
- `audio.play_music(track)` initiates crossfade

## Spatial Audio (`audio/spatial.lua`)

- Looping ambient sounds with dynamic volume
- `audio.update_spatial_sound(sound_id, volume)` - 0 stops, >0 plays
- Currently supports: "campfire", "spear_trap"

## Door Sounds

- `audio.locked_door` - Played when player tries to open locked door without key
- `audio.unlock_door` - Played when door unlocks (key used or group action)

## Death Sounds (`audio/death.lua`)

- Per-enemy-type death sound pools
- `audio.play_death_sound(key)` - falls back to default if key not found
- Supports: "ratto", "spike_slug", default (squish)

### Music Tracks

Loaded via `canvas.assets.load_music()`:
- `audio.level1` - Main level music (`music/level-1.ogg`)
- `audio.title_screen` - Title screen music (`music/title-screen.ogg`)
- `audio.rest` - Rest screen / campfire music (`music/rest.ogg`)
- `audio.gnomo_boss` - Gnomo boss encounter music (`music/gnomo-boss.ogg`)
- `audio.credits` - Credits screen music (`music/credits.ogg`)

## Key Methods

```lua
audio.init()                        -- Initialize all audio systems
audio.play_music(track)             -- Crossfade to music track
audio.update(dt)                    -- Update crossfade (call each frame)
audio.play_footstep()               -- Sound pool playback
audio.play_sword_sound()            -- Attack sound
audio.play_death_sound(key)         -- Enemy death sound
audio.update_spatial_sound(id, vol) -- Ambient volume control
audio.set_music_volume(volume)      -- Music group volume (0-1)
audio.set_sfx_volume(volume)        -- SFX group volume (0-1)
```

## Proximity Audio System

Distance-based volume control for ambient sound emitters using HC spatial hashing.

### Architecture

- HC world with 200px cell size for audio radii (3-5 tiles typical)
- Registration-based emitter system
- Per-frame cache for efficient queries
- Inner/outer radius with configurable falloff curves

### Falloff Functions (`proximity_audio/falloff.lua`)

- `linear` - Volume decreases linearly with distance
- `smooth` - Cosine curve for smoother boundary transitions
- `exponential` - Realistic sound attenuation

### Registration

```lua
proximity_audio.register(emitter, {
    sound_id = "campfire",     -- Matches audio/spatial.lua
    radius = 4,                -- Outer radius in tiles (silence beyond)
    inner_radius = 0.5,        -- Inner radius in tiles (full volume within)
    max_volume = 1.0,          -- Volume at inner radius
    falloff = "smooth"         -- Falloff curve type
})
```

### Key Methods

```lua
proximity_audio.register(emitter, config)  -- Add sound emitter
proximity_audio.remove(emitter)            -- Remove emitter
proximity_audio.invalidate_cache()         -- Call at frame start
proximity_audio.get_cached(x, y)           -- Query nearby emitters (cached)
proximity_audio.query(x, y)                -- Direct query (uncached)
proximity_audio.is_in_range(x, y, emitter) -- Check specific emitter
proximity_audio.clear()                    -- Level cleanup
```

### Query Result

Returns array of `{emitter, distance, volume, config}` for all in-range emitters.

## Key Files

- `audio/init.lua` - Main audio system with pool integration
- `audio/pool.lua` - Sound pool factory (round-robin, random modes)
- `audio/spatial.lua` - Spatial/ambient sound manager (looping sounds)
- `audio/music.lua` - Dual-channel music crossfade
- `audio/death.lua` - Enemy-specific death sounds
- `proximity_audio/init.lua` - Distance-based audio volume system
- `proximity_audio/falloff.lua` - Falloff curve functions (linear, smooth, exponential)
- `proximity_audio/state.lua` - HC world and emitter state
