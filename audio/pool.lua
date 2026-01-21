local canvas = require('canvas')
local pool = {}

local BASE_VOLUME = 0.15
local HIT_VOLUME = BASE_VOLUME * 1.15

--- SoundPool factory for reusable sound pool management
---@param config table Pool configuration
---@return table Pool instance with play() and init_channel() methods
local function create_sound_pool(config)
    local p = {
        sounds = {},
        channel = config.channel,
        next_index = 1,
        volume = config.volume or BASE_VOLUME,
        mode = config.mode or "round_robin",
    }

    if config.sounds then
        p.sounds = config.sounds
    else
        for i = config.start_index, config.end_index do
            table.insert(p.sounds, canvas.assets.load_sound(
                string.format(config.name_format, i),
                string.format(config.path_format, i)))
        end
    end

    function p:play()
        if canvas.channel_is_playing(self.channel) then return end
        local sfx
        if self.mode == "random" then
            sfx = self.sounds[math.random(#self.sounds)]
        else
            sfx = self.sounds[self.next_index]
            self.next_index = self.next_index % #self.sounds + 1
        end
        canvas.channel_play(self.channel, sfx, { volume = self.volume, loop = false })
    end

    function p:init_channel(parent)
        canvas.channel_create(self.channel, { parent = parent })
    end

    return p
end

pool.all = {
    footstep = create_sound_pool({
        channel = "footsteps_channel",
        path_format = "sfx/landing/%d.ogg", name_format = "footstep_%d",
        start_index = 0, end_index = 8, mode = "random"
    }),
    jump = create_sound_pool({
        channel = "jump_channel",
        path_format = "sfx/woosh/%d.ogg", name_format = "jump_%d",
        start_index = 0, end_index = 3
    }),
    landing = create_sound_pool({
        channel = "footsteps_channel",  -- shares channel with footstep
        path_format = "sfx/footsteps/%d.ogg", name_format = "landing_%d",
        start_index = 0, end_index = 8, mode = "random"
    }),
    sword = create_sound_pool({
        channel = "attack_channel",
        path_format = "sfx/attack/sword_%d.ogg", name_format = "sword_%d",
        start_index = 0, end_index = 5
    }),
    squish = create_sound_pool({
        channel = "hit_channel",
        path_format = "sfx/hits/squish/squish_%02d.ogg", name_format = "squish_%02d",
        start_index = 1, end_index = 9, volume = HIT_VOLUME
    }),
    solid = create_sound_pool({
        channel = "solid_hit_channel",
        path_format = "sfx/hits/solid/solid_%02d.ogg", name_format = "solid_%02d",
        start_index = 0, end_index = 8, volume = HIT_VOLUME
    }),
}

pool.all.axe_throw = create_sound_pool({
    channel = "axe_throw_channel",
    sounds = pool.all.sword.sounds
})
pool.all.shuriken_throw = create_sound_pool({
    channel = "shuriken_throw_channel",
    sounds = pool.all.sword.sounds
})

-- Track created channels to avoid duplicates (for shared channels)
local created_channels = {}

--- Initialize all pool channels under the given parent
---@param parent string Parent channel name
function pool.init_channels(parent)
    for _, p in pairs(pool.all) do
        if not created_channels[p.channel] then
            p:init_channel(parent)
            created_channels[p.channel] = true
        end
    end
end

return pool
