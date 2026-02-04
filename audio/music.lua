local canvas = require('canvas')
local music = {}

local music_group = "music_group"
local music_tracks = { "music_track_1", "music_track_2" }
local main_track = music_tracks[1]
local main_track_volume = 0
local secondary_track = music_tracks[2]
local secondary_track_volume = 0
local current_track = nil

local FADE_TIME = 2
local FADE_OUT_TIME = 2

-- Fade out state
local fading_out = false
local fade_out_duration = 2

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
    fading_out = false  -- Cancel any fade out in progress
    main_track, secondary_track = secondary_track, main_track
    canvas.channel_play(main_track, track, { volume = 0.0, loop = true })
    secondary_track_volume = main_track_volume
    main_track_volume = 0
    current_track = track
end

--- Update music crossfade (call each frame)
---@param dt number Delta time in seconds
function music.update(dt)
    -- Handle fade out (overrides normal crossfade)
    if fading_out then
        if main_track_volume > 0 then
            main_track_volume = math.max(0, main_track_volume - dt / fade_out_duration)
            canvas.channel_set_volume(main_track, main_track_volume)
        end
        if secondary_track_volume > 0 then
            secondary_track_volume = math.max(0, secondary_track_volume - dt / fade_out_duration)
            canvas.channel_set_volume(secondary_track, secondary_track_volume)
        end
        return
    end

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
    fading_out = false
end

--- Fade out all music over the specified duration.
---@param duration number|nil Fade duration in seconds (default: 2)
function music.fade_out(duration)
    fading_out = true
    fade_out_duration = duration or 2
end

--- Check if music has finished fading out.
---@return boolean True if fade out is complete
function music.is_faded_out()
    return fading_out and main_track_volume <= 0 and secondary_track_volume <= 0
end

--- Cancel fade out and restore normal playback.
function music.cancel_fade_out()
    fading_out = false
end

--- Set music group volume
---@param volume number Volume level (0-1)
function music.set_volume(volume)
    canvas.channel_set_volume(music_group, volume)
end

return music
