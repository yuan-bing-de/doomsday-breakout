extends Node2D

# ============================================================================
# coin.gd —— 掉落的金币（击杀丧尸后掉在路面上，需要玩家走过去捡）
# ============================================================================
# 生命周期：从丧尸位置弹起 → 受重力落到路面 → 停留 15 秒
#          → 闪烁 2 秒（闪烁期间仍可捡）→ 消失
# 捡取：玩家走到附近自动入账（GameState.add_gold），不是击杀即得。
# ============================================================================

const GRAVITY := 1500.0
const REST_Y := 466.0          # 金币静止时的世界 Y（路面顶边 478 再往上一点）
const LIFETIME := 15.0         # 正常停留时间（秒）
const BLINK_TIME := 2.0        # 之后闪烁时长
const BLINK_INTERVAL := 0.13   # 闪烁间隔（秒）
const PICKUP_DX := 60.0        # 捡取判定：水平距离
const PICKUP_DY := 120.0       # 捡取判定：垂直距离
const DISPLAY_W := 30.0        # 金币显示宽度（像素）

var value := 10                # 面值：100=金，10=银
var _spawn_pos := Vector2.ZERO
var _sprite: Sprite2D = null
var _vy := 0.0
var _vx := 0.0
var _landed := false
var _age := 0.0
var _blink_t := 0.0
var _collected := false

# 由 main.gd 在生成时调用：设置面值与出现位置
func setup(v: int, world_pos: Vector2):
	value = v
	_spawn_pos = world_pos

func _ready():
	global_position = _spawn_pos
	_vy = -randf_range(190.0, 270.0)      # 先向上弹起
	_vx = randf_range(-45.0, 45.0)        # 略微横向散开
	_sprite = Sprite2D.new()
	_sprite.texture = _coin_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tw: float = float(_sprite.texture.get_width())
	if tw > 0.0:
		var s := DISPLAY_W / tw
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)
	z_index = 1

# 金/银硬币贴图（读原始 PNG 字节，不依赖编辑器导入）；缺文件时画一个圆币兜底
func _coin_texture() -> Texture2D:
	var path := "res://art/coin_gold.png" if value >= GameState.GOLD_VALUE else "res://art/coin_silver.png"
	var t := GameState._tex_from_png(path)
	if t != null:
		return t
	var sz := 24
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (sz - 1) / 2.0
	var col := Color(1.0, 0.82, 0.12) if value >= GameState.GOLD_VALUE else Color(0.80, 0.83, 0.90)
	for y in range(sz):
		for x in range(sz):
			if Vector2(x - c, y - c).length() <= c:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _process(delta: float):
	if _collected:
		return

	# 掉落：受重力落到路面
	if not _landed:
		_vy += GRAVITY * delta
		global_position += Vector2(_vx, _vy) * delta
		if global_position.y >= REST_Y:
			global_position.y = REST_Y
			_vy = 0.0
			_vx = 0.0
			_landed = true

	# 捡取判定（闪烁期间同样有效）
	if _landed and _try_pickup():
		return

	# 超时：满 15 秒后闪烁 2 秒，然后消失
	_age += delta
	if _age >= LIFETIME:
		_blink_t += delta
		if _blink_t >= BLINK_INTERVAL:
			_blink_t -= BLINK_INTERVAL
			if _sprite != null:
				_sprite.visible = not _sprite.visible
		if _age >= LIFETIME + BLINK_TIME:
			queue_free()

# 捡取判定：取 group="player" 中第一个玩家，水平距≤PICKUP_DX 且垂直距≤PICKUP_DY 时调用 _collect 并返回 true
func _try_pickup() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	var p: Node2D = players[0]
	var d := p.global_position - global_position
	if absf(d.x) <= PICKUP_DX and absf(d.y) <= PICKUP_DY:
		_collect()
		return true
	return false

# 被玩家捡到：标记已收集、调用 GameState.add_gold 入账、记录拾取统计、飘「+N」文字后销毁自身
func _collect():
	_collected = true
	GameState.add_gold(value)
	GameState.record_coin_pickup()      # 任务/成就统计：累计拾取金币 + 每日「捡金币」进度
	_spawn_gain_text()
	queue_free()

# 捡到时飘一个「+N」
func _spawn_gain_text():
	var parent := get_parent()
	if parent == null:
		return
	var lbl := Label.new()
	lbl.text = "+%d" % value
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.25) if value >= GameState.GOLD_VALUE else Color(0.85, 0.88, 0.95))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = global_position + Vector2(-24, -30)
	lbl.size = Vector2(48, 20)
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(lbl.queue_free)
