assert(modlib.version >= 89, "character_anim requires at least version rolling-89 of modlib to function correctly")
local mod = modlib.mod
local namespace = mod.create_namespace()
namespace.quaternion = modlib.quaternion
namespace.conf = mod.configuration()
mod.extend"main"