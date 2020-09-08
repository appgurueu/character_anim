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
        local component_bytes = {
            [5120] = 1,
            [5121] = 1,
            [5122] = 2,
            [5123] = 2,
            [5125] = 4,
            [5126] = 4
        }
        local offset, buffer
        local component_readers = {
            [5120] = function()
                local value = buffer:byte(offset)
                if value >= 128 then
                    value = -value + 127
                end
                offset = offset + 1
                return value
            end,
            [5121] = function()
                return buffer:byte(offset)
            end,
            [5122] = function()
                local value = buffer:byte(offset) * 256 + buffer:byte(offset + 1)
                if value >= 128 * 256 then
                    value = -value + 128 * 256 - 1
                end
                return value
            end,
            [5123] = function()
                return buffer:byte(offset) * 256 + buffer:byte(offset + 1)
            end,
            [5125] = function()
                return ((buffer:byte(offset) * 256 + buffer:byte(offset + 1)) * 256 + buffer:byte(offset + 2)) * 256 + buffer:byte(offset + 3)
            end,
            [5126] = function()
                local byte_1, byte_2, byte_3, byte_4 = buffer:byte(offset), buffer:byte(offset + 1), buffer:byte(offset + 2), buffer:byte(offset + 3)
                local sign = 1
                if byte_1 >= 128 then
                    sign = -1
                    byte_1 = byte_1 - 128
                end
                local exponent = byte_1 * 2 - 127
                if byte_2 >= 128 then
                    exponent = exponent + 1
                    byte_2 = byte_2 - 128
                end
                assert(exponent ~= 256) -- glTF does not allow infinities & NaN
                local fraction = (byte_2 + ((byte_3 + (byte_4 / 256)) / 256)) / 256
                if exponent == 0 then
                    exponent = -126
                else
                    fraction = fraction + 1
                end
                return sign * fraction * math.pow(2, exponent)
                -- TODO math.fround (double vs float), smol precision errors are to be expected
            end
        }

        -- float reader test
        --[[local float_reader = component_readers[5126]
        offset = 1
        -- 0x3f000000
        buffer = string.char(0x3f) .. string.char(0) .. string.char(0) .. string.char(0)
        local value = float_reader()
        assert(value == 0.5, value)]]

        local component_reader = component_readers[accessor.componentType]
        local accessor_type = accessor.type
        local buffer_view = gltf.bufferViews[accessor.bufferView + 1]
        buffer = buffers[buffer_view.buffer + 1]
        offset = buffer_view.byteOffset + 1
        local value_bytes = component_bytes[accessor.componentType] * ({SCALAR = 1, VEC3 = 3, VEC4 = 4})[accessor_type]
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
            offset = offset + value_bytes
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
            local animation = {
                start_time = min_time,
                end_time = max_time,
                keyframes = time,
                values = transform
            }
            local nodename = nodes[node].name
            animations_by_nodename[nodename] = animations_by_nodename[nodename] or {}
            table.insert(animations_by_nodename[nodename], animation)
        end
    end
    -- HACK to remove the unneeded Camera animation
    animations_by_nodename.Camera = nil
    modlib.file.write(modlib.mod.get_resource("player_animations.lua"), minetest.serialize(animations_by_nodename))
    return animations_by_nodename
end

-- example call:
-- bone_data(minetest.get_modpath("this_mod").."/models/model.gltf", {Head = true})