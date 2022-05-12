assert(modlib.version >= 89, "character_anim requires at least version rolling-89 of modlib to function correctly")

character_anim = {}

character_anim.conf = modlib.mod.configuration()

local quaternion = modlib.quaternion
-- TODO deduplicate code: move to modlib (see ghosts mod)
local media_paths = modlib.minetest.media.paths
local models = setmetatable({}, {__index = function(self, filename)
	local _, ext = modlib.file.get_extension(filename)
	if not ext or ext:lower() ~= "b3d" then
		-- Only B3D support currently
		return
	end
	local path = assert(media_paths[filename], filename)
	local stream = io.open(path, "r")
	local model = assert(modlib.b3d.read(stream))
	assert(stream:read(1) == nil, "EOF expected")
	stream:close()
	self[filename] = model
	return model
end})

function character_anim.is_interacting(player)
	local control = player:get_player_control()
	return minetest.check_player_privs(player, "interact") and (control.RMB or control.LMB)
end

local function get_look_horizontal(player)
	return -math.deg(player:get_look_horizontal())
end

local players = {}
character_anim.players = players

function character_anim.set_bone_override(player, bonename, position, rotation)
	local name = player:get_player_name()
	local value = {
		position = position,
		euler_rotation = rotation
	}
	players[name].bone_positions[bonename] = next(value) and value
end

local function nil_default(value, default)
	if value == nil then return default end
	return value
end

-- Forward declaration
local handle_player_animations
-- Raw PlayerRef methods
local set_bone_position, set_animation, set_local_animation
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	players[name] = {
		interaction_time = 0,
		animation_time = 0,
		look_horizontal = get_look_horizontal(player),
		bone_positions = {}
	}
	if not set_bone_position then
		local PlayerRef = getmetatable(player)

		set_bone_position = PlayerRef.set_bone_position
		function PlayerRef:set_bone_position(bonename, position, rotation)
			if self:is_player() then
				character_anim.set_bone_override(self, bonename or "",
					position or {x = 0, y = 0, z = 0},
					rotation or {x = 0, y = 0, z = 0})
			end
			return set_bone_position(self, bonename, position, rotation)
		end

		set_animation = PlayerRef.set_animation
		function PlayerRef:set_animation(frame_range, frame_speed, frame_blend, frame_loop)
			if not self:is_player() then
				return set_animation(self, frame_range, frame_speed, frame_blend, frame_loop)
			end
			local player_animation = players[player:get_player_name()]
			if not player_animation then
				return
			end
			player_animation.animation = {
				nil_default(frame_range, {x = 1, y = 1}),
				nil_default(frame_speed, 15),
				nil_default(frame_blend, 0),
				nil_default(frame_loop, true)
			}
			player_animation.animation_time = 0
			handle_player_animations(0, player)
		end
		local set_animation_frame_speed = PlayerRef.set_animation_frame_speed
		function PlayerRef:set_animation_frame_speed(frame_speed)
			if not self:is_player() then
				return set_animation_frame_speed(self, frame_speed)
			end
			local player_animation = players[player:get_player_name()]
			if not player_animation then
				return
			end
			player_animation.animation[2] = frame_speed
		end

		local get_animation = PlayerRef.get_animation
		function PlayerRef:get_animation()
			if not self:is_player() then
				return get_animation(self)
			end
			local anim = players[self:get_player_name()].animation
			if anim then
				return unpack(anim, 1, 4)
			end
			return get_animation(self)
		end

		set_local_animation = PlayerRef.set_local_animation
		function PlayerRef:set_local_animation(idle, walk, dig, walk_while_dig, frame_speed)
			if not self:is_player() then return set_local_animation(self) end
			frame_speed = frame_speed or 30
			players[self:get_player_name()].local_animation = {idle, walk, dig, walk_while_dig, frame_speed}
		end
		local get_local_animation = PlayerRef.get_local_animation
		function PlayerRef:get_local_animation()
			if not self:is_player() then return get_local_animation(self) end
			local local_anim = players[self:get_player_name()].local_animation
			if local_anim then
				return unpack(local_anim, 1, 5)
			end
			return get_local_animation(self)
		end
	end

	-- Disable animation & local animation
	local no_anim = {x = 0, y = 0}
	set_animation(player, no_anim, 0, 0, false)
	set_local_animation(player, no_anim, no_anim, no_anim, no_anim, 1)
end)

minetest.register_on_leaveplayer(function(player) players[player:get_player_name()] = nil end)

local function clamp(value, range)
	if value > range.max then
		return range.max
	end
	if value < range.min then
		return range.min
	end
	return value
end

local function normalize_angle(angle)
	return ((angle + 180) % 360) - 180
end

local function normalize_rotation(euler_rotation)
	return vector.apply(euler_rotation, normalize_angle)
end

