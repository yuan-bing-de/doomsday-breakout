extends Node2D

# ============================================================================
# zombie_motion.gd —— 丧尸 GPU 蒙皮动作系统（走路/挥爪/死亡的骨骼动画驱动）
# ----------------------------------------------------------------------------
# 原英文注释机翻：「共用的 GPU 蒙皮丧尸动作。网格/权重每个种类只构建一次，绝不逐帧重建。」
#
# 【它解决什么问题】
# 让静态的丧尸立绘 PNG「动起来」——走路摆腿、挥爪拍打、死亡倒地。
# 传统做法是逐帧切图（每种动作要画 N 张图、内存暴涨），
# 本系统改为：把立绘切成「多边形网格」，用顶点着色器让网格顶点随时间摆动，
# 实现同样效果但只占 3 个 draw call，且网格只建一次、之后每帧只改参数。
#
# 【关键设计】
#   static var meshes / textures —— 静态缓存：网格与贴图按物种缓存，
#     多只同种丧尸共用一份，只在第一次出现时构建，之后完全复用（省内存+省 CPU）。
#   PROFILES —— 骨骼锚点数据（源图像素坐标），由 zombie_motion_profiles.gd 提供。
#   SKIN     —— 顶点变形着色器，做实际的肢体摆动计算。
#   phase / blend —— phase 是走路循环的相位（0~1 循环往复），blend 是不同动作间的混合权重。
#   arms（Vector4）/ body_angle / body_shift —— 身体各部位当前姿态参数。
#
# 【想改的地方】
#   - 走路快慢/步幅     → 看 PHASE 推进速度与 PROFILES 里的 stride
#   - 挥爪时机          → 看 CLAW_HIT(命中帧 0.38) / CLAW_DURATION(整段时长 0.65 秒)
#   - 皮毛/衣服质感     → 看 CLOTHING_PATH 指向的衣物图集与 zombie_skin.gdshader
# ============================================================================

## Shared GPU-skinned zombie motion. Mesh/weights built once per species, never per frame.
const PROFILES=preload("res://zombie_motion_profiles.gd")
const SKIN=preload("res://zombie_skin.gdshader")
const CLOTHING_PATH="res://art/zombie_motion/clothing_atlas.png"
const CATALOG=preload("res://zombie_catalog.gd")
const CLAW_HIT:=.38
const CLAW_DURATION:=.65
static var meshes: Dictionary={}
static var textures: Dictionary={}
var source: Sprite2D
var cfg: Dictionary
var species: String
var mesh_node: MeshInstance2D
var torso_patch: Polygon2D
var material_skin: ShaderMaterial
var phase:=0.0
var blend:=0.0
var clock:=0.0
var motion_state:="idle"
var arms:=Vector4.ZERO
var body_angle:=0.0
var body_shift:=Vector2.ZERO
var head_angle:=0.0
var pelvis:=Vector2.ZERO
var center:=Vector2.ZERO
var posed_legs: Array=[]
var leg_angles:=Vector4.ZERO
var leg_blend:=0.0
var last_hand:=Vector2.ZERO
var pixel_scale:=1.0

static func warmup(stage: int):
	if not textures.has(CLOTHING_PATH):textures[CLOTHING_PATH]=load(CLOTHING_PATH)
	# Load once while entering a stage, so a newly spawned species cannot stall a combat frame.
	for id in CATALOG.DEFINITIONS:
		if not CATALOG.unlocked(id,stage):continue
		var path:String=CATALOG.DEFINITIONS[id].texture
		if not textures.has(path):textures[path]=load(path)
		var mesh_path:String="res://art/zombie_motion/"+id+"_mesh.res"
		if not meshes.has(id) and ResourceLoader.exists(mesh_path):meshes[id]=load(mesh_path)

