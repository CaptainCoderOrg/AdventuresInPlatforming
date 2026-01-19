--- Persistent storage for game settings (volumes and control bindings)
local localstorage = require("APIS/localstorage")
local json = require("APIS/json")

local settings_storage = {}

-- Storage keys
local STORAGE_PREFIX = "platformer_"
local VOLUMES_KEY = "volumes"
local KEYBOARD_KEY = "keyboard_bindings"
local GAMEPAD_KEY = "gamepad_bindings"

-- Default volume values
local DEFAULT_VOLUMES = {
    master = 0.75,
    music = 0.20,
    sfx = 0.60,
}

--- Initialize storage with prefix
---@return nil
function settings_storage.init()
    localstorage.set_prefix(STORAGE_PREFIX)
end

--- Save volume settings to localStorage
---@param volumes table {master, music, sfx} values 0-1
---@return boolean success
function settings_storage.save_volumes(volumes)
    local data = {
        master = volumes.master,
        music = volumes.music,
        sfx = volumes.sfx,
    }
    local json_str = json.encode(data)
    local success, err = localstorage.set_item(VOLUMES_KEY, json_str)
    if not success then
        print("[settings_storage] Failed to save volumes: " .. (err or "unknown error"))
    end
    return success
end

--- Load volume settings from localStorage
---@return table volumes {master, music, sfx} or defaults if not found
function settings_storage.load_volumes()
    local json_str = localstorage.get_item(VOLUMES_KEY)
    local data

    if json_str then
        local success, parsed = pcall(json.decode, json_str)
        if success and type(parsed) == "table" then
            data = parsed
        else
            print("[settings_storage] Failed to parse volumes, using defaults")
        end
    end

    data = data or {}
    return {
        master = type(data.master) == "number" and data.master or DEFAULT_VOLUMES.master,
        music = type(data.music) == "number" and data.music or DEFAULT_VOLUMES.music,
        sfx = type(data.sfx) == "number" and data.sfx or DEFAULT_VOLUMES.sfx,
    }
end

--- Save control bindings for a scheme to localStorage
---@param scheme string "keyboard" or "gamepad"
---@param bindings table action_id -> code mapping
---@return boolean success
function settings_storage.save_bindings(scheme, bindings)
    local key = scheme == "keyboard" and KEYBOARD_KEY or GAMEPAD_KEY
    local json_str = json.encode(bindings)
    local success, err = localstorage.set_item(key, json_str)
    if not success then
        print("[settings_storage] Failed to save " .. scheme .. " bindings: " .. (err or "unknown error"))
    end
    return success
end

--- Load control bindings for a scheme from localStorage
---@param scheme string "keyboard" or "gamepad"
---@return table|nil bindings action_id -> code mapping, or nil if not found
function settings_storage.load_bindings(scheme)
    local key = scheme == "keyboard" and KEYBOARD_KEY or GAMEPAD_KEY
    local json_str = localstorage.get_item(key)
    if not json_str then
        return nil
    end

    local success, data = pcall(json.decode, json_str)
    if not success or type(data) ~= "table" then
        print("[settings_storage] Failed to parse " .. scheme .. " bindings")
        return nil
    end

    return data
end

--- Save all settings (volumes and bindings)
---@param volumes table {master, music, sfx}
---@param keyboard_bindings table action_id -> code
---@param gamepad_bindings table action_id -> code
---@return nil
function settings_storage.save_all(volumes, keyboard_bindings, gamepad_bindings)
    settings_storage.save_volumes(volumes)
    settings_storage.save_bindings("keyboard", keyboard_bindings)
    settings_storage.save_bindings("gamepad", gamepad_bindings)
end

return settings_storage
