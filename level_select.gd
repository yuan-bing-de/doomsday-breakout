extends Control

# ============================================================================
# level_select.gd —— 关卡选择界面（按「世界」分页）
# ============================================================================
# 25 个关卡按世界分成 5 页，每页只显示该世界的 5 关，不再全部挤在一屏。
#   页内 5 个圆圈横向蜿蜒排布，圆圈放大到 R=56，间距宽松，下方标关卡名。
#   已解锁高亮（该关主题色描边），未解锁置灰加锁。
# 导航：底部「◀ / ▶」切换世界，中间 5 个指示点可直接跳转（未解锁的世界置灰）。
# 顶部地图名（MAP_NAME）之下显示当前世界名，配色用该世界首关的主题色。
# 主界面「开始游戏」→ 本界面；本界面右上角「开始」→ 进入 Main.tscn。
#
# ★ 选中关的记忆（2026-10-04 用户需求）：
#   进来时**保留用户上次选中的那一关**（读档 GameState.selected_stage），
#   不再每次都重置成「已解锁的最高关」。退到主界面、甚至完全退出游戏重进，
#   都停在最后浏览/选中的关卡。只有两种情况会改写它：
#     ① 通关新关卡 —— main.gd 调 GameState.unlock_stage() 推进到新解锁的关；
#     ② 用户在本界面点圆圈 / 切世界 / 点「开始」—— 走 set_selected_stage() 立即落盘。
#   写入统一走 GameState.set_selected_stage()，不要直接给 selected_stage 赋值（否则不落盘）。
# ============================================================================

const ENEMIES = preload("res://zombie_catalog.gd")
var _enemy_info: Label
var _enemy_dialog: AcceptDialog

const MAP_NAME := "末日突围战区"   # 整张关卡地图的名字（标题处显示）
# 总关卡数（实际 25 关，分 5 个世界各 5 关；每页只显示本世界的 5 个圆点）
const STAGE_COUNT := 25
const R := 56.0            # 圆圈半径（像素）—— 每页只有 5 关，可以放大

# 世界划分：与 Stages.gd 的 1-5 / 6-10 / 11-15 / 16-20 / 21-25 一一对应
const WORLDS := [
	{"name": "城市废墟", "from": 1,  "to": 5},
	{"name": "荒野要塞", "from": 6,  "to": 10},
	{"name": "沙漠废都", "from": 11, "to": 15},
	{"name": "熔岩末日", "from": 16, "to": 20},
	{"name": "极寒废土", "from": 21, "to": 25},
]

# 页内 5 关的圆心的视口相对坐标 (x比例, y比例)：一条左→右、上下轻微起伏的
# 蜿蜒路径。每页只有 5 个圈，x 间距 0.18、y 在 0.44/0.56 之间交替，
# 既保留路径观感，又不会像 25 关同屏时那样互相挤压。
const REL_POS := [
	Vector2(0.14, 0.44),
	Vector2(0.32, 0.56),
	Vector2(0.50, 0.44),
	Vector2(0.68, 0.56),
	Vector2(0.86, 0.44),
]

var _centers: Array[Vector2] = []   # 当前页各圆圈中心，_draw 画虚线/高亮用
var _selected := 1                   # 本界面当前选中的关卡号。_ready 时从 GameState.selected_stage
									#   读回（用户上次停留的关）；用户点圆圈/切世界时同步写回并落盘。
var _world := 0                     # 当前世界索引（0 = 世界1）。由 _selected 反推得出（world_of_stage），
									#   所以选中的关在哪，世界就自动跟到哪。
