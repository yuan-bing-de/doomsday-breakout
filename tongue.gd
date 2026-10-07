extends Area2D

# ============================================================================
# tongue.gd —— 女丧尸的舌头（伸出 → 停留 → 缩回，不发射出去）
# ============================================================================
# 挂在 Tongue 场景（Area2D）上。由 zombie.gd 的 spawn_tongue() 调用 setup() 创建。
#
# 你想改的地方：
#   - 舌头颜色      → 看 setup() 里的 r_val / g_val / b_val 渐变
#   - 舌头粗细      → 看 setup() 里的 h（高度，当前 6px，尖端渐细）
#   - 伸缩快慢      → 看最底部 tween 的三个时间（0.15 / 0.25 / 0.15）
#   - 舌头伤害      → 看 _on_body_entered 里的 take_damage(5)
# ============================================================================

var direction := Vector2.RIGHT   # 舌头伸出的方向（指向玩家）
var max_length := 200.0          # 舌头最大长度
var has_dealt_damage := false    # 是否已经扣过血（防止同一根舌头每帧都扣）
var _origin_provider: Callable

# ----------------------------------------------------------------------------
# setup()：创建舌头时调用，传入方向和长度
#   参数：dir 舌头指向玩家的单位向量；length 舌头最大长度（像素，已在 zombie 里 clamp 到 280）
#   作用：定位到丧尸嘴部、旋转指向玩家、代码绘制渐变舌头贴图、设碰撞体(只撞 layer2 玩家)、
#         最后用 Tween 做「伸出→停留→缩回→删除」的伸缩动画
# ----------------------------------------------------------------------------
func setup(dir: Vector2, length: float, origin_provider: Callable = Callable()):
	direction = dir.normalized() if not dir.is_zero_approx() else Vector2.RIGHT
	# 距离不足 1 像素时 int(length) 会变成 0，Image 无法创建。
	max_length = clampf(length, 1.0, 280.0)
	has_dealt_damage = false
	_origin_provider = origin_provider

	# 根部取真实嘴部坐标；舌头保持世界像素长度，不继承精灵的 0.18 缩放。
	position = Vector2.ZERO
	_sync_origin()
	# Tween 在节点更新后执行，绘制前再同步一次，根部才会紧贴本帧的嘴部。
	RenderingServer.frame_pre_draw.connect(_sync_origin)
	rotation = direction.angle()   # 让整根舌头旋转到指向玩家

	# 用代码画一条细长舌头贴图（渐变色：根部深粉 → 尖端浅粉）
	var w: int = int(max_length)   # 宽度 = 舌头长度
	var h: int = 6                 # 与女丧尸嘴部匹配，避免舌头盖住整张脸
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x_idx in range(w):
		var ratio: float = float(x_idx) / float(w)   # 0=根部 1=尖端
		var r_val: float = lerp(0.75, 1.0, ratio)
		var g_val: float = lerp(0.15, 0.4, ratio)
		var b_val: float = lerp(0.3, 0.45, ratio)
		var edge_color: Color = Color(r_val, g_val, b_val)    # 上下边缘色
		var fill_color: Color = Color(r_val * 0.9, g_val * 0.85, b_val * 0.9)  # 中间填充色
		var half_height: float = lerpf(float(h) / 2.0, 1.0, ratio)
		for y_idx in range(h):
			var edge_distance := absf(float(y_idx) - float(h - 1) / 2.0)
			if edge_distance <= half_height:
				img.set_pixel(x_idx, y_idx, edge_color if edge_distance >= half_height - 1.0 else fill_color)
	$Sprite2D.texture = ImageTexture.create_from_image(img)
	$Sprite2D.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$Sprite2D.centered = false
	$Sprite2D.position = Vector2(0, -float(h) / 2.0)   # 让舌头在旋转中心上下对称

	# 碰撞体：一根和舌头一样大的矩形，用于检测打到玩家
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(w, h)
	$CollisionShape2D.shape = shape
	$CollisionShape2D.position = Vector2(float(w) / 2.0, 0)
	# 只检测玩家（玩家在 player.gd 里被放到 layer2）；丧尸彼此不撞，所以 mask 只放 2
	collision_mask = 2

	body_entered.connect(_on_body_entered)

	# ---- 伸缩动画 ----
	# 先缩成几乎看不见（scale.x=0.01），再伸出、停留、缩回、最后删除自己
	scale = Vector2(0.01, 1.0)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)    # 伸出（0.15秒）
	tw.tween_interval(0.25)                                       # 停留（0.25秒，期间检测碰撞）
	tw.tween_property(self, "scale", Vector2(0.01, 1.0), 0.15)   # 缩回（0.15秒）
	tw.tween_callback(queue_free)                                 # 删掉自己

func _sync_origin():
	if _origin_provider.is_valid():
		global_position = _origin_provider.call()

func _process(_delta: float):
	_sync_origin()

func _physics_process(_delta: float):
	_sync_origin()

# ----------------------------------------------------------------------------
# _on_body_entered()：舌头碰到玩家就扣血（一根舌头只扣一次）
# ----------------------------------------------------------------------------
func _on_body_entered(body):
	if body.is_in_group("player"):
		if not has_dealt_damage and body.has_method("take_damage"):
			body.take_damage(5)   # 舌头攻击扣 5 点
			has_dealt_damage = true
