extends Node2D

# ============================================================================
# driver_locomotion.gd —— 司机专属动作（双腿独立摆动 + 持枪上半身）
# ----------------------------------------------------------------------------
# 原英文注释机翻：
#   「司机动作：两条独立摆动的贴图双腿，原始持枪上半身。」
#   「缓存几何 + GPU 顶点变形：3 个移动 draw call，不做逐帧 CPU 网格构建。」
#
# 【与 character_locomotion.gd 的区别】
# 通用版（character_locomotion）给 6 个角色共用一套骨架；
# 本文件是给「司机」单独做的高质量版本——
# 腿是两张独立贴图各自摆动，上半身保持原始持枪姿势不动，
# 所以只有 3 个 draw call（双腿各一 + 上半身一），效率与观感都优于通用版。
#
# 【两种持枪姿态】
#   pistol（手枪 M1911）/ machine_gun（机枪 M249）——
#   ART 里存对应上半身贴图，CONFIG 里存各自的髋/膝/踝骨骼锚点与枪口坐标。
#   换枪时切 ART + CONFIG 的键即可。
#
# 【想改的地方】
#   走路步幅/节奏 → HALF_STRIDE / FOOT_LIFT
#   腿部弯曲点    → CONFIG 里的 hip(髋) / knee(膝) / ankle(踝) 锚点坐标
#   枪口火光位置  → CONFIG 里的 muzzle
# ============================================================================

## Driver locomotion: two independently posed textured legs, original armed upper body.
## Cached geometry + GPU vertex deformation: three moving draw calls, no per-frame CPU mesh construction.
const ART := {
	"pistol": "res://art/characters_v3/armed_20261004/driver_pistol_m1911.png",
	"machine_gun": "res://art/characters_v3/armed_20261004/driver_mg_m249.png",
}
const CONFIG := {
	"pistol": {"hip": Vector2(398, 637), "knee": Vector2(394, 870),
		"ankle": Vector2(367, 1100), "sole": 1236.0, "head": 18.0,
		"cut": 611.0, "muzzle": Vector2(977, 250)},
	"machine_gun": {"hip": Vector2(353, 606), "knee": Vector2(352, 848),
		"ankle": Vector2(323, 1080), "sole": 1223.0, "head": 18.0,
		"cut": 574.0, "muzzle": Vector2(1160, 246)},
}
const HALF_STRIDE := 155.0
const FOOT_LIFT := 60.0
const BODY_LOWERING := 22.0
const BODY_BOB := 5.0
const LAND_DURATION := 0.24
const LAND_CROUCH := 52.0
var jump_weight := 0.0
var landing_weight := 0.0
var motion_state := "idle"
var _air_front := Vector2.ZERO
var _air_back := Vector2.ZERO
var _last_air_speed := 0.0
var _was_grounded := true
var _motion_started := false
var _land_elapsed := LAND_DURATION
var _land_strength := 0.0
var phase := 0.0
var blend := 0.0
var facing := 1
var pose := ""
var texture: Texture2D
var cfg: Dictionary
var pixel_scale := 1.0
const LEG_SHADER = preload("res://driver_leg.gdshader")
var _textures: Dictionary = {}
var _meshes: Dictionary = {}
var _bob := 0.0
var _far_leg: MeshInstance2D
var _near_leg: MeshInstance2D
var _upper: Sprite2D
var _idle: Sprite2D
var _last_phase := -1.0
var _last_blend := -1.0
var _last_facing := 0

