local canvas = require('canvas')
local audio = {}

canvas.assets.add_path("assets/")
audio.title_screen = canvas.assets.load_music("title_screen", "music/title-screen.ogg")
audio.level1 = canvas.assets.load_music("level1", "music/level-1.ogg")
audio.rest = canvas.assets.load_music("rest", "music/rest.ogg")

audio.dash = canvas.assets.load_sound("dash", "sfx/dash.ogg")
audio.sound_check = canvas.assets.load_sound("sound_check", "sfx/sound-check.ogg")
audio.spiketrap = canvas.assets.load_sound("spiketrap", "sfx/environment/spiketrap.ogg")

local REPEAT_SOUND_VOLUME = 0.15

audio.footstep = {}
local footstep_channel = "footsteps_channel"
for i = 0,8 do
    table.insert(audio.footstep, canvas.assets.load_sound(string.format("footstep_%d", i), string.format("sfx/landing/%d.ogg", i)))
end

local jump_channel = "jump_channel"
audio.jump = {}
for i = 0,3 do
    table.insert(audio.jump, canvas.assets.load_sound(string.format("jump_%d", i), string.format("sfx/woosh/%d.ogg", i)))
end

audio.landing = {}
for i = 0,8 do
    table.insert(audio.landing, canvas.assets.load_sound(string.format("landing_%d", i), string.format("sfx/footsteps/%d.ogg", i)))
end

local attack_channel = "attack_channel"
audio.sword = {}
for i = 0,5 do
    table.insert(audio.sword, canvas.assets.load_sound(string.format("sword_%d", i), string.format("sfx/attack/sword_%d.ogg", i)))
end

local sound_check_channel = "sound_check_channel"

-- Environment/spatial sounds channel group
local environment_group = "environment_group"
local spatial_channels = {}  -- sound_id -> channel name
local spatial_sounds = {}    -- sound_id -> sound asset
local spatial_volumes = {}   -- sound_id -> current target volume

-- Register spatial sounds
spatial_sounds["campfire"] = canvas.assets.load_sound("campfire", "sfx/environment/campfire.ogg")

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

    -- Environment/spatial audio group and channels
    canvas.channel_create(environment_group, { parent = sfx_group })
    for sound_id, _ in pairs(spatial_sounds) do
        local channel = "spatial_" .. sound_id
        spatial_channels[sound_id] = channel
        spatial_volumes[sound_id] = 0
        canvas.channel_create(channel, { parent = environment_group })
    end

    initialized = true
end

--- Update or stop a spatial sound based on volume
--- Plays looped sound when volume > 0, stops when volume == 0
---@param sound_id string The spatial sound identifier
---@param volume number Target volume (0 to stop, >0 to play)
function audio.update_spatial_sound(sound_id, volume)
    local channel = spatial_channels[sound_id]
    local sound = spatial_sounds[sound_id]
    if not channel or not sound then return end

    local prev_volume = spatial_volumes[sound_id] or 0

    if volume > 0 then
        -- Start playing if not already
        if not canvas.channel_is_playing(channel) then
            canvas.channel_play(channel, sound, { volume = volume, loop = true })
        else
            -- Update volume
            canvas.channel_set_volume(channel, volume)
        end
    elseif prev_volume > 0 then
        -- Stop if volume dropped to 0
        canvas.channel_stop(channel)
    end

    spatial_volumes[sound_id] = volume
end

--- Stop all spatial sounds (for level cleanup)
function audio.stop_all_spatial()
    for sound_id, channel in pairs(spatial_channels) do
        canvas.channel_stop(channel)
        spatial_volumes[sound_id] = 0
    end
end

--- Get all registered spatial sound IDs
---@return table Array of sound_id strings
function audio.get_spatial_sound_ids()
    local ids = {}
    for sound_id, _ in pairs(spatial_sounds) do
        table.insert(ids, sound_id)
    end
    return ids
end

function audio.play_footstep()
    if canvas.channel_is_playing(footstep_channel) then return end
    local sfx = audio.footstep[math.random(#audio.footstep)]
    canvas.channel_play(footstep_channel, sfx, { volume = REPEAT_SOUND_VOLUME, loop = false })
end


function audio.play_landing_sound()
    if canvas.channel_is_playing(footstep_channel) then return end
    local sfx = audio.landing[math.random(#audio.landing)]
    canvas.channel_play(footstep_channel, sfx, { volume = REPEAT_SOUND_VOLUME, loop = false })
end

audio.play_wall_slide_start = audio.play_landing_sound

local next_jump_sound = 1
function audio.play_jump_sound()
    if canvas.channel_is_playing(jump_channel) then return end
    local sfx = audio.jump[next_jump_sound]
    next_jump_sound = next_jump_sound + 1
    if next_jump_sound > #audio.jump then next_jump_sound = 1 end
    canvas.channel_play(jump_channel, sfx, { volume = REPEAT_SOUND_VOLUME, loop = false })
end

audio.play_air_jump_sound = audio.play_jump_sound
audio.play_wall_jump_sound = audio.play_jump_sound

local next_sword_sound = 1
function audio.play_sword_sound()
    if canvas.channel_is_playing(attack_channel) then return end
    local sfx = audio.sword[next_sword_sound]
    next_sword_sound = next_sword_sound + 1
    if next_sword_sound > #audio.sword then next_sword_sound = 1 end
    canvas.channel_play(attack_channel, sfx, { volume = REPEAT_SOUND_VOLUME, loop = false })
end

--- Play sound check sample (skips if already playing)
function audio.play_sound_check()
    if canvas.channel_is_playing(sound_check_channel) then return end
    canvas.channel_play(sound_check_channel, audio.sound_check, { volume = 1.0, loop = false })
end

function audio.play_sfx(sfx, volume)
    if volume == nil then volume = 1.0 end
    local ch = sfx_ch[next_sfx_ch]
    next_sfx_ch = next_sfx_ch + 1
    if next_sfx_ch > #sfx_ch then
        next_sfx_ch = 1
    end
    canvas.channel_play(ch, sfx, { volume = volume, loop = false })
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
