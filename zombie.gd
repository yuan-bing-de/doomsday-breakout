extends CharacterBody2D

# ============================================================================
# zombie.gd —— 八种丧尸共用移动、受击和近战；变异能力由 zombie_mutation.gd 驱动
# ============================================================================
# 挂在 Zombie 场景（CharacterBody2D）上。具体属性由 main.gd 在生成时赋值。
#
# ★★ 你问的「血量」和「攻击间隔」到底在哪改 ★★
#   本文件下方的 max_health、attack_interval 只是给编辑器看的**占位默认值**，
#   改它们没有任何作用（每只丧尸生成时都会被 catalog 覆盖）！
#   ✅ 真正生效的位置：zombie_catalog.gd 第 3~12 行的 DEFINITIONS 表
#      · 血量       → 字段 max_health      （游荡者30 / 肥胖150 / 铁甲200）
#      · 攻击间隔   → 字段 attack_interval （单位秒，越大越慢；爆囊尸1.0最快，游荡者1.3）
#      · 伤害       → 字段 damage
#      · 移速       → 字段 speed
#      · 出现关卡   → 字段 unlock
#      改完直接运行游戏生效，不需要动本文件，也不需要动 main.gd。
#
# 你想改的地方：
#   - 丧尸贴图大小          → 看 ART_LAYOUT 的 height（可见高度）
#   - 血厚、速度、攻击间隔   → 在 zombie_catalog.gd 的 DEFINITIONS 里改
#   - 爬出地面的动画速度     → 看 _physics_process() 里的 220.0
#   - 步幅与挥爪动作         → 看 zombie_motion_profiles.gd 和 zombie_motion.gd
# ============================================================================

# ---- 这些属性由 main.gd 生成时赋值（@export 表示编辑器也能看到）----
# ⚠️⚠️ 重要：下面这些 @export 的默认值**只是占位，不是游戏实际数值**！
#    真实数值全部来自 zombie_catalog.gd 的 DEFINITIONS 表，由
#    main.gd 调 zombie_catalog.configure(z, type) 在刷怪时逐只赋值覆盖。
#    所以想改血量/攻击间隔，**不要改这里的默认数字（没用）**，
#    要去 zombie_catalog.gd 第 3~12 行改。
#    为什么用 @export：这样在 Godot 检查器里能直接看到当前这只丧尸的血量/移速等，方便调试。
const CATALOG = preload("res://zombie_catalog.gd")
const MUTATION = preload("res://zombie_mutation.gd")
const MUTANT_ART = preload("res://zombie_mutant_art.gd")
@export var zombie_type := "male"   # 种类键（male/female/fat/runner/...），决定用哪套数值和贴图
@export var melee_damage := 5       # 每次攻击的伤害值。★真实值在 zombie_catalog.gd 的 damage 字段
const MOTION=preload("res://zombie_motion.gd")
var locomotion: Node2D              # 动作系统实例（GPU 蒙皮走路/挥爪）
var _melee_elapsed := -1.0         # 近战攻击已过时间（-1 表示没在攻击中）
var _tongue_elapsed := -1.0        # 舌头攻击已过时间
var _spit_release := -1.0          # 吐酸液的发射时刻
var _melee_hit := false            # 本次攻击是否已命中过（防止一次挥爪多次扣血）
var _attack_facing := 1.0          # 攻击时朝向（1=右 -1=左）
var mutation: Node2D               # 变异技能实例（突进/吐酸/铁甲减伤等）
var rally_timer := 0.0             # 嚎叫者给周围丧尸加增益的持续计时

