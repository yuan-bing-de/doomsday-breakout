extends Control

# ============================================================================
# codex_panel.gd —— 丧尸图鉴（从主界面右侧「图鉴」小框打开）
# ----------------------------------------------------------------------------
# 左侧列表：全部 11 种丧尸（8 普通 + 3 BOSS），按「普通 / BOSS」分区。
#   · 已解锁 → 正常显示，可点击看详情
#   · 未解锁 → 整行置灰 + 蒙上灰色遮罩 + 锁图标 + 显示解锁关卡（第 N 关）
# 解锁判定 = 该丧尸的 unlock 关卡号 ≤ GameState.unlocked_stage（玩家已通关的最高关）
# 右侧详情：立绘、名称、生命、移速、攻击方式、攻击间隔、接触伤害、攻击距离、特殊技能。
#   未解锁时只显示名称 + 「第 N 关解锁」提示，不泄露数值。
# 数据源：zombie_catalog.gd（普通丧尸）+ boss_catalog.gd（BOSS），均为全局唯一定义源。
# ============================================================================

const CATALOG := preload("res://zombie_catalog.gd")      # 普通/变异丧尸定义
const BOSS_CATALOG := preload("res://boss_catalog.gd")   # BOSS 定义

# 列表项引用缓存：{id, is_boss, row, btn, icon, name, lock, tag}
var _rows: Array = []
var _sel_id := ""                 # 当前选中丧尸 id（空串=未选）
var _sel_is_boss := false
var _detail_layer: Control = null # 右侧详情容器（选中时重建）
var _codex_btn: Button = null     # 右侧「图鉴」小框（全屏面板打开时隐藏）

# ---------------------------------------------------------------------------
# _ready()：铺满视口 → 构建界面 → 默认选中第一只已解锁的丧尸
# ---------------------------------------------------------------------------
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# 默认选中：玩家当前关卡里出现的第一种丧尸，避免开局右侧空白
	for id in CATALOG.DEFINITIONS:
		if _is_unlocked(id, false):
			_select(id, false)
			break

# ============================================================================
#  解锁判定
# ============================================================================
# _unlock_stage(id, is_boss)：该丧尸的解锁关卡号。普通丧尸读 catalog 的 unlock；
# BOSS 读 boss_catalog 的 unlock（首次出现的那个世界末关）。
func _unlock_stage(id: String, is_boss: bool) -> int:
	if is_boss:
		return int(BOSS_CATALOG.DEFINITIONS.get(id, {}).get("unlock", 1))
	return int(CATALOG.DEFINITIONS.get(id, {}).get("unlock", 1))

# _is_unlocked(id, is_boss)：玩家已通关的最高关 ≥ 解锁关卡即视为已解锁。
func _is_unlocked(id: String, is_boss: bool) -> bool:
	return GameState.unlocked_stage >= _unlock_stage(id, is_boss)

# _entry(id, is_boss)：取该丧尸的定义字典。
func _entry(id: String, is_boss: bool) -> Dictionary:
	if is_boss:
		return BOSS_CATALOG.DEFINITIONS.get(id, {})
	return CATALOG.DEFINITIONS.get(id, {})