func configure(sprite: Sprite2D,id: String) -> bool:
	if not PROFILES.DATA.has(id) or sprite.texture==null or not sprite.region_enabled:return false
	source=sprite
	cfg=PROFILES.DATA[id]
	species=id
	center=source.region_rect.get_center()
	pixel_scale=source.scale.y
	pelvis=(cfg.legs[0][0]+cfg.legs[1][0])*.5
	_build_torso_patch()
	mesh_node=MeshInstance2D.new()
	mesh_node.name="SkinnedZombie"
	mesh_node.texture=source.texture
	mesh_node.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	if not meshes.has(id):
		var baked_path:="res://art/zombie_motion/"+id+"_mesh.res"
		meshes[id]=load(baked_path) if ResourceLoader.exists(baked_path) else _build_mesh()
	mesh_node.mesh=meshes[id]
	mesh_node.position=-center
	material_skin=ShaderMaterial.new()
	material_skin.shader=SKIN
	mesh_node.material=material_skin
	add_child(mesh_node)
	RenderingServer.canvas_item_set_custom_rect(mesh_node.get_canvas_item(),true,Rect2(-500,-500,2200,2400))
	material_skin.set_shader_parameter("texture_size",source.texture.get_size())
	material_skin.set_shader_parameter("pelvis",pelvis)
	material_skin.set_shader_parameter("neck",cfg.neck)
	material_skin.set_shader_parameter("near_shoulder",cfg.near[0])
	material_skin.set_shader_parameter("near_elbow",cfg.near[1])
	material_skin.set_shader_parameter("far_shoulder",cfg.far[0])
	material_skin.set_shader_parameter("far_elbow",cfg.far[1])
	for i in range(2):
		material_skin.set_shader_parameter("hip"+str(i),cfg.legs[i][0])
		material_skin.set_shader_parameter("knee"+str(i),cfg.legs[i][1])
		material_skin.set_shader_parameter("ankle"+str(i),cfg.legs[i][2])
	source.hide()
	advance(0,0,"idle",0)
	return true

func _split_x(y: float) -> float:
	var points: Array=cfg.split
	for i in range(points.size()-1):
		if y<=points[i+1].x:
			return lerpf(points[i].y,points[i+1].y,clampf(inverse_lerp(points[i].x,points[i+1].x,y),0,1))
	return points[-1].y

func _build_mesh() -> ArrayMesh:
	var rect:=source.region_rect
	var cols:=ceili(rect.size.x/16.0)
	var rows:=ceili(rect.size.y/16.0)
	var vertices:=PackedVector3Array()
	var weights:=PackedVector2Array()
	var indices:=PackedInt32Array()
	var near_poly:=PackedVector2Array(cfg.near_poly)
	var far_poly:=PackedVector2Array(cfg.far_poly)
	for row in range(rows):
		for col in range(cols):
			var a:=rect.position+rect.size*Vector2(float(col)/cols,float(row)/rows)
			var b:=rect.position+rect.size*Vector2(float(col+1)/cols,float(row+1)/rows)
			var cell:=PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)])
			var remainder: Array=[cell]
			for part in [1,-1]:
				var mask:=near_poly if part==1 else far_poly
				var after:=[]
				for polygon in remainder:
					for cut in Geometry2D.intersect_polygons(polygon,mask):
						_append_polygon(cut,part,vertices,weights,indices)
					for keep in Geometry2D.clip_polygons(polygon,mask):after.append(keep)
				remainder=after
			for polygon in remainder:_append_polygon(polygon,0,vertices,weights,indices)
	var data:=[]
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX]=vertices
	data[Mesh.ARRAY_TEX_UV]=weights
	data[Mesh.ARRAY_INDEX]=indices
	var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	return result

func _append_polygon(polygon: PackedVector2Array,part: int,vertices: PackedVector3Array,weights: PackedVector2Array,indices: PackedInt32Array):
	var triangles:=Geometry2D.triangulate_polygon(polygon)
	var start:=vertices.size()
	for p in polygon:
		var arm:=0.0
		if part!=0:
			var shoulder:Vector2=cfg.near[0] if part==1 else cfg.far[0]
			arm=part*smoothstep(shoulder.y-55,shoulder.y+95,p.y)
		var leg:=smoothstep(cfg.cut,cfg.cut+120,p.y) if part==0 else 0.0
		if p.x<_split_x(p.y):leg=-leg
		vertices.append(Vector3(p.x,p.y,0))
		weights.append(Vector2(arm,leg))
	for index in triangles:indices.append(start+index)

