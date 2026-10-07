extends Control

# ============================================================================
# endless_panel.gd —— 无尽模式入口界面（从主界面底部「副本」打开）
# ----------------------------------------------------------------------------
# 定位：主界面底部第 5 个选框「副本」= 无尽模式（唯一副本玩法）。
# 展示内容：
#   · 历史最高波次（GameState.best_wave）
#   · 累计击杀 / 累计钻石（GameState.endless_kills / endless_diamond）
#   · 玩法说明（无限存活 / 线性缓增 / 每 5 波波次奖励 / 每 10 波 BOSS）
#   · 「开始无尽」按钮 → 置 GameState.endless_mode=true → 进 Main.tscn
# 规则说明不铺在界面上：这里只给「开始」和历史数据，详细规则见下面的「?」弹层。
# ============================================================================

const ENDLESS := preload("res://Endless.gd")   # 无尽模式数据源（波次曲线/奖励公式）

var _help_layer: Control = null                # 「?」规则详解弹层

# _ready()：铺满视口 → 构建界面。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

# _build()：全屏深色底 + 标题「无尽模式」+ 关闭按钮 + 中央卡片（历史数据 + 开始按钮）+ 「?」。
func _build():
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.74)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# ---- 标题 ----
	var title := Label.new()
	title.text = "无尽模式"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.40))
	title.position = Vector2(36, 24)
	overlay.add_child(title)

	var sub := Label.new()
	sub.text = "无限存活 · 越活越难 · 死了才算结束"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	sub.position = Vector2(36, 62)
	overlay.add_child(sub)

	# ---- 关闭按钮（锚右上角）----
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -56.0
	close_btn.offset_right = -12.0
	close_btn.offset_top = 18.0
	close_btn.offset_bottom = 58.0
	close_btn.pressed.connect(_close)
	overlay.add_child(close_btn)

	# ---- 「?」规则弹层入口（标题右侧）----
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 20)
	help_btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	help_btn.position = Vector2(178, 30)
	help_btn.size = Vector2(34, 34)
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0, 0, 0, 0)
	hs.border_color = Color(0.6, 0.62, 0.68, 0.9)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(999)
	help_btn.add_theme_stylebox_override("normal", hs)
	help_btn.add_theme_stylebox_override("hover", hs)
	help_btn.add_theme_stylebox_override("pressed", hs)
	help_btn.pressed.connect(_show_help)
	overlay.add_child(help_btn)

	# ---- 中央卡片：历史数据 ----
	var pw := 620.0
	var ph := 300.0
	var card := Panel.new()
	card.position = Vector2(vw / 2.0 - pw / 2.0, vh / 2.0 - ph / 2.0 - 20.0)
	card.size = Vector2(pw, ph)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.13, 0.12, 0.13, 0.97)
	cs.set_border_width_all(2)
	cs.border_color = Color(0.85, 0.35, 0.25, 0.9)
	cs.set_corner_radius_all(16)
	card.add_theme_stylebox_override("panel", cs)
	overlay.add_child(card)

	# 历史最高波次（大字，视觉焦点）
	var best_lbl := _mk_label(card, "历史最高", 24, Color(0.65, 0.68, 0.74))
	best_lbl.position = Vector2(0, 34)
	best_lbl.size = Vector2(pw, 24)
	best_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var best_val := _mk_label(card, "第 %d 波" % GameState.best_wave, 48, Color(1.0, 0.72, 0.32))
	best_val.position = Vector2(0, 62)
	best_val.size = Vector2(pw, 60)
	best_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 累计统计（两列）
	var stat_y := 150.0
	var col := (pw - 60.0) / 2.0
	_mk_stat(card, "累计击杀", str(GameState.endless_kills), Vector2(30, stat_y), col)
	_mk_stat(card, "累计钻石", str(GameState.endless_diamond), Vector2(30 + col, stat_y), col)

	# 「开始无尽」按钮（卡片底部）
	var go := Button.new()
	go.text = "开 始 无 尽"
	go.add_theme_font_size_override("font_size", 26)
	go.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	go.position = Vector2(pw / 2.0 - 140, ph - 78)
	go.size = Vector2(280, 56)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.45, 0.16, 0.12, 0.98)
	gs.set_border_width_all(2)
	gs.border_color = Color(1.0, 0.55, 0.35, 0.95)
	gs.set_corner_radius_all(12)
	go.add_theme_stylebox_override("normal", gs)
	var gsh := gs.duplicate()
	gsh.bg_color = Color(0.62, 0.24, 0.16, 1.0)
	go.add_theme_stylebox_override("hover", gsh)
	go.add_theme_stylebox_override("pressed", gs)
	go.pressed.connect(_start_endless)
	card.add_child(go)