# ============================================================================
#  构建界面
# ============================================================================
# _build()：全屏深色底 + 标题「丧尸图鉴」+ 关闭按钮 + 左右分栏
# （左：可滚动列表；右：详情容器）。规则不做常驻说明，数值直接列在详情里。
func _build():
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.99)
	ps.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	# ---- 标题 ----
	var title := Label.new()
	title.text = "丧尸图鉴"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.position = Vector2(32, 20)
	panel.add_child(title)

	# ---- 关闭按钮（锚右上角，避免 expand 视口下跑出可视区）----
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -56.0
	close_btn.offset_right = -12.0
	close_btn.offset_top = 16.0
	close_btn.offset_bottom = 56.0
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	# ---- 进度文字（已解锁 / 总数）----
	var prog := Label.new()
	prog.add_theme_font_size_override("font_size", 15)
	prog.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
	prog.position = Vector2(160, 30)
	panel.add_child(prog)
	_prog_label = prog

	# ---- 左列表（ScrollContainer 装行）----
	var top := 70.0
	var list_w := 300.0
	var scroll := ScrollContainer.new()
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.anchor_right = 0.0
	scroll.offset_left = 32.0
	scroll.offset_right = 32.0 + list_w
	scroll.offset_top = top
	scroll.offset_bottom = -24.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_list_box = Control.new()
	scroll.add_child(_list_box)

	# 行高与分区标题高度
	var row_h := 74.0
	var head_h := 34.0
	# 总高：普通区(标题+8行) + BOSS区(标题+3行)
	var total_h := head_h + float(CATALOG.DEFINITIONS.size()) * row_h \
		+ head_h + float(BOSS_CATALOG.DEFINITIONS.size()) * row_h
	_list_box.custom_minimum_size = Vector2(list_w - 12.0, total_h)
	_list_box.size = Vector2(list_w - 12.0, total_h)

	# ---- 分区构建 ----
	var y := 0.0
	y = _build_section("普通丧尸", CATALOG.DEFINITIONS.keys(), false, y, row_h, head_h)
	y = _build_section("BOSS", BOSS_CATALOG.DEFINITIONS.keys(), true, y, row_h, head_h)

	# ---- 右侧详情（选中时填充）----
	_detail_layer = Control.new()
	_detail_layer.anchor_left = 0.0
	_detail_layer.anchor_right = 1.0
	_detail_layer.anchor_top = 0.0
	_detail_layer.anchor_bottom = 1.0
	_detail_layer.offset_left = 32.0 + list_w + 20.0
	_detail_layer.offset_right = -32.0
	_detail_layer.offset_top = top
	_detail_layer.offset_bottom = -24.0
	_detail_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_detail_layer)

	_refresh_progress()

var _list_box: Control = null
var _prog_label: Label = null

# _build_section(title, ids, is_boss, y, row_h, head_h)：在列表里建一个分区（标题 + 若干行），
# 返回下一行的 y 坐标。每行：图标 + 名称 + 解锁关卡提示（未解锁加灰罩 + 锁）。
func _build_section(title: String, ids: Array, is_boss: bool, y: float, row_h: float, head_h: float) -> float:
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35) if is_boss else Color(0.70, 0.80, 0.95))
	head.position = Vector2(6, y + 6)
	head.size = Vector2(240, 24)
	_list_box.add_child(head)
	y += head_h

	for id in ids:
		_build_row(String(id), is_boss, y, row_h)
		y += row_h
	return y

# _build_row(id, is_boss, y, row_h)：建一只丧尸的列表行。已解锁可点；未解锁置灰 + 灰罩 + 锁。
func _build_row(id: String, is_boss: bool, y: float, row_h: float):
	var cfg := _entry(id, is_boss)
	var unlocked := _is_unlocked(id, is_boss)

	var row := Panel.new()
	row.position = Vector2(0, y)
	row.size = Vector2(_list_box.size.x, row_h - 6.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.18, 0.95) if unlocked else Color(0.11, 0.11, 0.12, 0.95)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.35, 0.35, 0.40, 0.8)
	sb.set_corner_radius_all(8)
	row.add_theme_stylebox_override("panel", sb)
	_list_box.add_child(row)

	# 图标（未解锁时用 modulate 变灰）
	var icon := TextureRect.new()
	icon.texture = _icon_tex(id, is_boss)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(10, (row_h - 6.0 - 56.0) / 2.0)
	icon.size = Vector2(56, 56)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		icon.modulate = Color(0.42, 0.42, 0.46, 1.0)   # 未解锁图标变灰
	row.add_child(icon)

	# 名称 + 解锁关卡提示
	var nm := Label.new()
	nm.text = String(cfg.get("name", id))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color",
		Color(1, 1, 1, 0.95) if unlocked else Color(0.55, 0.55, 0.58, 1.0))
	nm.position = Vector2(76, 14)
	nm.size = Vector2(150, 24)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	var sub := Label.new()
	if unlocked:
		sub.text = "生命 %d · %s" % [int(cfg.get("max_health", 0)), _attack_label(String(cfg.get("attack_type", "melee")))]
	else:
		sub.text = "第 %d 关解锁" % _unlock_stage(id, is_boss)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color",
		Color(0.62, 0.66, 0.72, 1.0) if unlocked else Color(0.85, 0.55, 0.45, 1.0))
	sub.position = Vector2(76, 40)
	sub.size = Vector2(160, 20)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub)

	# 未解锁：整行灰色蒙罩 + 锁图标（盖在内容上，吃鼠标保证点不到）
	if not unlocked:
		var veil := ColorRect.new()
		veil.color = Color(0.05, 0.05, 0.06, 0.62)   # 半透明黑罩 = 蒙上灰色
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡点击
		row.add_child(veil)
		var lock := TextureRect.new()
		lock.texture = _lock_tex()
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.size = Vector2(30, 34)
		lock.position = Vector2(row.size.x - 40.0, (row.size.y - 34.0) / 2.0)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lock)

	# 点击层：已解锁才可点
	var hit := Button.new()
	hit.text = ""
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if unlocked:
		hit.pressed.connect(_select.bind(id, is_boss))
	else:
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 未解锁不可点
	row.add_child(hit)

	_rows.append({"id": id, "is_boss": is_boss, "row": row, "sb": sb, "btn": hit})

