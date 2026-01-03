local canvas = require('canvas')
local audio = {}

canvas.assets.add_path("assets/")
audio.title_screen = canvas.assets.load_music("title_screen", "music/title-screen.ogg")
audio.level1 = canvas.assets.load_music("level1", "music/level-1.ogg")

audio.dash = canvas.assets.load_sound("dash", "sfx/dash.ogg")
audio.sound_check = canvas.assets.load_sound("sound_check", "sfx/sound-check.ogg")
audio.footstep = {}

for i = 0,8 do
    table.insert(audio.footstep, canvas.assets.load_sound(string.format("footstep_%d", i), string.format("sfx/footsteps/%d.ogg", i)))
end
local footstep_channel = "footsteps_channel"
local sound_check_channel = "sound_check_channel"

local current_track = nil

local music_group = "music_group"
local music_tracks = { "music_track_1", "music_track_2" }
local main_track = music_tracks[1]
local main_track_volume = 0
local secondary_track = music_tracks[2]
local secondary_track_volume = 0

local sfx_group = "sfx_group"
local sfx_ch = { "sfx_1", "sfx_2", "sfx_3", "sfx_4" }
local next_sfx_ch = 1

local initialized = false
local FADE_TIME = 5
local FADE_OUT_TIME = 2

function audio.init()
    if initialized then return end
    canvas.channel_create(music_group, { parent = nil })
    canvas.channel_create(music_tracks[1], { parent = music_group })
    canvas.channel_create(music_tracks[2], { parent = music_group })

    canvas.channel_create(sfx_group, {parent = nil})
    for _, ch in pairs(sfx_ch) do
        canvas.channel_create(ch, { parent = sfx_group })
    end

    canvas.channel_create(footstep_channel, { parent = sfx_group })
    canvas.channel_create(sound_check_channel, { parent = sfx_group })

    initialized = true
end

function audio.play_footstep()
    if canvas.channel_is_playing(footstep_channel) then return end
    local sfx = audio.footstep[math.random(#audio.footstep)]
    canvas.channel_play(footstep_channel, sfx, { volume = 0.3, loop = false })
end

--- Play sound check sample (skips if already playing)
function audio.play_sound_check()
    if canvas.channel_is_playing(sound_check_channel) then return end
    canvas.channel_play(sound_check_channel, audio.sound_check, { volume = 1.0, loop = false })
end

function audio.play_sfx(sfx)
    local ch = sfx_ch[next_sfx_ch]
    next_sfx_ch = next_sfx_ch + 1
    if next_sfx_ch > #sfx_ch then
        next_sfx_ch = 1
    end
    canvas.channel_play(ch, sfx, { volume = 1.0, loop = false })
end

function audio.play_music(track)
    assert(track ~= nil, "Cannot play nil track")
    if current_track == track then return end
    main_track, secondary_track = secondary_track, main_track
    canvas.channel_play(main_track, track, { volume = 0.0, loop = true })
    secondary_track_volume = main_track_volume
    main_track_volume = 0
    current_track = track
end

function audio.update()
    local dt = canvas.get_delta()
    if main_track_volume < 1 then
        main_track_volume = math.min(1, main_track_volume + dt/FADE_TIME)
        canvas.channel_set_volume(main_track, main_track_volume)
    end
    if secondary_track_volume > 0 then
        secondary_track_volume = math.max(0, secondary_track_volume - dt/FADE_OUT_TIME)
        canvas.channel_set_volume(secondary_track, secondary_track_volume)
    end
end

function audio.stop_music()
    canvas.stop_music()
end

---@param volume number Volume level (0-1)
function audio.set_music_volume(volume)
    canvas.channel_set_volume(music_group, volume)
end

---@param volume number Volume level (0-1)
function audio.set_sfx_volume(volume)
    canvas.channel_set_volume(sfx_group, volume)
end

return audio