# ---- 下面五个是最常改的数值，含义逐个说清 ----
@export var texture_path := "res://art/zombie_male.png"  # 立绘贴图路径。★真实值在 catalog 的 texture
@export var max_health := 3         # 【血量】能挨几下打死。★真实值在 catalog 的 max_health（30/150/200 等）
@export var speed := 90.0           # 【移速】像素/秒。★真实值在 catalog 的 speed
@export var attack_type := "melee"  # 【攻击方式】melee 近战爪击 / ranged 舌头远程 / special 特殊
@export var melee_range := 72.0     # 【近战距离】双方中心最大距离（像素），够近才挥爪。★真实值在 catalog 的 melee_range
@export var ranged_range := 460.0   # 【远程距离】超出这个距离就不打。★真实值在 catalog 的 ranged_range
@export var attack_interval := 1.3  # 【攻击间隔】两次攻击之间最少隔几秒。★真实值在 catalog 的 attack_interval
	#   ↑ 数值越大攻击越慢。例如游荡者 1.3 秒一次，爆囊尸 1.0 秒一次。
	#     改攻击快慢就改 catalog 里的 attack_interval，不是改这里。
@export var mouth_uv := Vector2(0.84, 0.145)  # 嘴部在整张源图上的归一化 UV 坐标（吐酸液从这里喷出）；重制素材由 ART_LAYOUT 校准

# 新图保留透明画布，用 Sprite2D 区域显示内容，不改写 PNG 或破坏透明边缘。
# 高度沿用旧图可见高度 × 0.18，保持现有战斗体型、碰撞和刷怪数值。
const ART_LAYOUT := {
	"zombie_male.png": {"bounds":Rect2(271,77,495,1405), "height":178.92},
	"zombie_female.png": {"bounds":Rect2(252,83,537,1375), "height":158.4,
		"mouth":Vector2(724.0/1024.0,289.0/1536.0)},
	"zombie_fat.png": {"bounds":Rect2(194,60,668,1434), "height":174.06},
}

const GRAVITY := 1200.0
# STAND_Y = 丧尸「中心」的 Y 坐标。
# 丧尸贴图 180px 高（1.5 倍放大），centered=true → position 是中心点。
# 脚底要踩在路面落脚线(GROUND_LINE=478)，所以中心 = 478 - 90(半高) = 388
# ★ 如果改了 ground.gd 的 GROUND_LINE，这里也要跟着改：STAND_Y = GROUND_LINE - 90
const STAND_Y := 388.0
@onready var sprite: Sprite2D = $Sprite2D
@onready var attack_area: Area2D = $AttackArea   # 保留旧场景节点，不再作为伤害判据
const TONGUE_SCENE = preload("res://Tongue.tscn")

# ---- 运行时状态变量 ----
var health := 3
var player_ref: Node2D          # 记住玩家节点，省得每帧查找
var rising := true              # 是否还在「从地里爬出来」的状态
var rise_target_y := STAND_Y    # 爬出后要达到的 Y
var attack_timer := 0.0         # 攻击冷却计时
var dead := false              # 致命伤当场置位，死亡信号只能发射一次
var _hit_flash: Tween
var is_attacking := false       # 是否正在播放攻击动作
var stopped := false            # 游戏结束时设为 true，让丧尸停下
signal died(pos: Vector2)        # 丧尸死亡时发射，携带死亡位置（主场景用来发奖励）

# ---- 血条 + 受击伤害数字 ----
var _health_bar: Node2D          # 血条节点（代码绘制，z 高于精灵）
var _head_top: float = -90.0     # 贴图顶部相对丧尸中心的本地 Y（用于定位血条/数字）
var _dmg_seq := 0                # 连续命中计数：让 consecutive 数字错开，不完全叠在一起
var _dmg_labels: Array = []      # 挂在本节点下的伤害数字，死亡时转移到父节点让动画播完

# ---- 动画参数（程序化动画，不依赖走路帧贴图）----
# 像素画不能任意旋转，所以只用整像素位移 + 轻微缩放做动作
const SWAY_AMOUNT := 3.0        # 蹒跚走路：上下起伏幅度
const SWAY_SIDE := 2.4          # 蹒跚走路：左右摇摆幅度
const SWAY_FREQ := 4.0          # 摇晃频率（以速度 90 为基准，实际按自身速度缩放）
var sway_phase := 0.0           # 摇晃相位
# 旧贴图共用 0.18 缩放。重制图按 ART_LAYOUT 的可见高度对齐，
# 保持原先的体型比例；此常量仅用于其他自定义/旧贴图的回退。
const SPRITE_SCALE := 0.18
# 碰撞体高 180px 居中 → 脚底（碰撞体底边）在中心下方 90px（= GROUND_LINE 478 - STAND_Y 388）
const SOLE_OFFSET := 90.0
var sprite_base_scale := Vector2.ONE  # 按可见高度计算的基准缩放，攻击结束后回到此值
var sprite_ground_offset := 0.0       # 让可见脚底贴在碰撞体底边上