var _stage_layer: Control = null    # 关卡圆圈容器，切页时整层重建
var _world_title: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _dots: Array = []               # 世界指示点按钮

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 关卡选择属菜单界面，沿用「主界面音量」
	GameState.apply_ui_volume()
	# 保留用户上次选中的那一关（由存档 selected_stage 读回，GameState 已钳到已解锁范围）。
	# 旧逻辑在这里强制 selected_stage = unlocked_stage（每次进来都跳到最高关），
	# 已按需求移除：退到主界面或退出游戏重进，都停在用户最后浏览/选中的关卡；
	# 只有 main.gd 通关后调用 GameState.unlock_stage() 才会推进到新解锁的关卡。
	_selected = GameState.selected_stage
	_world = world_of_stage(_selected)
	_build_background()
	_build_title()
	_build_world_title()
	_build_enemy_intel()
	_build_stage_layer()
	_build_nav()
	_build_start_button()
	_build_back_button()
	queue_redraw()

# 关卡属于第几个世界（0 基）；越界回落到世界 1
static func world_of_stage(s: int) -> int:
	for i in range(WORLDS.size()):
		var w: Dictionary = WORLDS[i]
		if s >= int(w["from"]) and s <= int(w["to"]):
			return i
	return 0

# 该世界是否已开放（首关解锁即可进入）
# 判断第 i 个世界是否开放：只要该世界首关已解锁即视为可进入
func _world_unlocked(i: int) -> bool:
	var w: Dictionary = WORLDS[i]
	return GameState.stage_unlocked(int(w["from"]))

# ---------------------------------------------------------------------------
func _build_background():
	var bg := TextureRect.new()
	bg.anchor_left = 0.0; bg.anchor_top = 0.0; bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.offset_left = 0.0; bg.offset_top = 0.0; bg.offset_right = 0.0; bg.offset_bottom = 0.0
	if ResourceLoader.exists("res://art/hub_background.png"):
		bg.texture = load("res://art/hub_background.png")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		bg.color = Color(0.08, 0.08, 0.14, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -10
	add_child(bg)

func _build_title():
	var vw := get_viewport().get_visible_rect().size.x
	var t := Label.new()
	t.text = MAP_NAME
	t.add_theme_font_size_override("font_size", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(vw, 46)
	t.position = Vector2(0, 14)
	t.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	add_child(t)

# 当前世界名（配色取该世界首关的主题色）
func _build_world_title():
	var vw := get_viewport().get_visible_rect().size.x
	_world_title = Label.new()
	_world_title.add_theme_font_size_override("font_size", 24)
	_world_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_title.size = Vector2(vw, 34)
	_world_title.position = Vector2(0, 60)
	add_child(_world_title)

# 刷新当前世界标题文字（「世界 N · 名称」），并用该世界首关主题色着色
func _update_world_title():
	var w: Dictionary = WORLDS[_world]
	_world_title.text = "世界 %d · %s" % [_world + 1, String(w["name"])]
	_world_title.add_theme_color_override("font_color", Stages.accent(int(w["from"])))

# ---------------------------------------------------------------------------
# 关卡圆圈层：切页时整层清空重建
# ---------------------------------------------------------------------------
func _build_stage_layer():
	_stage_layer = Control.new()
	_stage_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage_layer)
	_rebuild_circles()

# 重建当前世界的关卡圆圈层：清空旧节点，按 REL_POS 摆放各关按钮与名称；已解锁可点、未解锁置灰加锁
func _rebuild_circles():
	for c in _stage_layer.get_children():
		_stage_layer.remove_child(c)
		c.queue_free()
	_centers.clear()

	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var w: Dictionary = WORLDS[_world]
	var first: int = int(w["from"])
	var last: int = mini(int(w["to"]), STAGE_COUNT)

	for i in range(last - first + 1):
		var s: int = first + i
		var rp: Vector2 = REL_POS[i]
		var cx: float = vw * rp.x
		var cy: float = vh * rp.y
		_centers.append(Vector2(cx, cy))

		var unlocked := GameState.stage_unlocked(s)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(R * 2, R * 2)
		btn.position = Vector2(cx - R, cy - R)
		btn.size = Vector2(R * 2, R * 2)
		btn.text = str(s) if unlocked else "🔒"
		btn.add_theme_font_size_override("font_size", 34)
		_apply_circle_style(btn, unlocked, Stages.accent(s))
		if unlocked:
			btn.pressed.connect(_on_circle_pressed.bind(s))
		else:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_layer.add_child(btn)

		# 圆圈下方标关卡名（已解锁用该关主题色，未解锁置灰）
		var name_lbl := Label.new()
		name_lbl.text = Stages.stage_name(s)
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.size = Vector2(200, 26)
		name_lbl.position = Vector2(cx - 100, cy + R + 10)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if unlocked:
			name_lbl.add_theme_color_override("font_color", Stages.accent(s))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_layer.add_child(name_lbl)

	_update_world_title()
	_update_enemy_intel()

# 给关卡圆圈按钮套用圆角样式：已解锁用主题色描边+绿底，未解锁灰底置灰且不可点
func _apply_circle_style(btn: Button, unlocked: bool, accent: Color = Color(0.4, 1.0, 0.6)):
	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 999
	normal.corner_radius_top_right = 999
	normal.corner_radius_bottom_left = 999
	normal.corner_radius_bottom_right = 999
	var hover := StyleBoxFlat.new()
	hover.corner_radius_top_left = 999
	hover.corner_radius_top_right = 999
	hover.corner_radius_bottom_left = 999
	hover.corner_radius_bottom_right = 999
	if unlocked:
		normal.bg_color = Color(0.16, 0.42, 0.26, 0.95)
		normal.border_color = accent
		normal.border_width_left = 4
		normal.border_width_top = 4
		normal.border_width_right = 4
		normal.border_width_bottom = 4
		hover.bg_color = Color(0.22, 0.55, 0.34, 0.98)
		hover.border_color = accent.lightened(0.3)
		hover.border_width_left = 4
		hover.border_width_top = 4
		hover.border_width_right = 4
		hover.border_width_bottom = 4
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		normal.bg_color = Color(0.12, 0.12, 0.14, 0.9)
		normal.border_color = Color(0.4, 0.4, 0.4, 0.7)
		normal.border_width_left = 2
		normal.border_width_top = 2
		normal.border_width_right = 2
		normal.border_width_bottom = 2
		hover = normal
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)

