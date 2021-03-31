local mod = modlib.mod
local namespace = mod.create_namespace()
local quaternion = setmetatable({}, {__index = namespace})
mod.include_env(mod.get_resource"quaternion.lua", quaternion)
namespace.quaternion = quaternion
namespace.conf = mod.configuration()
namespace.insecure_environment = minetest.request_insecure_environment() or _G
mod.extend"importer"
mod.extend"main"