# ----------------------------------------------------------------------------
# _ready()：丧尸一生成就执行
# ----------------------------------------------------------------------------
func _ready():
	# 按可见内容缩放，忽略新原图四周的透明留白。
	if ResourceLoader.exists(texture_path):
		var tex := load(texture_path) as Texture2D
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var layout: Dictionary = ART_LAYOUT.get(texture_path.get_file(),MUTANT_ART.LAYOUT.get(texture_path.get_file(),{}))
		var display_size: Vector2 = tex.get_size()
		var art_scale := SPRITE_SCALE
		# 尺寸匹配才使用新图标定；其他自定义贴图仍保留旧加载方式。
		if not layout.is_empty() and tex.get_size() == Vector2(1024,1536):
			sprite.region_enabled = true
			sprite.region_rect = layout.bounds
			display_size = sprite.region_rect.size
			art_scale = float(layout.height)/display_size.y
			if layout.has("mouth"):
				mouth_uv = layout.mouth
		sprite_base_scale = Vector2(art_scale, art_scale)
		sprite.scale = sprite_base_scale
		# 可见脚底始终对齐碰撞体底边 +90，不把透明画布底边当成脚底。
		sprite_ground_offset = SOLE_OFFSET - display_size.y * art_scale / 2.0
		sprite.position.y = sprite_ground_offset
		_head_top = sprite.position.y - display_size.y * art_scale / 2.0
	else:
		var img: Image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.55, 0.55))
		sprite.texture = ImageTexture.create_from_image(img)
		_head_top = -24.0

	# 原立绘作为贴图与坐标基准，渲染交给共享 GPU 骨骼。
	var art_id := texture_path.get_file().get_basename().trim_prefix("zombie_")
	locomotion=MOTION.new()
	add_child(locomotion)
	if not locomotion.configure(sprite,art_id):
		locomotion.queue_free()
		locomotion=null

	# 血条：代码绘制的 Node2D，挂在丧尸节点下、位于头顶上方（z 高于精灵）
	_health_bar = Node2D.new()
	_health_bar.z_index = 12
	_health_bar.draw.connect(_draw_health_bar)
	add_child(_health_bar)

	# 找到玩家并加入 zombie 分组（player.gd 自动瞄准要用这个分组）
	player_ref = get_tree().get_first_node_in_group("player")
	add_to_group("zombies")
	health = max_health

	# 出生在地面下方 105px，然后慢慢爬上来
	rising = true
	global_position.y = STAND_Y + 105.0
	rise_target_y = STAND_Y

	# 关键：丧尸之间互不碰撞，才能重叠堆在一起围攻玩家。
	# 分层：layer1 = 地面；layer2 = 玩家；layer4 = 丧尸自己。
	# 丧尸 mask=1 → 只撞地面；不撞玩家、不撞彼此（修"踩尸堆走"叠罗汉 + 不被玩家顶飞）。
	# ⚠️ 子弹的 collision_mask 必须包含 layer4，舌头的 mask 必须包含 layer2（见 bullet.gd / tongue.gd）。
	collision_layer = 4
	collision_mask = 1

	# 旧碰撞圈有固定偏移且不读取 melee_range；改为统一距离判定。
	attack_area.monitoring = false
	attack_area.monitorable = false
	if zombie_type in CATALOG.MUTANTS:
		mutation = MUTATION.new()
		add_child(mutation)
		var badge := Label.new()
		badge.text = CATALOG.DEFINITIONS[zombie_type].name
		badge.position = Vector2(-65,_head_top-34)
		badge.size = Vector2(130,22)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.z_index = 12
		badge.add_theme_font_size_override("font_size",13)
		badge.add_theme_color_override("font_color",Color(1,.85,.6))
		badge.add_theme_color_override("font_outline_color",Color.BLACK)
		badge.add_theme_constant_override("outline_size",4)
		add_child(badge)