func configure(weapon_type: String) -> bool:
	var next_pose := "pistol" if weapon_type == "pistol" else "machine_gun"
	if pose == next_pose and texture != null:
		return true
	var path: String = ART[next_pose]
	if not _textures.has(next_pose):
		if not ResourceLoader.exists(path):
			return false
		_textures[next_pose] = load(path)
	texture = _textures[next_pose]
	if texture == null:
		return false
	pose = next_pose
	cfg = CONFIG[pose]
	pixel_scale = 180.0 / (float(cfg.sole) - float(cfg.head))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ensure_nodes()
	if not _meshes.has(pose):
		_meshes[pose] = _build_mesh()
	for leg: MeshInstance2D in [_far_leg, _near_leg]:
		leg.texture = texture
		leg.mesh = _meshes[pose]
		var mat := leg.material as ShaderMaterial
		mat.set_shader_parameter("source_origin", Vector2(cfg.hip.x, cfg.sole))
		mat.set_shader_parameter("rest_hip", cfg.hip)
		mat.set_shader_parameter("rest_knee", cfg.knee)
		mat.set_shader_parameter("rest_ankle", cfg.ankle)
		mat.set_shader_parameter("cut_y", cfg.cut)
		# Deformed feet can extend beyond the standing mesh's bounds.
		RenderingServer.canvas_item_set_custom_rect(leg.get_canvas_item(), true, Rect2(-500,-800,1100,1100))
	_idle.texture = texture
	_idle.position = _local(Vector2.ZERO)
	_upper.texture = texture
	_upper.region_rect = Rect2(0,0,texture.get_width(),cfg.cut)
	_last_phase = -1.0
	_last_blend = -1.0
	_last_facing = 0
	_update_transform()
	_update_visual()
	return true

func _ensure_nodes():
	if _idle != null:
		return
	_far_leg = MeshInstance2D.new()
	_near_leg = MeshInstance2D.new()
	_far_leg.name = "FarLeg"
	_near_leg.name = "NearLeg"
	for leg: MeshInstance2D in [_far_leg, _near_leg]:
		var mat := ShaderMaterial.new()
		mat.shader = LEG_SHADER
		leg.material = mat
		add_child(leg)
	_upper = Sprite2D.new()
	_upper.name = "UpperBody"
	_upper.centered = false
	_upper.region_enabled = true
	add_child(_upper)
	_idle = Sprite2D.new()
	_idle.name = "IdleBody"
	_idle.centered = false
	add_child(_idle)

func advance(delta: float, distance: float, grounded: bool, direction: int, vertical_speed := 0.0) -> bool:
	facing = direction
	var moving := grounded and distance > 0.01
	var old_half := int(phase / PI)
	var previous_jump := jump_weight
	var previous_landing := landing_weight
	var previous_front := _air_front
	var previous_back := _air_back
	_update_jump(delta, grounded, vertical_speed)
	if moving:
		phase = fposmod(phase + distance / cycle_distance() * TAU, TAU)
	blend = move_toward(blend, 1.0 if moving else 0.0, delta * 10.0)
	_bob = blend * (BODY_LOWERING + BODY_BOB * cos(phase * 2.0)) * (1.0 - jump_weight)
	_bob += 4.0 * jump_weight + LAND_CROUCH * landing_weight
	if grounded and landing_weight < 0.001:
		motion_state = "walk" if moving else "idle"
	if facing != _last_facing:
		_update_transform()
	var jump_changed := jump_weight != previous_jump or landing_weight != previous_landing or _air_front != previous_front or _air_back != previous_back
	if phase != _last_phase or blend != _last_blend or jump_changed:
		_update_visual()
	return moving and old_half != int(phase / PI)

