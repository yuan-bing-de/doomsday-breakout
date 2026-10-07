extends Area2D

# ============================================================================
# bullet.gd —— 子弹脚本（玩家射击用）
# ============================================================================
# 挂在 Bullet 场景（Area2D + Sprite2D + CollisionShape2D）上。
# 由 player.gd 的 shoot() 生成。子弹是纯 Area2D（不做物理碰撞，只检测碰到谁）。
#
# 子弹外形：代码绘制像素风子弹（黄铜弹头 + 暗色尖端 + 曳光尾迹）
# 不同武器通过 bullet_size 控制大小，bullet_tracer 控制是否有曳光尾迹
# ============================================================================

var direction := Vector2.RIGHT   # 飞行方向（由 player.gd 设为指向目标）
const SPEED := 800.0             # 子弹速度（像素/秒）
var life := 2.5                 # 存活时间（秒）
var owner_node: Node = null      # 发射者（玩家），避免打到自己
var damage := 5                  # 子弹伤害（由当前武器决定）
var bullet_size: float = 1.0     # 子弹大小倍率（由武器决定）
var bullet_tracer: bool = false  # 是否有曳光尾迹（机枪=true）
var _spent := false

# ----------------------------------------------------------------------------
# _ready()：子弹生成时执行一次
#   作用：① 代码绘制子弹贴图并设好碰撞体 ② 设置碰撞层（只撞 layer1 地面 + layer4 丧尸）
#         ③ 把 Sprite 旋转到飞行方向 ④ 连接命中回调
# ----------------------------------------------------------------------------
func _ready():
	_draw_bullet()
	# 检测 layer1（地面/墙）+ layer4（丧尸）：
	# 丧尸在 zombie.gd 里被放到 layer4（彼此不碰撞），子弹必须把 layer4 包进来才打得中
	collision_mask = 1 | 4
	# 子弹朝向 = 飞行方向
	$Sprite2D.rotation = direction.angle()
	body_entered.connect(_on_body_entered)

# ----------------------------------------------------------------------------
# _draw_bullet()：用代码画一颗像素风子弹
# 布局：[曳光尾迹] [黄铜弹体] [暗色尖端▶]
# ----------------------------------------------------------------------------
func _draw_bullet():
	var sz: float = bullet_size
	# 各部分长度（按倍率缩放）
	var tip_len: int = max(3, int(4 * sz))
	var body_len: int = max(6, int(10 * sz))
	var trail_len: int = max(5, int(8 * sz)) if bullet_tracer else max(2, int(3 * sz))
	var w: int = tip_len + body_len + trail_len
	var h: int = max(4, int(6 * sz))

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # 透明背景

	# ---- 颜色 ----
	var tip_color := Color(0.35, 0.35, 0.4)       # 暗灰金属（弹尖）
	var tip_hi    := Color(0.55, 0.55, 0.6)       # 弹尖高光
	var body_color := Color(0.85, 0.7, 0.2)       # 黄铜金（弹体）
	var body_hi   := Color(1.0, 0.88, 0.35)       # 弹体高光（上沿）
	var body_lo   := Color(0.65, 0.5, 0.12)       # 弹体阴影（下沿）
	var trail_color := Color(1.0, 0.55, 0.12)     # 橙色曳光

	# ---- 画曳光尾迹（左侧，从透明渐变到亮）----
	for x in range(trail_len):
		var alpha: float = float(x + 1) / float(trail_len) * (0.7 if bullet_tracer else 0.4)
		for y in range(h):
			if y >= h / 4 and y < h * 3 / 4:
				img.set_pixel(x, y, Color(trail_color.r, trail_color.g, trail_color.b, alpha))

	# ---- 画弹体（中间，黄铜色 + 高光/阴影）----
	var body_start: int = trail_len
	for x in range(body_len):
		for y in range(h):
			if y < h / 4:
				img.set_pixel(body_start + x, y, body_hi)       # 上沿高光
			elif y >= h * 3 / 4:
				img.set_pixel(body_start + x, y, body_lo)       # 下沿阴影
			else:
				img.set_pixel(body_start + x, y, body_color)    # 主体

	# ---- 画弹尖（右侧，三角形渐缩）----
	var tip_start: int = trail_len + body_len
	for x in range(tip_len):
		var shrink: int = tip_len - 1 - x  # 从左到右逐渐缩窄
		for y in range(h):
			if y >= shrink and y < h - shrink:
				if y == shrink or y == h - shrink - 1:
					img.set_pixel(tip_start + x, y, tip_hi)     # 边缘高光
				else:
					img.set_pixel(tip_start + x, y, tip_color)  # 暗色填充

	$Sprite2D.texture = ImageTexture.create_from_image(img)
	$Sprite2D.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 碰撞体：和子弹同样大小
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	$CollisionShape2D.shape = shape

# ----------------------------------------------------------------------------
# _physics_process()：每物理帧推进子弹
#   参数：delta 帧间隔（秒）
#   作用：沿 direction 以固定 SPEED(800) 像素/秒移动；life 倒计时，归零即删除，
#         避免子弹飞出屏幕后仍以 Area2D 常驻内存造成性能浪费
# ----------------------------------------------------------------------------
func _physics_process(delta):
	position += direction * SPEED * delta   # 按方向飞（SPEED=800 像素/秒，匀速不衰减）
	life -= delta
	if life <= 0:
		queue_free()                        # 超时删除

func _on_body_entered(body):
	if _spent or is_queued_for_deletion():
		return
	if body == owner_node:
		return   # 不打发射者自己
	# queue_free 在帧末执行，多个重叠目标可能在同帧触发回调。
	_spent = true
	if body.has_method("take_projectile_damage"):
		body.take_projectile_damage(damage,direction)
	elif body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()             # 命中后子弹消失