# 旧帧动画接口保留兼容；当前由 zombie_motion.gd 驱动连续骨骼动作。
# 如需恢复帧动画：把 4 帧放进 art/walk/<key>_0..3.png 并还原本函数。
func _load_walk_frames():
	pass

func _apply_walk_frame(idx: int):
	pass

# ----------------------------------------------------------------------------
# _physics_process()：每物理帧执行
# ----------------------------------------------------------------------------
func _physics_process(delta):
	if dead or stopped:
		velocity = Vector2.ZERO   # 游戏结束 → 不动
		return

	# ---- 从地里爬出来 ----
	if rising:
		# 每帧把 Y 往目标值移动一点（速度 220 像素/秒）
		global_position.y = move_toward(global_position.y, rise_target_y, 220.0 * delta)   # 爬出速度 220 像素/秒，把 y 平滑推向 STAND_Y
		if global_position.y <= rise_target_y + 0.5:
			global_position.y = rise_target_y
			rising = false   # 爬完了，开始正常行动
		return   # 爬出过程中不做事

	var old_x := global_position.x
	# ---- 重力 ----
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0

	if rally_timer > 0:
		rally_timer = maxf(0,rally_timer-delta)
		queue_redraw()
	if is_instance_valid(mutation) and mutation.tick(delta):
		if not dead:
			move_and_slide()
			_advance_motion(delta,absf(global_position.x-old_x))
		return

	# ---- 追玩家 ----
	if is_instance_valid(player_ref) and not player_ref.is_queued_for_deletion():
		var dir := int(sign(player_ref.global_position.x - global_position.x))  # 朝玩家方向的符号
		if is_attacking:
			velocity.x = dir * speed * rally_speed_multiplier() * 0.3   # 攻击动作期间移动放慢到 30% 速度，呈现「站定输出」的感觉
		else:
			velocity.x = dir * speed * rally_speed_multiplier()
		if not is_attacking:
			sprite.flip_h = dir < 0

		# 攻击冷却倒计时
		attack_timer -= delta
		if attack_type == "melee" and _player_in_melee_range() and attack_timer <= 0 and not is_attacking:
			_do_melee_attack()              # 近战：玩家在范围内就挥爪
		elif attack_type == "ranged" and attack_timer <= 0 and not is_attacking:
			var dist := global_position.distance_to(player_ref.global_position)
			if dist <= ranged_range:
				spawn_tongue()             # 远程：玩家在射程内就吐舌头
				attack_timer = attack_interval
	else:
		velocity.x = 0

	move_and_slide()

	# ---- 蹒跚走路的摇摆动画 ----
	_advance_motion(delta,absf(global_position.x-old_x))

# ----------------------------------------------------------------------------
# _update_sway()：丧尸走路时的摇晃（上下起伏 + 左右摇摆）
#   像素画不能用任意角度旋转，所以只做整像素位移，动作幅度小但连续
# ----------------------------------------------------------------------------
func _update_sway(delta):
	if sprite == null:
		return
	# 攻击动作期间由 tween 接管 sprite.position / scale，这里不插手
	if is_attacking:
		return

	if absf(velocity.x) > 5.0:
		# 摇晃频率跟着自身速度走：胖子丧尸慢，摇晃也慢
		sway_phase += delta * SWAY_FREQ * (absf(velocity.x) / 90.0)
		sprite.position.y = lerpf(sprite.position.y, sprite_ground_offset - absf(sin(sway_phase)) * SWAY_AMOUNT, 0.5)
		sprite.position.x = lerpf(sprite.position.x, sin(sway_phase * 0.5) * SWAY_SIDE, 0.4)
	else:
		# 站着不动时轻轻晃动（像在喘气）
		sway_phase += delta * SWAY_FREQ * 0.35
		sprite.position.y = lerpf(sprite.position.y, sprite_ground_offset + sin(sway_phase) * 0.9, 0.15)
		sprite.position.x = lerpf(sprite.position.x, 0.0, 0.2)

