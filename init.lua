setfenv(1, modlib.mod)
local namespace = create_namespace()
local quaternion = setmetatable({}, {__index = namespace})
include_env(get_resource"quaternion.lua", quaternion)
namespace.quaternion = quaternion
extend"conf"
namespace.insecure_environment = minetest.request_insecure_environment() or _G
extend"importer"
extend"main"