# 点击关卡圆圈：记录选中关 s 到 _selected 与 GameState.selected_stage，并请求重绘高亮环
func _on_circle_pressed(s: int):
	_selected = s
	# 走 set_selected_stage：立即写盘，这样退回主界面/退出游戏重进仍停在这一关
	GameState.set_selected_stage(s)
	_update_enemy_intel()
	queue_redraw()

# ---------------------------------------------------------------------------
# 底部导航：◀ / 世界指示点 / ▶
# ---------------------------------------------------------------------------
func _build_nav():
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var nav_y: float = vh - 76.0
	var mid_x: float = vw * 0.5

	_prev_btn = Button.new()
	_prev_btn.text = "◀ 上一世界"
	_prev_btn.add_theme_font_size_override("font_size", 17)
	_prev_btn.size = Vector2(140, 44)
	_prev_btn.position = Vector2(mid_x - 320, nav_y)
	_prev_btn.pressed.connect(func(): _goto_world(_world - 1))   # lambda 实时读当前世界，避免 bind 固化旧值
	add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = "下一世界 ▶"
	_next_btn.add_theme_font_size_override("font_size", 17)
	_next_btn.size = Vector2(140, 44)
	_next_btn.position = Vector2(mid_x + 180, nav_y)
	_next_btn.pressed.connect(func(): _goto_world(_world + 1))   # 同上，实时取 _world + 1
	add_child(_next_btn)

	# 世界指示点：一排小圆，点击直接跳转
	var dot_w := 54.0
	var total_w: float = dot_w * float(WORLDS.size())
	for i in range(WORLDS.size()):
		var d := Button.new()
		d.text = str(i + 1)
		d.add_theme_font_size_override("font_size", 16)
		d.size = Vector2(dot_w - 10, dot_w - 10)
		d.position = Vector2(mid_x - total_w * 0.5 + dot_w * float(i) + 5, nav_y + 2)
		d.pressed.connect(_goto_world.bind(i))
		add_child(d)
		_dots.append(d)

	_update_nav()