function handle_player_animations(dtime, player)
	local mesh = player:get_properties().mesh
	local model = models[mesh]
	if not model then
		return
	end
	local conf = character_anim.conf.models[mesh] or character_anim.conf.default
	local name = player:get_player_name()
	local player_animation = players[name]
	local anim = player_animation.animation
	if not anim then
		return
	end
	local range, frame_speed, _, frame_loop = unpack(anim, 1, 4)
	local animation_time = player_animation.animation_time
	animation_time = animation_time + dtime
	player_animation.animation_time = animation_time
	local range_min, range_max = range.x + 1, range.y + 1
	local keyframe
	if range_min == range_max then
		keyframe = range_min
	elseif frame_loop then
		keyframe = range_min + ((animation_time * frame_speed) % (range_max - range_min))
	else
		keyframe = math.min(range_max, range_min + animation_time * frame_speed)
	end
	local bones = {}
	for _, props in ipairs(model:get_animated_bone_properties(keyframe, true)) do
		local bone = props.bone_name
		local position, rotation = modlib.vector.to_minetest(props.position), props.rotation
		-- Fix the signs of X and Y to match Minetest
		rotation = {-rotation[1], rotation[2], -rotation[3], rotation[4]}
		local euler_rotation = quaternion.to_euler_rotation(rotation)
		bones[bone] = {position = position, rotation = rotation, euler_rotation = euler_rotation}
	end
	if not (bones.Body and bones.Head and bones.Arm_Right) then
		-- Model is missing some bones, don't animate serverside
		return
	end
	local Body, Head, Arm_Right = bones.Body.euler_rotation, bones.Head.euler_rotation, bones.Arm_Right.euler_rotation
	local look_vertical = -math.deg(player:get_look_vertical())
	Head.x = look_vertical
	local interacting = character_anim.is_interacting(player)
	if interacting then
		local interaction_time = player_animation.interaction_time
		-- Note: +90 instead of +Arm_Right.x because it looks better
		Arm_Right.x = 90 + look_vertical - math.sin(-interaction_time) * conf.arm_right.radius
		Arm_Right.y = Arm_Right.y + math.cos(-interaction_time) * conf.arm_right.radius
		player_animation.interaction_time = interaction_time + dtime * math.rad(conf.arm_right.speed)
	else
		player_animation.interaction_time = 0
	end
	local look_horizontal = get_look_horizontal(player)
	local diff = look_horizontal - player_animation.look_horizontal
	if math.abs(diff) > 180 then
		diff = math.sign(-diff) * 360 + diff
	end
	local moving_diff = math.sign(diff) * math.abs(diff) * math.min(1, dtime / conf.body.turn_speed)
	player_animation.look_horizontal = player_animation.look_horizontal + moving_diff
	if math.abs(moving_diff) < 1e-6 then
		player_animation.look_horizontal = look_horizontal
	end
	local lag_behind = diff - moving_diff
	local attach_parent, _, _, attach_rotation = player:get_attach()
	if attach_parent then
		local parent_rotation = attach_parent:get_rotation()
		if attach_rotation and parent_rotation then
			parent_rotation = vector.apply(parent_rotation, math.deg)
			local total_rotation = normalize_rotation(vector.subtract(attach_rotation, parent_rotation))
			local function rotate_relative(euler_rotation)
				euler_rotation.y = euler_rotation.y + look_horizontal
				local new_rotation = normalize_rotation(vector.subtract(euler_rotation, total_rotation))
				modlib.table.add_all(euler_rotation, new_rotation)
			end

			rotate_relative(Head)
			if interacting then rotate_relative(Arm_Right) end
		end
	elseif not modlib.table.nilget(rawget(_G, "player_api"), "player_attached", name) then
		Body.y = Body.y - lag_behind
		Head.y = Head.y + lag_behind
		if interacting then Arm_Right.y = Arm_Right.y + lag_behind end
	end

	-- HACK assumes that Body is root & parent bone of Head, only takes rotation around X-axis into consideration
	Head.x = normalize_angle(Head.x + Body.x)
	if interacting then Arm_Right.x = normalize_angle(Arm_Right.x - Body.x) end

	Head.x = clamp(Head.x, conf.head.pitch)
	Head.y = clamp(Head.y, conf.head.yaw)
	if math.abs(Head.y) > conf.head.yaw_restriction then
		Head.x = clamp(Head.x, conf.head.yaw_restricted)
	end
	Arm_Right.y = clamp(Arm_Right.y, conf.arm_right.yaw)

	-- Replace animation with serverside bone animation
	for bone, values in pairs(bones) do
		local overridden_values = player_animation.bone_positions[bone]
		overridden_values = overridden_values or {}
		set_bone_position(player, bone,
			overridden_values.position or values.position,
			overridden_values.euler_rotation or values.euler_rotation)
	end
end

minetest.register_globalstep(function(dtime)
	for _, player in pairs(minetest.get_connected_players()) do
		handle_player_animations(dtime, player)
	end
end)