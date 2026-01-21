local canvas = require('canvas')
local music = {}

local music_group = "music_group"
local music_tracks = { "music_track_1", "music_track_2" }
local main_track = music_tracks[1]
local main_track_volume = 0
local secondary_track = music_tracks[2]
local secondary_track_volume = 0
local current_track = nil

local FADE_TIME = 5
local FADE_OUT_TIME = 2

--- Initialize music channels
function music.init()
    canvas.channel_create(music_group, { parent = nil })
    canvas.channel_create(music_tracks[1], { parent = music_group })
    canvas.channel_create(music_tracks[2], { parent = music_group })
end

--- Play a music track with crossfade
---@param track table Music asset returned from canvas.assets.load_music()
function music.play(track)
    assert(track ~= nil, "Cannot play nil track")
    if current_track == track then return end
    main_track, secondary_track = secondary_track, main_track
    canvas.channel_play(main_track, track, { volume = 0.0, loop = true })
    secondary_track_volume = main_track_volume
    main_track_volume = 0
    current_track = track
end

--- Update music crossfade (call each frame)
---@param dt number Delta time in seconds
function music.update(dt)
    if main_track_volume < 1 then
        main_track_volume = math.min(1, main_track_volume + dt / FADE_TIME)
        canvas.channel_set_volume(main_track, main_track_volume)
    end
    if secondary_track_volume > 0 then
        secondary_track_volume = math.max(0, secondary_track_volume - dt / FADE_OUT_TIME)
        canvas.channel_set_volume(secondary_track, secondary_track_volume)
    end
end

--- Stop all music playback
function music.stop()
    canvas.stop_music()
end

--- Set music group volume
---@param volume number Volume level (0-1)
function music.set_volume(volume)
    canvas.channel_set_volume(music_group, volume)
end

return music
