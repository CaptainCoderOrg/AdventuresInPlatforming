local canvas = require('canvas')
local audio = {}

canvas.assets.add_path("assets/")
audio.title_screen = canvas.assets.load_music("title_screen", "music/title-screen.ogg")
audio.level1 = canvas.assets.load_music("level1", "music/level-1.ogg")

local current_track = nil

local music_group = "music_group"
local music_tracks = { "music_track_1", "music_track_2" }
local main_track = music_tracks[1]
local main_track_volume = 0
local secondary_track = music_tracks[2]
local secondary_track_volume = 0

local initialized = false
local FADE_TIME = 5
local FADE_OUT_TIME = 2

function audio.init()
    if initialized then return end
    canvas.channel_create(music_group, { parent = nil })
    canvas.channel_create(music_tracks[1], { parent = music_group })
    canvas.channel_create(music_tracks[2], { parent = music_group })
    initialized = true
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

return audio