func _build_torso_patch():
	# A shared illustrated garment atlas reconstructs the body hidden by resting arms.
	# Original zombie PNGs remain unchanged; the atlas is a separate repair layer.
	var contours:={
		"male":[Vector2(360,315),Vector2(500,360),Vector2(600,480),Vector2(622,821),Vector2(556,978),Vector2(405,952),Vector2(340,769),Vector2(305,480)],
		"female":[Vector2(459,389),Vector2(540,357),Vector2(604,462),Vector2(600,651),Vector2(678,1087),Vector2(391,1111),Vector2(335,861),Vector2(347,681)],
		"fat":[Vector2(340,340),Vector2(523,360),Vector2(681,561),Vector2(746,752),Vector2(644,1010),Vector2(370,1010),Vector2(270,750),Vector2(300,480)],
		"runner":[Vector2(447,318),Vector2(602,314),Vector2(683,441),Vector2(670,574),Vector2(568,729),Vector2(379,787),Vector2(365,573),Vector2(367,447)],
		"spitter":[Vector2(385,335),Vector2(530,349),Vector2(614,428),Vector2(637,685),Vector2(586,980),Vector2(330,976),Vector2(275,870),Vector2(295,600)],
		"armored":[Vector2(375,276),Vector2(540,366),Vector2(647,506),Vector2(665,809),Vector2(580,942),Vector2(410,937),Vector2(314,705),Vector2(310,440)],
		"volatile":[Vector2(485,406),Vector2(629,360),Vector2(774,602),Vector2(796,788),Vector2(649,1040),Vector2(433,1040),Vector2(391,725),Vector2(398,573)],
		"howler":[Vector2(455,340),Vector2(610,386),Vector2(659,470),Vector2(691,737),Vector2(620,1030),Vector2(395,1065),Vector2(380,980),Vector2(389,638)]}
	if not textures.has(CLOTHING_PATH):textures[CLOTHING_PATH]=load(CLOTHING_PATH)
	torso_patch=Polygon2D.new()
	torso_patch.texture=textures[CLOTHING_PATH]
	torso_patch.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	torso_patch.modulate=Color(.88,.88,.88,1)
	var index:int=CATALOG.DEFINITIONS.keys().find(species)
	var tile_size:Vector2=torso_patch.texture.get_size()/Vector2(4,2)
	var tile_origin:=Vector2(index%4,index/4)*tile_size+Vector2(3,3)
	var bounds:=Rect2(contours[species][0],Vector2.ZERO)
	for p:Vector2 in contours[species]:bounds=bounds.expand(p)
	var points:=PackedVector2Array()
	var uv:=PackedVector2Array()
	for p:Vector2 in contours[species]:
		points.append(p-pelvis)
		uv.append(tile_origin+(p-bounds.position)/bounds.size*(tile_size-Vector2(6,6)))

	torso_patch.polygon=points
	torso_patch.uv=uv
	add_child(torso_patch)

func cycle_distance(charging:=false) -> float:
	return float(cfg.stride)*4.0*(1.4 if charging else 1.0)

func advance(delta: float,distance: float,state: String,progress: float):
	clock+=delta
	motion_state=state
	var moving:=distance>.001 and distance<160
	if moving:phase=fposmod(phase+distance/cycle_distance(state=="charge")*TAU,TAU)
	blend=move_toward(blend,1.0 if moving else 0.0,delta*8)
	arms=Vector4(-.09*sin(phase),-.12*sin(phase),.08*sin(phase),.12*sin(phase))*blend
	body_angle=.012*sin(phase)*blend
	body_shift=Vector2(0,blend*(9+3*cos(phase*2)))
	head_angle=.008*sin(clock*2)
	var planted:=0.0
	match state:
		"claw":
			var pose:=_claw(progress)
			arms=Vector4(pose.x,pose.y,pose.x*.28,pose.y*.22)
			body_angle=pose.z
			body_shift+=Vector2(pose.w,10*sin(clampf(progress/CLAW_DURATION,0,1)*PI))
			planted=1
		"tongue":
			var t:=clampf(progress/.55,0,1)
			var push:=sin(PI*t)
			body_angle=.045*push
			head_angle=-.08*push
			body_shift+=Vector2(40*push,0)
			arms=Vector4(-.12,-.2,-.25,-.3)*push
			planted=1
		"spit_windup":
			var t:=clampf(progress,0,1)
			body_angle=-.04*sin(t*PI)+.045*t
			head_angle=-.16*sin(t*PI)
			arms=Vector4(-.35,-.65,-.25,-.45)*sin(t*PI*.5)
			body_shift.y+=12*sin(t*PI)
			planted=1
		"spit_release":
			var strength:=1-clampf(progress/.3,0,1)
			body_angle=.075*strength
			head_angle=.06*strength
			body_shift.x=38*strength
			arms=Vector4(-.28,-.45,-.18,-.3)*strength
			planted=1
		"charge_windup":
			var t:=clampf(progress,0,1)
			body_shift=Vector2(-25*t,38*t)
			body_angle=.07*t
			arms=Vector4(.2,.3,-.6,-.7)*t
			planted=1
		"charge":
			body_angle=.085
			body_shift.y+=20
			arms+=Vector4(-.75,-1.0,-.9,-1.1)
			head_angle=-.035
		"recovery":
			var t:=1-clampf(progress,0,1)
			body_angle=.07*t
			body_shift.y+=30*t
			arms=Vector4(-.2,-.1,-.25,-.15)*t
			planted=1
		"fuse":
			var t:=clampf(progress,0,1)
			body_angle=-.025*t
			body_shift.y+=20*t
			body_shift.x=3*sin(clock*(15+16*t))*t
			arms=Vector4(-.45,-.85,.18,.32)*t
			head_angle=-.08*t
			planted=1
		"howl_windup","howl_wave":
			var t:=clampf(progress,0,1) if state=="howl_windup" else 1-clampf(progress,0,1)
			body_angle=-.045*t
			head_angle=-.2*t
			arms=Vector4(-.6,-1.1,-.35,-.7)*t
			body_shift.y+=15*t
			planted=1
	leg_blend=maxf(blend,planted)
	_pose_legs(state=="charge")
	material_skin.set_shader_parameter("body_angle",body_angle)
	material_skin.set_shader_parameter("body_shift",body_shift)
	material_skin.set_shader_parameter("head_angle",head_angle)
	material_skin.set_shader_parameter("arm_angles",arms)
	material_skin.set_shader_parameter("leg_angles",leg_angles)
	material_skin.set_shader_parameter("leg_blend",leg_blend)
	for i in range(2):
		material_skin.set_shader_parameter("posed_hip"+str(i),posed_legs[i][0])
		material_skin.set_shader_parameter("posed_knee"+str(i),posed_legs[i][1])
		material_skin.set_shader_parameter("posed_ankle"+str(i),posed_legs[i][2])
	_sync_transform()
	torso_patch.position=pelvis+body_shift-center
	torso_patch.rotation=body_angle
	torso_patch.visible=absf(arms.x)>.002 or absf(arms.z)>.002
	last_hand=hand_global()