func _update_jump(delta: float, grounded: bool, vertical_speed: float):
	# A zero-time refresh (e.g. changing guns) must not consume a landing event.
	if delta <= 0.0:
		return
	if grounded and _motion_started and not _was_grounded:
		_land_elapsed = 0.0
		_land_strength = clampf(_last_air_speed / 520.0, 0.0, 1.0)
	if grounded:
		_land_elapsed = minf(LAND_DURATION, _land_elapsed + delta)
		var progress := _land_elapsed / LAND_DURATION
		landing_weight = sin(PI * sqrt(progress)) * _land_strength if progress < 1.0 else 0.0
		jump_weight = move_toward(jump_weight, 0.0, delta * 12.0)
		motion_state = "landing" if landing_weight > 0.001 else "idle"
	else:
		_land_elapsed = LAND_DURATION
		landing_weight = 0.0
		_last_air_speed = maxf(0.0, vertical_speed)
		jump_weight = move_toward(jump_weight, 1.0, delta * 12.0)
		var front: Vector2
		var back: Vector2
		if vertical_speed < -90.0:
			# One knee leads; the other leg trails during takeoff.
			motion_state = "jump_rise"
			var tuck := 1.0 - clampf((-vertical_speed - 90.0) / 430.0, 0.0, 1.0)
			front = Vector2(70.0, -55.0).lerp(Vector2(100.0, -115.0), tuck)
			back = Vector2(-80.0, -20.0).lerp(Vector2(-65.0, -80.0), tuck)
		elif vertical_speed <= 90.0:
			motion_state = "jump_apex"
			front = Vector2(100.0, -115.0)
			back = Vector2(-65.0, -80.0)
		else:
			# Extend toward the floor as falling speed increases.
			motion_state = "jump_fall"
			var extend := clampf((vertical_speed - 90.0) / 360.0, 0.0, 1.0)
			front = Vector2(100.0, -115.0).lerp(Vector2(65.0, -5.0), extend)
			back = Vector2(-65.0, -80.0).lerp(Vector2(-55.0, -12.0), extend)
		var follow := 1.0 - exp(-delta * 18.0)
		_air_front = _air_front.lerp(front, follow)
		_air_back = _air_back.lerp(back, follow)
	_was_grounded = grounded
	_motion_started = true

func _update_visual():
	_last_phase = phase
	_last_blend = blend
	var pose_weight := maxf(blend, maxf(jump_weight, landing_weight))
	var walking := pose_weight >= 0.001
	_idle.visible = not walking
	_upper.visible = walking
	_near_leg.visible = walking
	_far_leg.visible = walking
	if not walking:
		return
	_upper.position = _local(Vector2(0,_bob))
	_far_leg.self_modulate = Color(0.76,0.79,0.82,pose_weight)
	_update_leg(_near_leg, phase)
	_update_leg(_far_leg, phase + PI)

func _update_leg(leg: MeshInstance2D, leg_phase: float):
	var joints := _joints(leg_phase)
	var thigh_angle: float = (joints[1] - joints[0]).angle() - (cfg.knee - cfg.hip).angle()
	var shin_angle: float = (joints[2] - joints[1]).angle() - (cfg.ankle - cfg.knee).angle()
	var mat := leg.material as ShaderMaterial
	mat.set_shader_parameter("posed_hip",joints[0])
	mat.set_shader_parameter("posed_knee",joints[1])
	mat.set_shader_parameter("posed_ankle",joints[2])
	mat.set_shader_parameter("rotations",Vector4(cos(thigh_angle),sin(thigh_angle),cos(shin_angle),sin(shin_angle)))
	mat.set_shader_parameter("body_bob",_bob)

func _build_mesh() -> ArrayMesh:
	# Build UVs and indexed triangles once per pose, shared by both legs.
	var rows: Array[float] = []
	var y := float(cfg.cut) - 2.0
	while y < texture.get_height():
		rows.append(y)
		y += 22.0
	rows.append(float(texture.get_height()))
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var tex_size := Vector2(texture.get_size())
	for row_y in rows:
		var edge := _boot_edge(row_y)
		for col in range(8):
			var p := Vector2(minf(220.0 + col*50.0,edge),row_y)
			var local := _local(p)
			vertices.append(Vector3(local.x,local.y,0))
			uv.append(p/tex_size)
	for row in range(rows.size()-1):
		for col in range(7):
			var a := row*8+col
			var b := a+1
			var c := a+9
			var d := a+8
			for tri in [[a,b,c],[a,c,d]]:
				var ab := vertices[tri[1]]-vertices[tri[0]]
				var ac := vertices[tri[2]]-vertices[tri[0]]
				if ab.cross(ac).length_squared() > 0.0001:
					indices.append_array(PackedInt32Array(tri))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func cycle_distance() -> float:
	return 4.0 * HALF_STRIDE * pixel_scale

