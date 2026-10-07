extends Node2D

# ============================================================================
# character_locomotion.gd —— 玩家角色 GPU 蒙皮动作（走路/跳跃/落地/持枪）
# ----------------------------------------------------------------------------
# 原英文注释机翻：
#   「共用的按距离驱动的步态/跳跃，枪械独立适配，前景双手。」
#   「缓存索引网格：不做逐帧图像处理，也不逐帧构建网格。」
#
# 【它解决什么问题】
# 玩家角色（司机/医生/警察/军人/维修工/程序员共用）的立绘会走会跳会落地。
# 与 zombie_motion.gd 同思路：切多边形网格 + 顶点变形，不做逐帧切图。
# 「按距离驱动」是关键——脚步相位由**走过的距离**推进，不是由时间推进，
# 所以玩家改变速度时脚不会打滑（时间驱动就会滑步）。
#
# 【关键常量】
#   HALF_STRIDE  —— 半个步幅（一整步 = 2×），决定迈多远
#   FOOT_LIFT    —— 抬脚高度，决定步子高低
#   BODY_LOWERING—— 走路时身体下沉量（真实走路身体会略沉）
#   BODY_BOB     —— 身体上下起伏幅度
#   LAND_DURATION / LAND_CROUCH —— 落地缓冲时长与下蹲幅度
#
# 【依赖】
#   BODY_DATA  = character_visuals.gd（6 个角色的身体骨骼锚点）
#   WEAPON_DATA = weapon_visuals.gd（16 把枪的握持点/枪口锚点，实现枪随手走）
#
# 【想改的地方】
#   走路步幅/节奏 → HALF_STRIDE / FOOT_LIFT
#   跳跃手感      → jump_weight 推进与 LAND_* 落地参数
#   持枪位置      → weapon_visuals.gd 里每把枪的 grip / muzzle
# ============================================================================

## Shared distance-driven gait/jump, independently fitted guns and foreground hands.
## Cached indexed meshes: no per-frame image processing or mesh construction.
const BODY_DATA = preload("res://character_visuals.gd")
const WEAPON_DATA = preload("res://weapon_visuals.gd")
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
var motion_scale := 1.0
var character_id := ""
var weapon_id := ""
var weapon_cfg: Dictionary
var _body_key := ""
var _weapon_muzzle := Vector2.ZERO
var _weapon_rest := Vector2.ZERO
const LEG_SHADER = preload("res://character_leg.gdshader")
static var _textures: Dictionary = {}
static var _meshes: Dictionary = {}
var _bob := 0.0
var _far_leg: MeshInstance2D
var _near_leg: MeshInstance2D
var _upper: Sprite2D
var _idle: Sprite2D
var _gun: Sprite2D
var _hands: Array[Polygon2D] = []
var _last_phase := -1.0
var _last_blend := -1.0
var _last_facing := 0

func configure(next_character: String, next_weapon: String, weapon: Dictionary) -> bool:
	var next_pose := "pistol" if str(weapon.get("type", "pistol")) == "pistol" else "machine_gun"
	if character_id == next_character and weapon_id == next_weapon and texture != null:
		return true
	var next_cfg := BODY_DATA.body(next_character, next_pose)
	var next_weapon_cfg := WEAPON_DATA.anchors(next_weapon)
	var gun_path := str(weapon.get("texture", ""))
	if next_cfg.is_empty() or next_weapon_cfg.is_empty():
		return false
	var path: String = next_cfg.path
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(gun_path):
		return false
	if not _textures.has(path): _textures[path] = load(path)
	if not _textures.has(gun_path): _textures[gun_path] = load(gun_path)
	if _textures[path] == null or _textures[gun_path] == null: return false
	var next_key := next_character + "/" + next_pose
	var body_changed := next_key != _body_key
	character_id = next_character
	weapon_id = next_weapon
	pose = next_pose
	cfg = next_cfg
	texture = _textures[path]
	weapon_cfg = next_weapon_cfg
	pixel_scale = 180.0 / (float(cfg.sole) - float(cfg.head))
	motion_scale = (float(cfg.sole) - float(cfg.head)) / 1218.0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ensure_nodes()
	if body_changed:
		_body_key = next_key
		if not _meshes.has(next_key): _meshes[next_key] = _build_mesh()
		for leg: MeshInstance2D in [_far_leg, _near_leg]:
			leg.texture = texture
			leg.mesh = _meshes[next_key]
			var mat := leg.material as ShaderMaterial
			mat.set_shader_parameter("source_origin", Vector2(cfg.hip.x, cfg.sole))
			mat.set_shader_parameter("rest_hip", cfg.hip)
			mat.set_shader_parameter("rest_knee", cfg.knee)
			mat.set_shader_parameter("rest_ankle", cfg.ankle)
			mat.set_shader_parameter("cut_y", cfg.deform_cut)
			RenderingServer.canvas_item_set_custom_rect(leg.get_canvas_item(), true, Rect2(-700,-1000,1500,1400))
		_idle.texture = texture
		_idle.position = _local(Vector2.ZERO)
		_upper.texture = texture
		_upper.region_rect = Rect2(0,0,texture.get_width(),cfg.cut)
		_configure_hands()
	_fit_weapon(_textures[gun_path])
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
	_gun = Sprite2D.new()
	_gun.name = "HeldWeapon"
	_gun.centered = false
	add_child(_gun)
	for i in range(2):
		var hand := Polygon2D.new()
		hand.name = "GripHand" if i == 0 else "SupportHand"
		add_child(hand)
		_hands.append(hand)