# 刷新底部导航：上一/下一世界按钮按边界禁用；世界指示点按当前/已解锁/未解锁三态着色，并禁用未解锁项
func _update_nav():
	_prev_btn.disabled = (_world <= 0)
	_next_btn.disabled = (_world >= WORLDS.size() - 1)
	for i in range(_dots.size()):
		var d: Button = _dots[i]
		var active: bool = (i == _world)
		var open: bool = _world_unlocked(i)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(999)
		if active:
			sb.bg_color = Color(0.30, 0.35, 0.42, 1.0)
			sb.border_color = Stages.accent(int(WORLDS[i]["from"]))
			sb.set_border_width_all(3)
		elif open:
			sb.bg_color = Color(0.18, 0.18, 0.20, 1.0)
			sb.border_color = Color(0.45, 0.45, 0.45, 0.6)
			sb.set_border_width_all(2)
		else:
			sb.bg_color = Color(0.12, 0.12, 0.14, 0.9)
			sb.border_color = Color(0.35, 0.35, 0.35, 0.5)
			sb.set_border_width_all(1)
		d.add_theme_stylebox_override("normal", sb)
		d.add_theme_stylebox_override("hover", sb)
		d.add_theme_stylebox_override("pressed", sb)
		d.add_theme_color_override("font_color", Color(1, 1, 1, 1 if (active or open) else 0.45))
		# 未解锁的世界不允许跳转
		d.disabled = not open

# 切换世界：重建圆圈、更新标题与导航，并选中该世界内已解锁的最高关
func _goto_world(i: int):
	var target: int = clampi(i, 0, WORLDS.size() - 1)
	if target == _world:
		return
	if not _world_unlocked(target):
		return
	_world = target
	var w: Dictionary = WORLDS[_world]
	var first: int = int(w["from"])
	var last: int = mini(int(w["to"]), STAGE_COUNT)
	var pick: int = first
	for s in range(first, last + 1):
		if GameState.stage_unlocked(s):
			pick = s
	_selected = pick
	# 切换世界同样视为「用户当前选中」，落盘保留（下次进界面仍停在这一关）
	GameState.set_selected_stage(pick)
	_rebuild_circles()
	_update_nav()
	queue_redraw()

# ---------------------------------------------------------------------------
func _build_start_button():
	var vw := get_viewport().get_visible_rect().size.x
	var btn := Button.new()
	btn.text = "开始"
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(180, 64)
	btn.position = Vector2(vw - 200, 16)
	btn.size = Vector2(180, 64)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.45, 0.25, 0.08, 0.95)
	normal.border_color = Color(1.0, 0.7, 0.2, 1)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.6, 0.34, 0.12, 1)
	hover.border_color = Color(1.0, 0.85, 0.4, 1)
	hover.border_width_left = 2
	hover.border_width_top = 2
	hover.border_width_right = 2
	hover.border_width_bottom = 2
	hover.corner_radius_top_left = 8
	hover.corner_radius_top_right = 8
	hover.corner_radius_bottom_left = 8
	hover.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(_on_start_pressed)
	add_child(btn)

# 「开始」按钮：把 _selected 写入 GameState.selected_stage，并切到 Main 战斗场景
func _on_start_pressed():
	# 同步选中关并落盘：万一玩家在这里直接进关、没点过圆圈，也要记住这一关
	GameState.set_selected_stage(_selected)
	get_tree().change_scene_to_file("res://Main.tscn")

func _build_back_button():
	var btn := Button.new()
	btn.text = "返回"
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(120, 46)
	btn.position = Vector2(20, 20)
	btn.pressed.connect(_on_back_pressed)
	add_child(btn)

# 「返回」按钮：回到主界面 Hub 场景
func _on_back_pressed():
	get_tree().change_scene_to_file("res://Hub.tscn")

