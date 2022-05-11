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
	assert(not stream:read(1))
	stream:close()
	self[filename] = model
	return model
end})

function get_animation_value(animation, keyframe_index, is_rotation)
	local values = animation.values
	assert(keyframe_index >= 1 and keyframe_index <= #values, keyframe_index)
	local ratio = keyframe_index % 1
	if ratio == 0 then
		return values[keyframe_index]
	end
	assert(ratio > 0 and ratio < 1)
	local prev_value, next_value = values[math.floor(keyframe_index)], values[math.ceil(keyframe_index)]
	assert(next_value)
	if is_rotation then
		return quaternion.slerp(prev_value, next_value, ratio)
	end
	return modlib.vector.interpolate(prev_value, next_value, ratio)
end

function is_interacting(player)
	local control = player:get_player_control()
	return minetest.check_player_privs(player, "interact") and (control.RMB or control.LMB)
end

local function get_look_horizontal(player)
	return 180-math.deg(player:get_look_horizontal())
end

players = {}

function set_bone_override(player, bonename, position, rotation)
	local name = player:get_player_name()
	local value = {
		position = position,
		euler_rotation = rotation
	}
	-- TODO consider setting empty overrides to nil
	players[name].bone_positions[bonename] = value
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
				set_bone_override(self, bonename or "", position or {x = 0, y = 0, z = 0}, rotation or {x = 0, y = 0, z = 0})
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
	local conf = conf.models[mesh] or conf.default
	local name = player:get_player_name()
	local player_animation = players[name]
	local anim = player_animation.animation
	if not anim then
		return
	end
	local range, frame_speed, _, frame_loop = unpack(anim, 1, 4)
	assert(range, dump(anim))
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
	local bone_positions = {}
	for _, props in ipairs(model:get_animated_bone_properties(keyframe, true)) do
		local bone = props.bone_name
		local position, rotation = modlib.vector.to_minetest(props.position), props.rotation
		-- Fix the signs of X and Y to match Minetest
		rotation = {-rotation[1], rotation[2], -rotation[3], rotation[4]}
		local euler_rotation = quaternion.to_euler_rotation(rotation)
		bone_positions[bone] = {position = position, rotation = rotation, euler_rotation = euler_rotation}
	end
	local Body, Head, Arm_Right = bone_positions.Body.euler_rotation, bone_positions.Head.euler_rotation, bone_positions.Arm_Right.euler_rotation
	if not (Body and Head and Arm_Right) then
		-- Model is missing some bones, don't animate serverside
		return
	end
	local look_vertical = -math.deg(player:get_look_vertical())
	Head.x = look_vertical
	local interacting = is_interacting(player)
	if interacting then
		local interaction_time = player_animation.interaction_time
		-- note: +90 instead +Arm_Right.x because it looks better
		Arm_Right.x = 90 - look_vertical - math.sin(-interaction_time) * conf.arm_right.radius
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
	-- TODO properly handle eye offset & height vs. actual head position
	if attach_parent then
		local parent_rotation = attach_parent:get_rotation()
		if attach_rotation and parent_rotation then
			parent_rotation = vector.apply(parent_rotation, math.deg)
			local total_rotation = normalize_rotation(vector.subtract(parent_rotation, attach_rotation))
			local function rotate_relative(euler_rotation)
				-- HACK +180
				euler_rotation.y = euler_rotation.y + look_horizontal + 180
				local new_rotation = normalize_rotation(vector.add(euler_rotation, total_rotation))
				modlib.table.add_all(euler_rotation, new_rotation)
			end

			rotate_relative(Head)
			if interacting then rotate_relative(Arm_Right) end
		end
	elseif not player_api.player_attached[name] then
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
	for bone, values in pairs(bone_positions) do
		local overridden_values = player_animation.bone_positions[bone]
		overridden_values = overridden_values or {}
		set_bone_position(player, bone, overridden_values.position or values.position, overridden_values.euler_rotation or values.euler_rotation)
	end
end

minetest.register_globalstep(function(dtime)
	for _, player in pairs(minetest.get_connected_players()) do
		handle_player_animations(dtime, player)
	end
end)