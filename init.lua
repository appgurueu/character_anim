local mod = modlib.mod
local namespace = mod.create_namespace()
namespace.quaternion = modlib.quaternion
namespace.conf = mod.configuration()
mod.extend"main"