# ---------------------------------------------------------------------------
# 画布层：当前世界内相邻关卡的弯曲虚线 + 选中圈的白色高亮环
# ---------------------------------------------------------------------------
func _draw():
	var w: Dictionary = WORLDS[_world]
	var first: int = int(w["from"])
	for i in range(_centers.size() - 1):
		var a := _centers[i]
		var b := _centers[i + 1]
		var col: Color
		if GameState.stage_unlocked(first + i + 1):
			col = Stages.accent(first + i + 1)   # 连线用下一关的主题色
			col.a = 0.85
		else:
			col = Color(0.4, 0.4, 0.4, 0.7)
		_draw_curved_dashed(a, b, col, 3.0, 14.0, 10.0)
	if _selected >= first and _selected <= mini(int(w["to"]), STAGE_COUNT):
		var idx: int = _selected - first
		if idx >= 0 and idx < _centers.size():
			draw_arc(_centers[idx], R + 9, 0, TAU, 48, Color(1.0, 1.0, 1.0, 0.95), 3.0)

# 沿二次贝塞尔曲线绘制弯曲虚线：把曲线采样成折线，再按弧长走 dash/gap
func _draw_curved_dashed(a: Vector2, b: Vector2, color: Color, width: float, dash_len: float, gap_len: float):
	var mid: Vector2 = (a + b) * 0.5
	var dir: Vector2 = (b - a).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var ctrl: Vector2 = mid + perp * 42.0   # 控制点外移 → 连线自然弯曲
	var pts := PackedVector2Array()
	var N: int = 48
	for s in range(N + 1):
		var t: float = float(s) / float(N)
		var p: Vector2 = (1.0 - t) * (1.0 - t) * a + 2.0 * (1.0 - t) * t * ctrl + t * t * b
		pts.append(p)
	var phase: float = 0.0
	var drawing: bool = true
	var cursor: Vector2 = pts[0]
	for i in range(1, pts.size()):
		var target: Vector2 = pts[i]
		var seg_len: float = target.distance_to(cursor)
		var traveled: float = 0.0
		while traveled < seg_len:
			var need: float = (dash_len if drawing else gap_len) - phase
			var step: float = min(seg_len - traveled, need)
			var nxt: Vector2 = cursor + (target - cursor).normalized() * step
			if drawing:
				draw_line(cursor, nxt, color, width)
			cursor = nxt
			traveled += step
			phase += step
			if phase >= (dash_len if drawing else gap_len) - 0.0001:
				phase = 0.0
				drawing = !drawing

func _build_enemy_intel():
	var vw := get_viewport_rect().size.x
	var panel := Panel.new()
	panel.position = Vector2(50,108)
	panel.size = Vector2(vw-100,92)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025,.04,.035,.90)
	style.border_color = Color(.4,.55,.43,.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	_enemy_info = Label.new()
	_enemy_info.position = Vector2(18,10)
	_enemy_info.size = Vector2(vw-268,76)
	_enemy_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_info.add_theme_font_size_override("font_size",16)
	panel.add_child(_enemy_info)
	var button := Button.new()
	button.text = "变异情报"
	button.position = Vector2(vw-234,24)
	button.size = Vector2(118,44)
	panel.add_child(button)
	_enemy_dialog = AcceptDialog.new()
	_enemy_dialog.title = "本关变异丧尸 · 技能与应对"
	_enemy_dialog.get_ok_button().text = "知道了"
	_enemy_dialog.min_size = Vector2i(900,360)
	_enemy_dialog.dialog_autowrap = true
	_enemy_dialog.get_label().add_theme_font_size_override("font_size",18)
	add_child(_enemy_dialog)
	button.pressed.connect(func():
		_enemy_dialog.dialog_text = ENEMIES.summary(_selected)+"\n\n"+ENEMIES.briefing(_selected)
		_enemy_dialog.popup_centered(Vector2i(900,360)))

func _update_enemy_intel():
	if is_instance_valid(_enemy_info):
		_enemy_info.text = ENEMIES.summary(_selected)
		var new_id: String = ENEMIES.new_at(_selected)
		if not new_id.is_empty():
			_enemy_info.text += "\n首次出现："+String(ENEMIES.DEFINITIONS[new_id].name)
