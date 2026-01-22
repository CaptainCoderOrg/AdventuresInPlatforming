local canvas = require('canvas')
local spatial = {}

local environment_group = "environment_group"
local channels = {}   -- sound_id -> channel name
local sounds = {}     -- sound_id -> sound asset
local volumes = {}    -- sound_id -> current target volume
local ids_cache = nil -- Cached array of sound IDs (built once at init)

sounds["campfire"] = canvas.assets.load_sound("campfire", "sfx/environment/campfire.ogg")

--- Initialize spatial audio channels
---@param parent string Parent channel name
---@return nil
function spatial.init(parent)
    canvas.channel_create(environment_group, { parent = parent })
    -- Build cached IDs array once at init time
    ids_cache = {}
    for sound_id, _ in pairs(sounds) do
        local channel = "spatial_" .. sound_id
        channels[sound_id] = channel
        volumes[sound_id] = 0
        canvas.channel_create(channel, { parent = environment_group })
        table.insert(ids_cache, sound_id)
    end
end

--- Update or stop a spatial sound based on volume
--- Plays looped sound when volume > 0, stops when volume == 0
---@param sound_id string The spatial sound identifier
---@param volume number Target volume (0 to stop, >0 to play)
---@return nil
function spatial.update(sound_id, volume)
    local channel = channels[sound_id]
    local sound = sounds[sound_id]
    if not channel or not sound then return end

    local prev_volume = volumes[sound_id] or 0
    volumes[sound_id] = volume

    if volume == 0 then
        if prev_volume > 0 then
            canvas.channel_stop(channel)
        end
        return
    end

    if not canvas.channel_is_playing(channel) then
        canvas.channel_play(channel, sound, { volume = volume, loop = true })
    else
        canvas.channel_set_volume(channel, volume)
    end
end

--- Stop all spatial sounds (for level cleanup)
---@return nil
function spatial.stop_all()
    for sound_id, channel in pairs(channels) do
        canvas.channel_stop(channel)
        volumes[sound_id] = 0
    end
end

--- Get all registered spatial sound IDs (cached at init time)
---@return table Array of sound_id strings
function spatial.get_ids()
    return ids_cache or {}
end

return spatial
