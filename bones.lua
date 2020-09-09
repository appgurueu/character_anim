local BinaryStream = require("binarystream")

-- helper function
local function quaternion_to_rotation(q)
    local rotation = {}

    local sinr_cosp = 2 * (q[4] * q[1] + q[2] * q[3])
    local cosr_cosp = 1 - 2 * (q[1] * q[1] + q[2] * q[2])
    rotation.x = math.atan2(sinr_cosp, cosr_cosp)

    local sinp = 2 * (q[4] * q[2] - q[3] * q[1])
    if sinp <= -1 then
        rotation.y = -math.pi/2
    elseif sinp >= 1 then
        rotation.y = math.pi/2
    else
        rotation.y = math.asin(sinp)
    end

    local siny_cosp = 2 * (q[4] * q[3] + q[1] * q[2])
    local cosy_cosp = 1 - 2 * (q[2] * q[2] + q[3] * q[3])
    rotation.z = math.atan2(siny_cosp, cosy_cosp)
end

-- call with glTF path & set of bones {bonename = true}
function bone_data(path, bones)
    local file = io.open(path, "r")
    local nodes = minetest.parse_json(file:read("*a")).nodes
    for _, node in ipairs(nodes) do
        if bones[node.name] then
            bones[node.name] = {
                position = vector.new(unpack(node.translation)),
                rotation = (node.rotation and quaternion_to_rotation(node.rotation)) or {x=0,y=0,z=0}
            }
        end
    end
end

local data_uri_start = "data:application/octet-stream;base64,"
function read_animation(path)
    local gltf = minetest.parse_json(modlib.file.read(path))
    local buffers = {}
    for index, buffer in ipairs(gltf.buffers) do
        buffer = buffer.uri
        assert(modlib.text.starts_with(buffer, data_uri_start))
        buffers[index] = minetest.decode_base64(buffer:sub((data_uri_start):len()+1))
    end
    local accessors = gltf.accessors
    local function read_accessor(accessor)
        local buffer_view = gltf.bufferViews[accessor.bufferView + 1]
        buffer = buffers[buffer_view.buffer + 1]
        local binary_stream = BinaryStream(buffer, buffer:len())
        local component_readers = {
            [5120] = "readS8",
            [5121] = "readU8",
            [5122] = "readS16",
            [5123] = "readU16",
            [5125] = "readU32",
            [5126] = "readF32"
        }
        for key, value in pairs(component_readers) do
            local reader = binary_stream[value]
            component_readers[key] = function()
                return reader(binary_stream)
            end
        end
        local accessor_type = accessor.type
        local component_reader = component_readers[accessor.componentType]
        binary_stream:skip(buffer_view.byteOffset)
        local values = {}
        for index = 1, accessor.count do
            if accessor_type == "SCALAR" then
                values[index] = component_reader()
            elseif accessor_type == "VEC3" or accessor_type == "VEC4" then
                local vector = {}
                vector.x = component_reader()
                vector.y = component_reader()
                vector.z = component_reader()
                if accessor_type == "VEC4" then
                    vector.w = component_reader()
                end
                values[index] = vector
            end
        end
        return values
    end
    local nodes = gltf.nodes
    local animation = gltf.animations[1]
    local channels, samplers = animation.channels, animation.samplers
    local animations_by_nodename = {}
    for _, channel in ipairs(channels) do
        local path, node, sampler = channel.target.path, channel.target.node, samplers[channel.sampler + 1]
        assert(sampler.interpolation == "LINEAR")
        if path == "translation" or path == "rotation" then
            local time_accessor = accessors[sampler.input + 1]
            local time, transform = read_accessor(time_accessor), read_accessor(accessors[sampler.output + 1])
            local min_time, max_time = time_accessor.min and time_accessor.min[1] or modlib.table.min(time), time_accessor.max and time_accessor.max[1] or modlib.table.max(time)
            local nodename = nodes[node].name
            animations_by_nodename[nodename] = animations_by_nodename[nodename] or {}
            assert(not animations_by_nodename[nodename][path])
            animations_by_nodename[nodename][path] = {
                start_time = min_time,
                end_time = max_time,
                keyframes = time,
                values = transform
            }
        end
    end
    -- HACK to remove the unneeded Camera animation
    animations_by_nodename.Camera = nil
    return animations_by_nodename
end