func _claw(t: float) -> Vector4:
	var times:=[0.0,.24,CLAW_HIT,.46,CLAW_DURATION]
	var upper:float=(cfg.near[1]-cfg.near[0]).angle()
	var lower:float=(cfg.near[3]-cfg.near[1]).angle()
	var poses:=[Vector4.ZERO,Vector4(-upper,-.95-lower,-.035,-18),Vector4(.42-upper,-.04-lower,.06,65),Vector4(.7-upper,.5-lower,.035,32),Vector4.ZERO]
	for i in range(times.size()-1):
		if t<=times[i+1]:return (poses[i] as Vector4).lerp(poses[i+1],smoothstep(times[i],times[i+1],t))
	return Vector4.ZERO

func _body_point(p: Vector2) -> Vector2:
	return pelvis+(p-pelvis).rotated(body_angle)+body_shift

func _pose_legs(charging: bool):
	posed_legs.clear()
	var stride:float=cfg.stride/pixel_scale*(1.4 if charging else 1.0)
	var lift:float=cfg.lift/pixel_scale*(1.4 if charging else 1.0)
	for i in range(2):
		var rest: Array=cfg.legs[i]
		var hip:Vector2=_body_point(rest[0])
		var ankle:Vector2=rest[2]
		var t:=fposmod(phase+i*PI,TAU)/TAU
		var x:=lerpf(stride,-stride,t*2) if t<.5 else lerpf(-stride,stride,smoothstep(.5,1,t))
		var y:=0.0 if t<.5 else -lift*sin((t-.5)*TAU)
		var goal:=Vector2(rest[0].x+x,ankle.y+source.region_rect.end.y-float(cfg.soles[i])+y)
		var target:=ankle.lerp(goal,blend)
		var upper:float=rest[0].distance_to(rest[1])
		var lower:float=rest[1].distance_to(rest[2])
		var delta:=target-hip
		var d:=clampf(delta.length(),.001,upper+lower-.001)
		var axis:=delta.normalized()
		var along:float=(upper*upper-lower*lower+d*d)/(2*d)
		var bend:=sqrt(maxf(0,upper*upper-along*along))
		var knee:=hip+axis*along+Vector2(axis.y,-axis.x)*bend
		knee=(rest[1] as Vector2).lerp(knee,leg_blend)
		posed_legs.append([hip,knee,target])
		var a:float=(knee-hip).angle()-(rest[1]-rest[0]).angle()
		var b:float=(target-knee).angle()-(rest[2]-rest[1]).angle()
		if i==0:
			leg_angles.x=a;leg_angles.y=b
		else:
			leg_angles.z=a;leg_angles.w=b

func _sync_transform():
	transform=source.transform
	if source.flip_h:scale.x=-scale.x
	if source.flip_v:scale.y=-scale.y
	modulate=source.modulate

func mouth_global(source_uv: Vector2) -> Vector2:
	_sync_transform()
	var p:=source_uv*source.texture.get_size()
	var weight:=1-smoothstep(cfg.neck.y-50,cfg.neck.y+25,p.y)
	p=p.lerp(cfg.neck+(p-cfg.neck).rotated(head_angle),weight)
	return to_global(_body_point(p)-center)

func hand_global() -> Vector2:
	_sync_transform()
	var shoulder:Vector2=cfg.near[0]
	var elbow:Vector2=cfg.near[1]
	var hand:Vector2=cfg.near[3]
	var moved_elbow:=shoulder+(elbow-shoulder).rotated(arms.x)
	return to_global(_body_point(moved_elbow+(hand-elbow).rotated(arms.y))-center)