func _update_transform():
	_last_facing = facing
	scale = Vector2(pixel_scale * facing, pixel_scale)
	position = Vector2(0, 90.0)

func muzzle_local() -> Vector2:
	var point: Vector2 = cfg.muzzle + Vector2(0, _bob)
	return Vector2((point.x - cfg.hip.x) * pixel_scale * facing,
		90.0 + (point.y - cfg.sole) * pixel_scale)

func foot_target(leg_phase: float) -> Vector2:
	var t := fposmod(leg_phase, TAU) / TAU
	var x: float
	var lift := 0.0
	if t < 0.5:
		x = lerpf(HALF_STRIDE, -HALF_STRIDE, t * 2.0)
	else:
		var swing := (t - 0.5) * 2.0
		x = lerpf(-HALF_STRIDE, HALF_STRIDE, smoothstep(0.0, 1.0, swing))
		lift = sin(swing * PI) * FOOT_LIFT
	# Center the moving stride under the hip. The standing ankle sits behind
	# it in the source art; keeping that bias would overextend the rear step.
	var center_shift: float = cfg.hip.x - cfg.ankle.x
	var target: Vector2 = cfg.ankle + Vector2(x + center_shift, -lift) * blend
	var near_leg := cos(leg_phase - phase) > 0.0
	var air_offset := _air_front if near_leg else _air_back
	var air_target: Vector2 = cfg.ankle + Vector2(center_shift, 0) + air_offset
	target = target.lerp(air_target, jump_weight)
	var land_offset := 65.0 if near_leg else -55.0
	# A running landing keeps the horizontal walking contact path; a
	# stationary landing uses a small, stable split stance.
	var land_x := lerpf(center_shift + land_offset, x + center_shift, blend)
	var land_target: Vector2 = cfg.ankle + Vector2(land_x, 0)
	return target.lerp(land_target, landing_weight)

func _joints(leg_phase: float) -> Array[Vector2]:
	var hip: Vector2 = cfg.hip + Vector2(0, _bob)
	var target := foot_target(leg_phase)
	var upper_len: float = cfg.hip.distance_to(cfg.knee)
	var lower_len: float = cfg.knee.distance_to(cfg.ankle)
	var offset := target - hip
	var distance := clampf(offset.length(), 0.001, upper_len + lower_len - 0.001)
	var axis := offset.normalized()
	var along := (upper_len * upper_len - lower_len * lower_len + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_len * upper_len - along * along))
	var knee := hip + axis * along + Vector2(axis.y, -axis.x) * height
	# The stop transition returns to the approved standing silhouette.
	knee = (cfg.knee as Vector2).lerp(knee, maxf(blend, maxf(jump_weight, landing_weight)))
	return [hip, knee, target]

func _local(point: Vector2) -> Vector2:
	return point - Vector2(cfg.hip.x, cfg.sole)

func _boot_edge(y: float) -> float:
	# Hide the small far boot present in the standing artwork before posing
	# each leg independently, otherwise the moving silhouette has four toes.
	var contour := PackedVector2Array([Vector2(1090,428), Vector2(1130,428), Vector2(1155,445), Vector2(1178,548), Vector2(1254,570)])
	if pose == "machine_gun":
		contour = PackedVector2Array([Vector2(1070,382), Vector2(1110,389), Vector2(1135,405), Vector2(1160,495), Vector2(1254,570)])
	if y < contour[0].x:
		return 570.0
	for i in range(contour.size() - 1):
		if y <= contour[i + 1].x:
			return lerpf(contour[i].y, contour[i + 1].y, inverse_lerp(contour[i].x, contour[i + 1].x, y))
	return 570.0