# _mk_label(parent, text, size, color)：快速造一个 Label。
func _mk_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

# _mk_stat(parent, key, val, pos, w)：卡片里的一组「累计统计」（键 + 值，纵向）。
func _mk_stat(parent: Control, key: String, val: String, pos: Vector2, w: float):
	var k := _mk_label(parent, key, 16, Color(0.62, 0.66, 0.72))
	k.position = pos
	k.size = Vector2(w, 22)
	var v := _mk_label(parent, val, 28, Color(0.92, 0.94, 0.98))
	v.position = pos + Vector2(0, 24)
	v.size = Vector2(w, 36)

# _start_endless()：置无尽标记 → 切进 Main.tscn。main.gd 的 _ready 会据此接管逻辑。
func _start_endless():
	GameState.endless_mode = true
	get_tree().change_scene_to_file("res://Main.tscn")

# ============================================================================
#  「?」规则详解（UI 铁律：规则不常驻界面，放弹层）
# ============================================================================
# _show_help()：弹出规则详解层（不可重入，已开则忽略）。
func _show_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		return
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	_help_layer = Control.new()
	_help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_help_layer)

	var p := Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.99)
	p.add_theme_stylebox_override("panel", ps)
	_help_layer.add_child(p)

	var t := _mk_label(p, "无尽模式规则", 32, Color(1.0, 0.72, 0.40))
	t.position = Vector2(40, 26)
	t.size = Vector2(vw - 160, 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# 关闭
	var cb := Button.new()
	cb.text = "×"
	cb.add_theme_font_size_override("font_size", 28)
	cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cb.anchor_left = 1.0
	cb.anchor_right = 1.0
	cb.offset_left = -56.0
	cb.offset_right = -12.0
	cb.offset_top = 18.0
	cb.offset_bottom = 58.0
	cb.pressed.connect(_close_help)
	p.add_child(cb)

	# 正文（动态取 Endless 常量，改数值文案自动跟着变）
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(56, 104)
	vbox.size = Vector2(vw - 112, vh - 150)
	vbox.add_theme_constant_override("separation", 16)
	p.add_child(vbox)
	for line in _help_lines():
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(vw - 112, 0)
		vbox.add_child(l)

# _help_lines()：规则文案，数值全部来自 Endless.gd（改配置文案自动同步）。
func _help_lines() -> Array:
	return [
		"1. 玩法：没有时间限制，撑过一波又一波；死亡即本局结束。",
		"2. 波次推进：清空场上全部丧尸即进入下一波，刷怪更密、敌人更厚。",
		"3. 数量：第 %d 波 %d 只，之后每 %d 波 +1 只（基础上限 %d 只）；每 %d 波额外 +%d 只。" % [
			1, ENDLESS.BASE_START, ENDLESS.BASE_PER_WAVES, ENDLESS.BASE_MAX,
			ENDLESS.REWARD_WAVE, ENDLESS.EXTRA_PER_REWARD],
		"4. 难度线性缓增：刷怪间隔每波 ×%.2f（下限 %.2f 秒），敌人血量每波 ×%.2f。" % [
			ENDLESS.INTERVAL_DECAY, ENDLESS.INTERVAL_MIN, ENDLESS.HP_GROWTH],
		"5. 波次奖励：每 %d 波结算一次（活到就拿，不看击杀数）：金币、精魂、钻石。" % ENDLESS.REWARD_WAVE,
		"6. BOSS 波：每 %d 波出现一只 BOSS，血量随波次叠加。" % ENDLESS.BOSS_EVERY,
		"7. 结算：死亡时记录到达波次，历史最高波次会永久保存。",
	]

# _close_help()：销毁规则弹层。
func _close_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = null

# _on_overlay_input(event)：点遮罩关闭面板（仅左键按下，避免误触）。
func _on_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

# _close()：销毁面板自身。
func _close():
	queue_free()
