local bump = require('bump')
local world = {}

world.grid = bump.newWorld(50)

local STEP_THRESHOLD = 0.1
local STEP_OFFSET = 0.01

-- Custom response: slide with step-over for seams
local function slideWithStep(bumpWorld, col, x, y, w, h, goalX, goalY, filter)
    goalX = goalX or x
    goalY = goalY or y

    local tch = col.touch
    local move = col.move
    local normal = col.normal
    local other = col.otherRect

    -- Standard slide: lock axis based on collision normal
    if move.x ~= 0 or move.y ~= 0 then
        if normal.x ~= 0 then
            goalX = tch.x
        else
            goalY = tch.y
        end
    end

    local stepX, stepY = tch.x, tch.y

    -- Horizontal collision (hit wall on left/right)
    if normal.x ~= 0 then
        local lipBottom = (tch.y + h) - other.y
        local lipTop = (other.y + other.h) - tch.y
        local lipRight = (tch.x + w) - other.x
        local lipLeft = (other.x + other.w) - tch.x

        if lipRight >= 0 and lipRight < STEP_THRESHOLD then
            local offset = lipRight + STEP_OFFSET
            stepX = tch.x - offset
            goalX = goalX - offset
        elseif lipLeft >= 0 and lipLeft < STEP_THRESHOLD then
            local offset = lipLeft + STEP_OFFSET
            stepX = tch.x + offset
            goalX = goalX + offset
        elseif lipBottom >= 0 and lipBottom < STEP_THRESHOLD then
            local offset = lipBottom + STEP_OFFSET
            stepY = tch.y - offset
            goalY = goalY - offset
        elseif lipTop >= 0 and lipTop < STEP_THRESHOLD then
            local offset = lipTop + STEP_OFFSET
            stepY = tch.y + offset
            goalY = goalY + offset
        end
    end

    -- Vertical collision (hit floor/ceiling)
    if normal.y ~= 0 then
        local lipRight = (tch.x + w) - other.x
        local lipLeft = (other.x + other.w) - tch.x
        local lipBottom = (tch.y + h) - other.y
        local lipTop = (other.y + other.h) - tch.y

        if lipRight >= 0 and lipRight < STEP_THRESHOLD then
            local offset = lipRight + STEP_OFFSET
            stepX = tch.x - offset
            goalX = goalX - offset
        elseif lipLeft >= 0 and lipLeft < STEP_THRESHOLD then
            local offset = lipLeft + STEP_OFFSET
            stepX = tch.x + offset
            goalX = goalX + offset
        elseif lipBottom >= 0 and lipBottom < STEP_THRESHOLD then
            local offset = lipBottom + STEP_OFFSET
            stepY = tch.y - offset
            goalY = goalY - offset
        elseif lipTop >= 0 and lipTop < STEP_THRESHOLD then
            local offset = lipTop + STEP_OFFSET
            stepY = tch.y + offset
            goalY = goalY + offset
        end
    end

    local cols, len = bumpWorld:project(col.item, stepX, stepY, w, h, goalX, goalY, filter)
    return goalX, goalY, cols, len
end

world.grid:addResponse('slideWithStep', slideWithStep)

function world.add_collider(obj)
    world.grid:add(obj, obj.x + obj.box.x, obj.y + obj.box.y, obj.box.w, obj.box.h)
end

local function seamFilter(item, other)
    return 'slideWithStep'
end

function world.move(obj)
    local actualX, actualY, cols, len = world.grid:move(
        obj,
        obj.x + obj.box.x,
        obj.y + obj.box.y,
        seamFilter
    )
    obj.x = actualX - obj.box.x
    obj.y = actualY - obj.box.y
    return cols
end

function world.remove_collider(obj)
    world.grid:remove(obj)
end

return world
