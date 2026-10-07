extends Node2D

# ============================================================================
# drop_item.gd —— 掉落的物品（目前用于「腐肉」，击杀丧尸 10% 概率掉落）
# ============================================================================
# 机制与金币（coin.gd）一致：
#   从丧尸位置弹起 → 受重力落到路面（REST_Y）→ 停留 15 秒
#   → 闪烁 2 秒（闪烁期间仍可捡）→ 消失
# 捡取：玩家走到附近自动存入背包（GameState.add_item）。
# 通用实现：任何在 GameState.ITEM_DEFS 里登记过的物品都能用本脚本掉落。
# ============================================================================

const GRAVITY := 1500.0
const REST_Y := 466.0          # 静止时的世界 Y（路面顶边 478 再往上一点）
const LIFETIME := 15.0         # 正常停留时间（秒）
const BLINK_TIME := 2.0        # 之后闪烁时长
const BLINK_INTERVAL := 0.13   # 闪烁间隔（秒）
const PICKUP_DX := 60.0        # 捡取判定：水平距离
const PICKUP_DY := 120.0       # 捡取判定：垂直距离
const DISPLAY_W := 30.0        # 显示宽度（像素）——与金币同尺寸

var item_id := ""
var _spawn_pos := Vector2.ZERO
var _sprite: Sprite2D = null
var _vy := 0.0
var _vx := 0.0
var _bob_t := 0.0
var _landed := false
var _age := 0.0
var _blink_t := 0.0
var _collected := false
var _full_cd := 0.0        # 「背包已满」提示的冷却（防止每帧刷屏）

# 由 main.gd 在生成时调用：设置物品 id 与出现位置
func setup(id: String, world_pos: Vector2):
	item_id = id
	_spawn_pos = world_pos

func _ready():
	global_position = _spawn_pos
	_vy = -randf_range(190.0, 270.0)      # 先向上弹起
	_vx = randf_range(-45.0, 45.0)        # 略微横向散开
	_sprite = Sprite2D.new()
	_sprite.texture = GameState.item_icon_tex(item_id)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tw: float = float(_sprite.texture.get_width())
	if tw > 0.0:
		var s := DISPLAY_W / tw
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)
	z_index = 1

func _process(delta: float):
	if _collected:
		return
	if _full_cd > 0.0:
		_full_cd -= delta

	# 掉落：受重力落到路面
	if not _landed:
		_vy += GRAVITY * delta
		global_position += Vector2(_vx, _vy) * delta
		if global_position.y >= REST_Y:
			global_position.y = REST_Y
			_vy = 0.0
			_vx = 0.0
			_landed = true
	else:
		# 落地后轻微上下浮动（区别于金币，一眼能认出地上是物品）
		_bob_t += delta
		if _sprite != null:
			_sprite.position.y = sin(_bob_t * 3.4) * 2.0

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

# 捡取判定（与金币一致）：取 group="player" 第一个玩家，水平距≤PICKUP_DX 且垂直距≤PICKUP_DY 时调用 _collect
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

func _collect():
	# 背包满（放不下新物品）时：不消失，只飘字提示（有冷却），让玩家先清背包
	if not GameState.add_item(item_id, 1):
		if _full_cd <= 0.0:
			_full_cd = 1.5
			_spawn_gain_text("背包已满", Color(1.0, 0.45, 0.45))
		return
	_collected = true
	_spawn_gain_text("+1 %s" % GameState.item_name(item_id), Color(0.72, 0.88, 0.48))
	queue_free()

# 捡到时飘一行字
func _spawn_gain_text(text: String, col: Color):
	var parent := get_parent()
	if parent == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", col)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = global_position + Vector2(-48, -30)
	lbl.size = Vector2(96, 20)
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(lbl.queue_free)