# _icon_tex(id, is_boss)：丧尸立绘贴图。缺文件返回 null（行内图标留空，不崩）。
func _icon_tex(id: String, is_boss: bool) -> Texture2D:
	var path := String(_entry(id, is_boss).get("texture", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var t := load(path)
	return t as Texture2D

# _lock_tex()：代码画一个锁图标（锁梁圆环 + 锁体 + 钥匙孔），静态缓存一次。
static var _lock_cache: ImageTexture = null
func _lock_tex() -> Texture2D:
	if _lock_cache != null:
		return _lock_cache
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.85, 0.85, 0.90, 0.95)
	var body := Rect2(s * 0.22, s * 0.44, s * 0.56, s * 0.38)
	for y in range(int(body.position.y), int(body.position.y + body.size.y)):
		for x in range(int(body.position.x), int(body.position.x + body.size.x)):
			img.set_pixel(x, y, col)
	var cx := s / 2.0
	var cy := s * 0.44
	var r_out := s * 0.22
	var r_in := s * 0.13
	for y in range(0, s):
		for x in range(0, s):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(Vector2(cx, cy))
			if d <= r_out and d >= r_in and p.y <= cy:
				img.set_pixel(x, y, col)
	# 钥匙孔
	var kx := int(cx)
	var ky := int(s * 0.58)
	for dy in range(0, int(s * 0.14)):
		for dx in range(-2, 3):
			if absi(dx) + dy <= 2:
				img.set_pixel(kx + dx, ky + dy, Color(0.12, 0.12, 0.14, 1.0))
	_lock_cache = ImageTexture.create_from_image(img)
	return _lock_cache

# ============================================================================
#  选中与详情
# ============================================================================
# _select(id, is_boss)：选中一只已解锁丧尸 → 重绘列表高亮 + 重建右侧详情。
func _select(id: String, is_boss: bool):
	_sel_id = id
	_sel_is_boss = is_boss
	_refresh_rows()
	_rebuild_detail()
	_refresh_progress()

# _refresh_rows()：按当前选中项刷新所有行的边框（选中金边，已解锁普通灰，未解锁暗红）。
func _refresh_rows():
	for r in _rows:
		var sb: StyleBoxFlat = r["sb"]
		var unlocked := _is_unlocked(r["id"], r["is_boss"])
		if r["id"] == _sel_id and r["is_boss"] == _sel_is_boss:
			sb.border_color = Color(1.0, 0.82, 0.25, 1.0)        # 选中：金边
			sb.border_width_left = 3; sb.border_width_top = 3
			sb.border_width_right = 3; sb.border_width_bottom = 3
		elif not unlocked:
			sb.border_color = Color(0.40, 0.30, 0.30, 0.7)        # 未解锁：暗边
			sb.border_width_left = 2; sb.border_width_top = 2
			sb.border_width_right = 2; sb.border_width_bottom = 2
		else:
			sb.border_color = Color(0.35, 0.35, 0.40, 0.8)
			sb.border_width_left = 2; sb.border_width_top = 2
			sb.border_width_right = 2; sb.border_width_bottom = 2

# _refresh_progress()：刷新顶部「已解锁 X / Y」进度文字。
func _refresh_progress():
	if _prog_label == null or not is_instance_valid(_prog_label):
		return
	var total := CATALOG.DEFINITIONS.size() + BOSS_CATALOG.DEFINITIONS.size()
	var got := 0
	for r in _rows:
		if _is_unlocked(r["id"], r["is_boss"]):
			got += 1
	_prog_label.text = "已解锁 %d / %d（通关第 %d 关解锁更多）" % [got, total, GameState.unlocked_stage]

# _rebuild_detail()：清空并重建右侧详情。未解锁只给名称 + 解锁关卡，不泄露数值。
func _rebuild_detail():
	for c in _detail_layer.get_children():
		_detail_layer.remove_child(c)
		c.queue_free()
	if _sel_id == "":
		return
	var cfg := _entry(_sel_id, _sel_is_boss)
	var unlocked := _is_unlocked(_sel_id, _sel_is_boss)
	# 容器尺寸：优先用实际的 size()，首帧布局未完成时退到按视口估算，避免除零/宽度为 0
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var w: float = _detail_layer.size.x
	var h: float = _detail_layer.size.y
	if w < 100.0:
		w = vw - 32.0 - 300.0 - 20.0 - 32.0
	if h < 100.0:
		h = vh - 70.0 - 24.0

	# ============================================================================
	# 左右分栏：左 42% 放大立绘（占满整栏高度），右 58% 放名称 + 数值 + 特殊技能。
	# 这样数值和技能都在右栏内纵向排布，不会被挤出屏幕下沿。
	# ============================================================================
	var col_w: float = w * 0.42
	var right_x: float = col_w + 28.0
	var right_w: float = w - right_x - 20.0

	# ---------- 左栏：立绘 ----------
	var art := TextureRect.new()
	art.texture = _icon_tex(_sel_id, _sel_is_boss)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(8, 0)
	art.size = Vector2(col_w - 16.0, h)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		art.modulate = Color(0.34, 0.34, 0.38, 1.0)
	_detail_layer.add_child(art)

	# 未解锁：左栏压一层灰 + 居中大锁，视觉上明确"未获得"
	if not unlocked:
		var veil := ColorRect.new()
		veil.color = Color(0.05, 0.05, 0.06, 0.55)
		veil.position = Vector2(8, 0)
		veil.size = Vector2(col_w - 16.0, h)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_layer.add_child(veil)
		var lock := TextureRect.new()
		lock.texture = _lock_tex()
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.size = Vector2(96, 108)
		lock.position = Vector2(col_w / 2.0 - 48.0, h / 2.0 - 54.0)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_layer.add_child(lock)

	# ---------- 右栏：名称 ----------
	var y := 4.0
	var nm := Label.new()
	nm.text = String(cfg.get("name", _sel_id))
	nm.add_theme_font_size_override("font_size", 30)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.98) if unlocked else Color(0.6, 0.6, 0.64))
	nm.position = Vector2(right_x, y)
	nm.size = Vector2(right_w, 40)
	_detail_layer.add_child(nm)
	y += 44.0

	# ---------- 右栏：未解锁 → 只提示解锁条件，直接结束 ----------
	if not unlocked:
		var tip := Label.new()
		tip.text = "尚未解锁 · 第 %d 关登场" % _unlock_stage(_sel_id, _sel_is_boss)
		tip.add_theme_font_size_override("font_size", 19)
		tip.add_theme_color_override("font_color", Color(0.90, 0.58, 0.45))
		tip.position = Vector2(right_x, y)
		tip.size = Vector2(right_w, 30)
		_detail_layer.add_child(tip)
		return

	# ---------- 右栏：数值表（两列：名称 / 数值）----------
	var rows := [
		["生命值", str(int(cfg.get("max_health", 0)))],
		["移动速度", "%.0f" % float(cfg.get("speed", 0.0))],
		["攻击方式", _attack_label(String(cfg.get("attack_type", "melee")))],
		["攻击间隔", "%.1f s" % float(cfg.get("attack_interval", 0.0))],
	]
	# BOSS 用 contact_damage 表示接触伤害；普通丧尸用 damage
	var dmg_val := int(cfg.get("contact_damage", cfg.get("damage", 0)))
	rows.append(["接触伤害", str(dmg_val)])
	# 攻击距离：近战显示 melee_range，远程显示 ranged_range，特殊/无距离显示"—"
	rows.append(["攻击距离", _range_text(cfg)])

	var rh := 40.0
	for i in range(rows.size()):
		var ry := y + float(i) * rh
		# 隔行淡底，读起来像表格
		if i % 2 == 0:
			var stripe := ColorRect.new()
			stripe.color = Color(1, 1, 1, 0.03)
			stripe.position = Vector2(right_x, ry)
			stripe.size = Vector2(right_w, rh)
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_detail_layer.add_child(stripe)
		var k := Label.new()
		k.text = String(rows[i][0])
		k.add_theme_font_size_override("font_size", 18)
		k.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
		k.position = Vector2(right_x + 12.0, ry)
		k.size = Vector2(160, rh)
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_detail_layer.add_child(k)
		var v := Label.new()
		v.text = String(rows[i][1])
		v.add_theme_font_size_override("font_size", 22)
		v.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
		v.position = Vector2(right_x + 172.0, ry)
		v.size = Vector2(right_w - 184.0, rh)
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_detail_layer.add_child(v)
	y += float(rows.size()) * rh + 14.0

	# ---- 特殊技能标题（右栏，与上方数值表同左边界）----
	var st := Label.new()
	st.text = "特殊技能"
	st.add_theme_font_size_override("font_size", 20)
	st.add_theme_color_override("font_color", Color(0.95, 0.72, 0.30))
	st.position = Vector2(right_x + 12.0, y)
	st.size = Vector2(right_w - 24.0, 28)
	_detail_layer.add_child(st)
	y += 32.0

	# ---- 特殊技能说明（tip 字段，右栏自动换行）----
	var tip := Label.new()
	tip.text = _skill_text(cfg, _sel_is_boss)
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.position = Vector2(right_x + 12.0, y)
	tip.size = Vector2(right_w - 24.0, 96.0)
	_detail_layer.add_child(tip)