func _configure_hands():
	var rects: Array = [cfg.pistol_hand] if pose == "pistol" else [cfg.rear_hand, cfg.front_hand]
	for i in range(2):
		_hands[i].visible = i < rects.size()
		if i >= rects.size(): continue
		var r: Rect2 = rects[i]
		var points := PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
		var local := PackedVector2Array()
		for p in points: local.append(_local(p))
		_hands[i].texture = texture
		_hands[i].uv = points
		_hands[i].polygon = local

func _fit_weapon(gun_texture: Texture2D):
	_gun.texture = gun_texture
	var size := gun_texture.get_size()
	var grip: Vector2 = weapon_cfg.grip * size
	_weapon_muzzle = weapon_cfg.muzzle * size
	var flip := -1.0 if weapon_cfg.get("flip",false) else 1.0
	var rotation_angle := 0.0
	var factor: float
	var target_grip: Vector2
	if pose == "pistol":
		factor = float(weapon_cfg.height) * motion_scale / size.y
		target_grip = cfg.pistol_grip
	else:
		target_grip = cfg.rear_grip
		var source_delta: Vector2 = (weapon_cfg.support - weapon_cfg.grip) * size
		source_delta.x *= flip
		var target_delta: Vector2 = cfg.support - target_grip
		factor = target_delta.length() / source_delta.length()
		rotation_angle = target_delta.angle() - source_delta.angle()
	_gun.rotation = rotation_angle
	_gun.scale = Vector2(factor*flip,factor)
	_weapon_rest = _local(target_grip) - (grip * _gun.scale).rotated(rotation_angle)
	_gun.position = _weapon_rest + Vector2(0,_bob)

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
	_bob = (blend * (BODY_LOWERING + BODY_BOB * cos(phase * 2.0)) * (1.0 - jump_weight)
		+ 4.0 * jump_weight + LAND_CROUCH * landing_weight) * motion_scale
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
	_gun.position = _weapon_rest + Vector2(0,_bob)
	for hand in _hands: hand.position = Vector2(0,_bob)
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
	# Build UVs and indexed triangles once per character/pose, shared by both legs.
	var rows: Array[float] = []
	var y := float(cfg.get("leg_start",cfg.cut)) - 2.0
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
			var p := Vector2(minf(lerpf(cfg.left,cfg.right,col/7.0),edge),row_y)
			var local := _local(p)
			vertices.append(Vector3(local.x,local.y,0))
			var sample_point := p
			# The doctor's coat hides the upper thigh in the source image.
			# Extend the visible trouser strip under that coat in UV space;
			# otherwise bending the knee would expose an empty upper leg.
			if cfg.has("leg_texture_top") and p.y < cfg.knee.y:
				sample_point.y = remap(p.y,float(cfg.leg_start),cfg.knee.y,float(cfg.leg_texture_top),cfg.knee.y)
			uv.append(sample_point/tex_size)
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
	return 4.0 * HALF_STRIDE * motion_scale * pixel_scale

func _update_transform():
	_last_facing = facing
	scale = Vector2(pixel_scale * facing, pixel_scale)
	position = Vector2(0, 90.0)

func muzzle_local() -> Vector2:
	return transform * (_gun.transform * _weapon_muzzle)

func foot_target(leg_phase: float) -> Vector2:
	var t := fposmod(leg_phase, TAU) / TAU
	var x: float
	var lift := 0.0
	if t < 0.5:
		x = lerpf(HALF_STRIDE, -HALF_STRIDE, t * 2.0) * motion_scale
	else:
		var swing := (t - 0.5) * 2.0
		x = lerpf(-HALF_STRIDE, HALF_STRIDE, smoothstep(0.0, 1.0, swing)) * motion_scale
		lift = sin(swing * PI) * FOOT_LIFT * motion_scale
	# Center the moving stride under the hip. The standing ankle sits behind
	# it in the source art; keeping that bias would overextend the rear step.
	var center_shift: float = cfg.hip.x - cfg.ankle.x
	var target: Vector2 = cfg.ankle + Vector2(x + center_shift, -lift) * blend
	var near_leg := cos(leg_phase - phase) > 0.0
	var air_offset := (_air_front if near_leg else _air_back) * motion_scale
	var air_target: Vector2 = cfg.ankle + Vector2(center_shift, 0) + air_offset
	target = target.lerp(air_target, jump_weight)
	var land_offset := (65.0 if near_leg else -55.0) * motion_scale
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
	# Hide the small far boot present in each standing artwork before posing
	# each leg independently, otherwise the moving silhouette has four toes.
	var contour: PackedVector2Array = cfg.boot
	if y < contour[0].x:
		return float(cfg.right)
	for i in range(contour.size() - 1):
		if y <= contour[i + 1].x:
			return lerpf(contour[i].y, contour[i + 1].y, inverse_lerp(contour[i].x, contour[i + 1].x, y))
	return float(cfg.right)
