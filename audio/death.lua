local canvas = require('canvas')
local pool = require('audio/pool')

local death = {}

local CHANNEL = "death_channel"

--- Enemy death sound pools indexed by enemy type key.
--- Falls back to 'default' if key not found.
death.pools = {
    default = pool.create({
        channel = CHANNEL,
        sounds = { canvas.assets.load_sound("death_squish", "sfx/death/squish.ogg") },
        volume = pool.HIT_VOLUME
    }),
    ratto = pool.create({
        channel = CHANNEL,
        path_format = "sfx/death/ratto_%02d.ogg",
        name_format = "death_ratto_%02d",
        start_index = 0, end_index = 0,
        volume = pool.HIT_VOLUME
    }),
    spike_slug = pool.create({
        channel = CHANNEL,
        path_format = "sfx/death/spike_slug_%02d.ogg",
        name_format = "death_spike_slug_%02d",
        start_index = 0, end_index = 2,
        volume = pool.HIT_VOLUME,
        mode = "random"
    }),
}

--- Initialize death sound channel under the given parent
---@param parent string Parent channel name
function death.init(parent)
    canvas.channel_create(CHANNEL, { parent = parent })
end

--- Play death sound for the given enemy type key
---@param key string|nil Enemy death sound key (nil uses default)
function death.play(key)
    local sound_pool = death.pools[key] or death.pools.default
    sound_pool:play()
end

return death
