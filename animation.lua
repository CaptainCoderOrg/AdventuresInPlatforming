local animation = {}

function animation.create(name, frame_count)
    return {
        name = name,
        frame_count = frame_count,
        frame = 0,
        flipped = 1,
    }
end

return animation