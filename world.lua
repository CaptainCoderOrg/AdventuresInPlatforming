local bump = require('bump')
local config = require('config')
local sprites = require('sprites')
local world = {}


world.grid = bump.newWorld(50)

function world.add_collider(obj)
    world.grid:add(obj, obj.x + obj.box.x, obj.y + obj.box.y, obj.box.w, obj.box.h)
end

function world.move(obj)
    local actualX, actualY, cols, len = world.grid:move(obj, obj.x + obj.box.x, obj.y + obj.box.y)
    obj.x = actualX - obj.box.x
    obj.y = actualY - obj.box.y
    return cols
end

return world