# _attack_label(t)：攻击方式中文名。
func _attack_label(t: String) -> String:
	match t:
		"melee": return "近战"
		"ranged": return "远程"
		"special": return "特殊"
	return t

# _range_text(cfg)：攻击距离文案。近战取 melee_range，远程取 ranged_range，无距离返回"—"。
func _range_text(cfg: Dictionary) -> String:
	var mr := float(cfg.get("melee_range", 0.0))
	var rr := float(cfg.get("ranged_range", 0.0))
	if mr > 0.0:
		return "%.0f" % mr
	if rr > 0.0:
		return "%.0f" % rr
	return "—"

# _skill_text(cfg, is_boss)：技能说明文案。优先取 tip 字段；
# BOSS 若无 tip 则按 skill_type 生成一句（charge=冲锋 / slam=震地 / summon=召唤）。
func _skill_text(cfg: Dictionary, is_boss: bool) -> String:
	var tip := String(cfg.get("tip", ""))
	if tip != "":
		return tip
	if is_boss:
		match String(cfg.get("skill_type", "")):
			"charge": return "冲锋：短时间内高速突进撞击玩家，撞到即结算伤害。"
			"slam":  return "震地：砸地产生范围冲击波，命中范围内的玩家受到伤害。"
			"summon": return "召唤：定期召出小怪支援自身。"
	return "无特殊技能。"

# ============================================================================
#  关闭
# ============================================================================
# _on_overlay_input(event)：点遮罩（左键按下）关闭面板。
func _on_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

# _close()：销毁图鉴面板自身。
func _close():
	queue_free()