# ----------------------------------------------------------------------------
# _do_melee_attack()：抬臂蓄力、挥爪、收手。
#   0.24s 完成蓄力，0.38s 挥爪命中，0.65s 回到站姿。
#   姿态和伤害共享 _advance_motion() 的时间线，命中时再次检查距离与朝向。
# ----------------------------------------------------------------------------
func _do_melee_attack():
	if dead or stopped or rising or is_attacking or not _player_in_melee_range():
		return
	is_attacking=true
	attack_timer=attack_interval
	_melee_elapsed=0.0
	_melee_hit=false
	_attack_facing=1.0 if player_ref.global_position.x>=global_position.x else -1.0
	sprite.flip_h=_attack_facing<0

# ----------------------------------------------------------------------------
# _on_melee_impact()：挥爪到位后的命中回调，由攻击时间线触发一次。
#   参数：dir 攻击方向（1 右 / -1 左）
#   作用：结算对玩家的伤害 + 在命中点留下三道爪痕特效
# ----------------------------------------------------------------------------
func _on_melee_impact(dir: float):
	if dead or stopped:
		return
	if not is_instance_valid(player_ref):return
	# 手爪朝向在蓄力时锁定，跨到背后可躲开本次挥击。
	if (player_ref.global_position.x-global_position.x)*dir>=-8:
		_deal_melee_damage()
	_spawn_claw_slash(dir)

