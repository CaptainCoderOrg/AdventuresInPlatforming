local canvas = require('canvas')
local pool = require('audio/pool')
local music = require('audio/music')
local spatial = require('audio/spatial')

canvas.assets.add_path("assets/")

local audio = {}

audio.title_screen = canvas.assets.load_music("title_screen", "music/title-screen.ogg")
audio.level1 = canvas.assets.load_music("level1", "music/level-1.ogg")
audio.rest = canvas.assets.load_music("rest", "music/rest.ogg")

audio.dash = canvas.assets.load_sound("dash", "sfx/dash.ogg")
audio.sound_check = canvas.assets.load_sound("sound_check", "sfx/sound-check.ogg")
audio.spiketrap = canvas.assets.load_sound("spiketrap", "sfx/environment/spiketrap.ogg")

local sfx_group = "sfx_group"
local sfx_ch = { "sfx_1", "sfx_2", "sfx_3", "sfx_4" }
local next_sfx_ch = 1
local sound_check_channel = "sound_check_channel"
local initialized = false

--- Initialize all audio systems
function audio.init()
    if initialized then return end

    music.init()

    canvas.channel_create(sfx_group, { parent = nil })
    for _, ch in ipairs(sfx_ch) do
        canvas.channel_create(ch, { parent = sfx_group })
    end

    pool.init_channels(sfx_group)

    canvas.channel_create(sound_check_channel, { parent = sfx_group })

    spatial.init(sfx_group)

    initialized = true
end

--- Play footstep sound (skips if channel busy)
function audio.play_footstep() pool.all.footstep:play() end
--- Play landing sound (skips if channel busy)
function audio.play_landing_sound() pool.all.landing:play() end
--- Play jump sound (skips if channel busy)
function audio.play_jump_sound() pool.all.jump:play() end
--- Play sword swing sound (skips if channel busy)
function audio.play_sword_sound() pool.all.sword:play() end
--- Play squish hit sound (skips if channel busy)
function audio.play_squish_sound() pool.all.squish:play() end
--- Play solid hit sound (skips if channel busy)
function audio.play_solid_sound() pool.all.solid:play() end
--- Play axe throw sound (skips if channel busy)
function audio.play_axe_throw_sound() pool.all.axe_throw:play() end
--- Play shuriken throw sound (skips if channel busy)
function audio.play_shuriken_throw_sound() pool.all.shuriken_throw:play() end

--- Wall slide uses landing sound for consistent contact feedback
audio.play_wall_slide_start = audio.play_landing_sound
--- Air jump reuses jump sound
audio.play_air_jump_sound = audio.play_jump_sound
--- Wall jump reuses jump sound
audio.play_wall_jump_sound = audio.play_jump_sound

--- Play background music track with crossfade
---@param track table Music asset returned from canvas.assets.load_music()
audio.play_music = music.play
--- Update music crossfade (call each frame)
---@param dt number Delta time in seconds
audio.update = music.update
--- Stop all music playback
audio.stop_music = music.stop
--- Set music group volume
---@param volume number Volume level (0-1)
audio.set_music_volume = music.set_volume

--- Update or stop a spatial sound based on volume
---@param sound_id string The spatial sound identifier
---@param volume number Target volume (0 to stop, >0 to play)
audio.update_spatial_sound = spatial.update
--- Stop all spatial sounds (for level cleanup)
audio.stop_all_spatial = spatial.stop_all
--- Get all registered spatial sound IDs
---@return table Array of sound_id strings
audio.get_spatial_sound_ids = spatial.get_ids

--- Play sound check sample (skips if already playing)
function audio.play_sound_check()
    if canvas.channel_is_playing(sound_check_channel) then return end
    canvas.channel_play(sound_check_channel, audio.sound_check, { volume = 1.0, loop = false })
end

--- Play a sound effect on a rotating SFX channel
---@param sfx any Sound asset to play
---@param volume number|nil Volume level (0-1), defaults to 1.0
function audio.play_sfx(sfx, volume)
    local ch = sfx_ch[next_sfx_ch]
    next_sfx_ch = next_sfx_ch % #sfx_ch + 1
    canvas.channel_play(ch, sfx, { volume = volume or 1.0, loop = false })
end

--- Set SFX group volume
---@param volume number Volume level (0-1)
function audio.set_sfx_volume(volume)
    canvas.channel_set_volume(sfx_group, volume)
end

return audio