# ----------------------------------------------------------------------------
# _spawn_claw_slash()：挥爪命中时留下三道爪痕（纯代码绘制，不用贴图）
# ----------------------------------------------------------------------------
func _spawn_claw_slash(dir: float):
	if get_parent() == null:
		return

	var slash := Node2D.new()
	slash.z_index = 6                        # 盖在角色之上
	slash.global_position = locomotion.hand_global() if is_instance_valid(locomotion) else global_position + Vector2(dir * 44.0, -22.0)
	get_parent().add_child(slash)

	for i in range(3):
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(1.0, 0.96, 0.92, 0.92)
		line.antialiased = false             # 像素风：关抗锯齿，保持硬边
		var off_x := (i - 1) * 7.0
		line.points = PackedVector2Array([
			Vector2(off_x - dir * 8.0, -15.0),
			Vector2(off_x + dir * 8.0, 15.0),
		])
		slash.add_child(line)

	var tw := slash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(slash, "scale", Vector2(1.6, 1.6), 0.16)
	tw.tween_property(slash, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(slash.queue_free)

# 起手和命中使用同一判据；左右对称，玩家跳起或撤离范围即可躲开。
func _player_in_melee_range() -> bool:
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		return false
	if player_ref.get("dead") == true or melee_range <= 0.0:
		return false
	return global_position.distance_squared_to(player_ref.global_position) <= melee_range * melee_range

func _deal_melee_damage():
	if not dead and not stopped and not rising and _player_in_melee_range():
		player_ref.take_damage(roundi(melee_damage * (1.2 if rally_timer>0 else 1.0)))

# ----------------------------------------------------------------------------
# spawn_tongue()：女丧尸吐舌头（伸缩，不发射）
# 嘴部坐标包含贴图缩放、朝向翻转、贴底偏移与走路/攻击动画。
func get_tongue_origin() -> Vector2:
	if is_instance_valid(locomotion):
		return locomotion.mouth_global(mouth_uv)
	var rect := sprite.get_rect()
	var uv := mouth_uv
	if sprite.region_enabled:
		# mouth_uv 是整张 PNG 的 UV，先转换到当前可见区域，再应用镜像。
		uv = (mouth_uv * sprite.texture.get_size() - sprite.region_rect.position) / sprite.region_rect.size
	if sprite.flip_h:
		uv.x = 1.0 - uv.x
	if sprite.flip_v:
		uv.y = 1.0 - uv.y
	return sprite.to_global(rect.position + rect.size * uv)

# 舌头长度与方向都从嘴部计算，而不是从丧尸身体中心计算。
# ----------------------------------------------------------------------------
func spawn_tongue():
	if dead or stopped or rising or not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		return
	var facing_delta := player_ref.global_position.x - global_position.x
	if not is_zero_approx(facing_delta):
		sprite.flip_h = facing_delta < 0.0
	var origin := get_tongue_origin()
	var t := TONGUE_SCENE.instantiate()
	add_child(t)
	var tongue_len: float = min(origin.distance_to(player_ref.global_position), 280.0)
	var dir := (player_ref.global_position - origin).normalized()
	t.setup(dir, tongue_len, get_tongue_origin)

	# 完整前倾—吐舌—收势动作持续到舌头回收，嘴部锚点逐帧同步。
	is_attacking=true
	_tongue_elapsed=0.0

# ----------------------------------------------------------------------------
# take_damage()：先同步结算致命伤，受击闪红不再延迟死亡判断。
# ----------------------------------------------------------------------------
func take_damage(amount):
	if dead or is_queued_for_deletion() or amount <= 0:
		return
	health -= amount
	_spawn_damage_number(amount)
	if is_instance_valid(_health_bar):
		_health_bar.queue_redraw()
	if health <= 0:
		# 先置位再发信号，即使信号回调重入或同帧多段命中也只结算一次。
		dead = true
		stopped = true
		velocity = Vector2.ZERO
		set_physics_process(false)   # 关掉自身物理帧：死亡后不再移动/追击，同时避免死亡动画期间误触发逻辑
		remove_from_group("zombies")   # 死亡后立即移出 zombies 组：之后的手雷/导弹范围伤害不会再打到尸体，避免「尸体被二次炸」
		if _hit_flash != null and _hit_flash.is_valid():
			_hit_flash.kill()
		# 把还没播完的伤害数字转移到父节点，避免随本节点一起被释放
		for lbl in _dmg_labels:
			if is_instance_valid(lbl):
				var gp: Vector2 = lbl.global_position
				if get_parent() != null and is_instance_valid(get_parent()):
					lbl.reparent(get_parent())
					lbl.global_position = gp
		_dmg_labels.clear()
		died.emit(global_position)
		queue_free()
		return
	if _hit_flash != null and _hit_flash.is_valid():
		_hit_flash.kill()
	sprite.modulate = Color(1, 0.3, 0.3)
	# 绑定本节点的 Tween 会在节点释放时终止，不留下访问已释放 sprite 的协程。
	_hit_flash = create_tween()
	_hit_flash.tween_interval(0.08)
	_hit_flash.tween_property(sprite, "modulate", Color.WHITE, 0.0)

# ----------------------------------------------------------------------------
# _draw_health_bar()：头顶尖角血条（绿→黄→红，随血量变色）
#   挂在 _health_bar 节点的 draw 信号上；血量变化时 queue_redraw() 重画。
# ----------------------------------------------------------------------------
func _draw_health_bar() -> void:
	if _health_bar == null:
		return
	var w: float = 54.0
	var h: float = 7.0
	var x: float = -w / 2.0
	var y: float = _head_top - 12.0
	# 背景条（暗红半透明）
	_health_bar.draw_rect(Rect2(x, y, w, h), Color(0.1, 0.05, 0.05, 0.85))
	# 当前血量比例 + 颜色
	var ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var col: Color
	if ratio > 0.5:
		col = Color(0.30, 0.85, 0.30)      # 绿（健康）
	elif ratio > 0.25:
		col = Color(0.95, 0.85, 0.25)      # 黄（告警）
	else:
		col = Color(0.90, 0.25, 0.20)      # 红（濒死）
	var bw: float = w * ratio
	if bw > 0.5:
		_health_bar.draw_rect(Rect2(x, y, bw, h), col)
	# 黑色描边
	_health_bar.draw_rect(Rect2(x, y, w, h), Color(0.0, 0.0, 0.0, 0.9), false, 1.0)

# ----------------------------------------------------------------------------
# _spawn_damage_number()：在丧尸头顶上方弹出实时伤害数字（上浮 + 淡出）
#   数字挂在丧尸节点下 → 跟随丧尸（爬出/移动）；丧尸死亡时 reparent 到父节点
#   让动画播完，所以击杀的最后一击数字也不会随丧尸一起消失。
# ----------------------------------------------------------------------------
func _spawn_damage_number(amount: int) -> void:
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.z_index = 24
	var ls := LabelSettings.new()
	ls.font_size = 20
	ls.font_color = Color(1.0, 0.95, 0.40)      # 亮黄
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	ls.outline_size = 4
	lbl.label_settings = ls
	# 头顶上方；连续命中的数字按序号错开（水平 ±12px 一档 + 垂直两档），避免叠成一团
	_dmg_seq += 1
	var ox: float = randf_range(-6.0, 6.0) + float((_dmg_seq % 3) - 1) * 12.0
	var oy: float = -16.0 - float(_dmg_seq % 2) * 10.0
	# 挂在丧尸节点下 → 跟随丧尸（爬出/移动）；死亡时再 reparent 到父节点让动画播完
	add_child(lbl)
	lbl.global_position = Vector2(global_position.x + ox, global_position.y + _head_top + oy)
	_dmg_labels.append(lbl)
	var start := lbl.global_position
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position", start + Vector2(0.0, -34.0), 0.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(lbl.queue_free)

# 游戏结束时调用，让丧尸停下
func stop_moving():
	stopped = true

	if is_instance_valid(mutation):
		mutation.cancel()
	rally_timer = 0.0
	queue_redraw()

func rally_speed_multiplier() -> float:
	return 1.2 if rally_timer > 0 else 1.0

func apply_rally(duration: float):
	if dead or stopped or rising: return
	# 多个嚎叫者只刷新持续时间，不叠乘加速。
	rally_timer = maxf(rally_timer,duration)
	queue_redraw()

func take_projectile_damage(amount: int, direction: Vector2):
	if dead or stopped or amount<=0: return
	var facing := -1.0 if sprite.flip_h else 1.0
	if zombie_type=="armored" and direction.normalized().x*facing < -.2:
		amount = maxi(1,roundi(amount*.45))
		if is_instance_valid(mutation):
			mutation.armor_flash = .18
	take_damage(amount)

func _draw():
	if rally_timer>0 and not dead and not stopped:
		draw_set_transform(Vector2(0,87),0,Vector2(1,.3))
		draw_arc(Vector2.ZERO,32,0,TAU,32,Color(.8,.45,1,.85),3,true)


# 物理位移驱动步频；技能姿态直接读取其状态，不使用会越过死亡/暂停的动画协程。
func _advance_motion(delta: float, distance: float):
	var hit_this_frame := false
	var state := "walk" if distance>.001 else "idle"
	var progress := 0.0
	if _melee_elapsed>=0:
		_melee_elapsed=minf(_melee_elapsed+delta,MOTION.CLAW_DURATION)
		state="claw"
		progress=_melee_elapsed
		if not _melee_hit and _melee_elapsed>=MOTION.CLAW_HIT:
			_melee_hit=true
			hit_this_frame=true
	elif _tongue_elapsed>=0:
		_tongue_elapsed+=delta
		state="tongue"
		progress=_tongue_elapsed
	elif is_instance_valid(mutation) and mutation.state!="idle":
		state=mutation.state
		var durations:={"charge_windup":.65,"charge":.68,"recovery":.6,"spit_windup":.7,"fuse":1.2,"howl_windup":.9,"howl_wave":.55}
		progress=1-float(mutation.remaining)/float(durations.get(state,1))
	elif _spit_release>=0:
		_spit_release+=delta
		state="spit_release"
		progress=_spit_release
	if is_instance_valid(locomotion):
		locomotion.advance(delta,distance,state,progress)
	else:
		_update_sway(delta)
	if hit_this_frame:_on_melee_impact(_attack_facing)
	if _melee_elapsed>=MOTION.CLAW_DURATION:
		_melee_elapsed=-1.0
		is_attacking=false
	if _tongue_elapsed>=.55:
		_tongue_elapsed=-1.0
		is_attacking=false
	if _spit_release>=.3:_spit_release=-1.0

func start_spit_release():
	_spit_release=0.0
	if is_instance_valid(locomotion):
		locomotion.advance(0,0,"spit_release",0)
