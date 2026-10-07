extends Control

# ============================================================================
# task_panel.gd —— 任务面板（从主界面右侧「任务」小框打开）
# 两个选项卡：「每日任务」和「成就」。
#   每日任务：每天 3 个，显示进度；完成后「领取」按钮可点；3 个全完成可领额外奖励。
#   成就：跨天累计，分级制（Ⅰ Ⅱ Ⅲ…）——领取当前等级奖励后自动升到下一级，
#         目标更大、奖励更厚；全部等级领完显示「已达成」。
# 数据与逻辑全部在 GameState（tasks_changed 信号驱动刷新）。
# ============================================================================

const PW := 820.0              # 任务面板宽
const PH := 520.0              # 任务面板高
const ROW_H := 62.0            # 每日任务单行高
const ROW_GAP := 8.0           # 行间距
const ACH_EXTRA_H := 14.0      # 成就行比每日任务行多出的高度（容纳描述 + 奖励）
const CONTENT_TOP := 118.0     # 选项卡下方内容区起始 y

var _daily_box: Control = null       # 每日任务内容容器（放在 daily_scroll 内）
var _ach_box: Control = null         # 成就内容容器（放在 ach_scroll 内）
var _daily_scroll: ScrollContainer = null   # 每日任务滚动容器（滚轮滚动列表）
var _ach_scroll: ScrollContainer = null     # 成就滚动容器
var _tab_daily: Button = null        # 「每日任务」选项卡
var _tab_ach: Button = null          # 「成就」选项卡
var _daily_rows: Array = []    # 每行引用 {id, box, prog, bar, inner_w}（bar=填充条前景，inner_w=可填充宽）
var _ach_rows: Array = []      # 每行引用 {id, panel, name_lbl, desc_lbl, prog, bar, inner_w, reward_box, tier}
var _bonus_box: Control = null       # 额外奖励（每日全完成）的奖励胶囊
var _bonus_prog: Label = null        # 额外奖励进度文字（n/3）
var _bonus_bar: ColorRect = null    # 额外奖励填充条
var _bonus_inner_w := 0.0           # 额外奖励可填充宽度
var _cur_tab := "daily"             # 当前选项卡："daily" / "ach"
var _claim_all_btn: Button = null   # 右上角「一键领取」按钮（有关联奖励时高亮可点）

# _ready()：任务面板入口。铺满视口 → 构建界面 → 订阅 GameState.tasks_changed 信号（任务进度变化时刷新）
# → 首次刷新。任务数据与领取逻辑都在 GameState。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.tasks_changed.connect(_refresh)
	_refresh()

# _build()：构建任务面板——遮罩、居中面板、标题、关闭按钮、两个选项卡、两个 ScrollContainer
# （每日/成就各自独立，避免滚轮误退面板）。按 GameState 的任务数量计算内容总高并建好各行，
# 最后默认切到「每日任务」选项卡。
func _build():
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var panel := Panel.new()
	panel.position = Vector2((vw - PW) / 2.0, (vh - PH) / 2.0)
	panel.size = Vector2(PW, PH)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.12, 0.14, 0.97)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.4, 0.4, 0.4, 0.8)
	ps.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "任务"
	title.add_theme_font_size_override("font_size", 30)
	title.position = Vector2(24, 16)
	panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	close_btn.flat = true
	close_btn.position = Vector2(PW - 44, 8)
	close_btn.size = Vector2(36, 36)
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	# 一键领取按钮：位于右上角「×」正下方；3px 亮金粗边框 + 金色描边字，刻意做得醒目
	_claim_all_btn = Button.new()
	_claim_all_btn.text = "一键领取"
	_claim_all_btn.add_theme_font_size_override("font_size", 17)
	_claim_all_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.52))
	_claim_all_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_claim_all_btn.add_theme_constant_override("outline_size", 3)
	_claim_all_btn.position = Vector2(PW - 116, 50)
	_claim_all_btn.size = Vector2(108, 38)
	var cab := StyleBoxFlat.new()
	cab.bg_color = Color(0.24, 0.17, 0.05, 0.96)
	cab.set_border_width_all(3)                    # 粗金边，框得更明显
	cab.border_color = Color(1.0, 0.80, 0.32, 1.0)
	cab.set_corner_radius_all(10)
	_claim_all_btn.add_theme_stylebox_override("normal", cab)
	var cabh := cab.duplicate()
	cabh.bg_color = Color(0.40, 0.28, 0.10, 0.98)
	_claim_all_btn.add_theme_stylebox_override("hover", cabh)
	_claim_all_btn.add_theme_stylebox_override("pressed", cab)
	_claim_all_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_claim_all_btn.pressed.connect(_on_claim_all)
	panel.add_child(_claim_all_btn)

	# ---- 选项卡 ----
	_tab_daily = Button.new()
	_tab_daily.text = "每日任务"
	_tab_daily.add_theme_font_size_override("font_size", 18)
	_tab_daily.position = Vector2(24, 64)
	_tab_daily.size = Vector2(130, 40)
	_tab_daily.pressed.connect(_on_tab.bind("daily"))
	panel.add_child(_tab_daily)

	_tab_ach = Button.new()
	_tab_ach.text = "成就"
	_tab_ach.add_theme_font_size_override("font_size", 18)
	_tab_ach.position = Vector2(24 + 130, 64)
	_tab_ach.size = Vector2(130, 40)
	_tab_ach.pressed.connect(_on_tab.bind("ach"))
	panel.add_child(_tab_ach)

	# ---- 内容容器：每个 Tab 一个 ScrollContainer，让滚轮滚动列表而不是退出面板 ----
	var content_w := PW - 48.0
	var content_h := PH - CONTENT_TOP - 24.0

	_daily_scroll = ScrollContainer.new()
	_daily_scroll.position = Vector2(24, CONTENT_TOP)
	_daily_scroll.size = Vector2(content_w, content_h)
	_daily_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_daily_scroll)

	_daily_box = Control.new()
	# 每日：3 个任务 + 1 个额外奖励，按现有间距累加总高
	var daily_total_h: float = (GameState.DAILY_TASKS.size() + 1) * (ROW_H + ROW_GAP)
	# ScrollContainer 依据子节点的 custom_minimum_size 决定可滚动范围，
	# 只设 size 会在下一次布局时被容器改写。
	_daily_box.custom_minimum_size = Vector2(content_w, daily_total_h)
	_daily_box.size = Vector2(content_w, daily_total_h)
	_daily_scroll.add_child(_daily_box)

	_ach_scroll = ScrollContainer.new()
	_ach_scroll.position = Vector2(24, CONTENT_TOP)
	_ach_scroll.size = Vector2(content_w, content_h)
	_ach_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_ach_scroll)

	_ach_box = Control.new()
	# 成就：每行额外多 ACH_EXTRA_H 以容纳描述行
	var ach_total_h: float = GameState.ACHIEVEMENTS.size() * (ROW_H + ACH_EXTRA_H) \
		+ maxi(0, GameState.ACHIEVEMENTS.size() - 1) * ROW_GAP
	_ach_box.custom_minimum_size = Vector2(content_w, ach_total_h)
	_ach_box.size = Vector2(content_w, ach_total_h)
	_ach_scroll.add_child(_ach_box)

	# 每日任务行（3 个）+ 额外奖励行
	for i in range(GameState.DAILY_TASKS.size()):
		_build_daily_row(_daily_box, i, i * (ROW_H + ROW_GAP), content_w)
	_build_bonus_row(_daily_box, GameState.DAILY_TASKS.size() * (ROW_H + ROW_GAP), content_w)

	# 成就行
	for i in range(GameState.ACHIEVEMENTS.size()):
		_build_ach_row(_ach_box, i, i * (ROW_H + ACH_EXTRA_H + ROW_GAP), content_w)

	_on_tab("daily")

# ---- 行样式 ----
# _row_style()：返回每日/成就任务行通用的深色圆角边框样式。
func _row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 1.0)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.32, 0.32, 0.38, 0.7)
	sb.set_corner_radius_all(8)
	return sb

# ----------------------------------------------------------------------------
# 进度条：白色描边的「空心槽」+ 内部彩色填充条
#   · 槽底色比行背景略亮，加上 1px 白框 —— 0 进度时也能一眼看到条在哪
#   · 填充条内缩 BAR_BORDER，右端不会盖住白框
#   · 返回 {track, fg, inner_w}；inner_w 是可填充宽度（刷新时按比例乘）
# ----------------------------------------------------------------------------
const BAR_W := 400.0
const BAR_H := 14.0
const BAR_BORDER := 1.0
const BAR_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)   # 白色外框
const BAR_TRACK_COLOR := Color(0.10, 0.10, 0.13, 1.0)  # 槽底色（比行背景 0.09 略亮）

# _make_progress_bar(parent, pos, fg_color)：构造「白框空心槽 + 内部填充条」进度条。
# 返回 {track, fg, inner_w}；fg（ColorRect）宽度由刷新时按 inner_w*ratio 设置。详见上方注释块。
func _make_progress_bar(parent: Control, pos: Vector2, fg_color: Color) -> Dictionary:
	var track := Panel.new()
	track.position = pos
	track.size = Vector2(BAR_W, BAR_H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAR_TRACK_COLOR
	sb.border_color = BAR_BORDER_COLOR
	sb.set_border_width_all(int(BAR_BORDER))
	sb.set_corner_radius_all(3)
	track.add_theme_stylebox_override("panel", sb)
	parent.add_child(track)

	var fg := ColorRect.new()
	fg.color = fg_color
	fg.position = Vector2(BAR_BORDER, BAR_BORDER)
	fg.size = Vector2(0, BAR_H - BAR_BORDER * 2.0)
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fg)

	return {"track": track, "fg": fg, "inner_w": BAR_W - BAR_BORDER * 2.0}

# ----------------------------------------------------------------------------
# 奖励「胶囊」：和主界面金币/钻石 HUD 同一套画法（圆角描边底框 + 图标 + 数字）。
#   整块可点击领取；未达成 / 已领取置灰，已达成为高亮。
# ----------------------------------------------------------------------------
const REWARD_PILL_W := 112.0
const REWARD_PILL_GAP := 8.0
const REWARD_BOX_W := 240.0
const REWARD_BOX_H := 36.0
const REWARD_STATE_LOCKED := 0     # 未达到要求
const REWARD_STATE_READY := 1      # 已达成待领取（高亮）
const REWARD_STATE_CLAIMED := 2    # 已领取（置灰）

# _make_reward_box(parent, gold, diamond, pos, claim_cb)：构造奖励胶囊组（金币/钻石各一胶囊）。
# 整块可点，点击触发 claim_cb 领取；胶囊引用存 meta("pills") 供 _apply_reward_state 改外观。详见上方注释块。
func _make_reward_box(parent: Control, gold: int, diamond: int, pos: Vector2, claim_cb: Callable) -> Control:
	var box := Control.new()
	box.position = pos
	box.size = Vector2(REWARD_BOX_W, REWARD_BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击，避免冒泡到遮罩把面板关掉
	parent.add_child(box)

	var defs: Array = []
	if gold > 0:
		defs.append({"tex": GameState.gold_icon_tex(), "value": gold, "border": Color(0.95, 0.78, 0.25, 1.0)})
	if diamond > 0:
		defs.append({"tex": GameState.diamond_icon_tex(), "value": diamond, "border": Color(0.88, 0.32, 0.36, 1.0)})

	var total := defs.size() * REWARD_PILL_W + maxi(0, defs.size() - 1) * REWARD_PILL_GAP
	var x := REWARD_BOX_W - total
	var pills: Array = []
	for d in defs:
		var pill := PanelContainer.new()
		pill.position = Vector2(x, 0)
		pill.size = Vector2(REWARD_PILL_W, REWARD_BOX_H)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.border_color = d["border"]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(18)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		pill.add_theme_stylebox_override("panel", sb)
		box.add_child(pill)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(hb)

		var icon := TextureRect.new()
		icon.texture = d["tex"]
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)

		var lb := Label.new()
		lb.text = str(d["value"])
		lb.add_theme_font_size_override("font_size", 18)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lb)

		pills.append({"pill": pill, "icon": icon, "label": lb, "border": d["border"]})
		x += REWARD_PILL_W + REWARD_PILL_GAP

	box.set_meta("pills", pills)
	box.gui_input.connect(_on_reward_box_input.bind(claim_cb))
	return box

# _on_reward_box_input(event, claim_cb)：奖励胶囊的点击回调。左键按下→调用 claim_cb 领取，
# 并 set_input_as_handled 防止冒泡到遮罩误关面板。
func _on_reward_box_input(event: InputEvent, claim_cb: Callable):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	claim_cb.call()
	if is_inside_tree():
		get_viewport().set_input_as_handled()

# state: 0 未达成 / 1 可领取 / 2 已领取
# _apply_reward_state(box, state)：按状态改奖励胶囊外观——可领取高亮金边、其余置灰，
# 并切换鼠标手型光标。
func _apply_reward_state(box: Control, state: int):
	if box == null:
		return
	var gray_border := Color(0.42, 0.42, 0.46, 0.9)
	var gray_text := Color(0.58, 0.58, 0.62, 0.95)
	var pills: Array = box.get_meta("pills", [])
	for p in pills:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(18)
		sb.set_border_width_all(2)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		if state == REWARD_STATE_READY:
			sb.bg_color = Color(0.16, 0.13, 0.04, 0.85)
			sb.border_color = p["border"]
			p["icon"].modulate = Color(1, 1, 1, 1)
			p["label"].add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
		else:
			sb.bg_color = Color(0.07, 0.07, 0.08, 0.75)
			sb.border_color = gray_border
			p["icon"].modulate = Color(0.5, 0.5, 0.52, 0.9)
			p["label"].add_theme_color_override("font_color", gray_text)
		p["pill"].add_theme_stylebox_override("panel", sb)
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if state == REWARD_STATE_READY else Control.CURSOR_ARROW

# _build_daily_row(parent, idx, y, w)：构建第 idx 条每日任务行——任务名、进度条+数值、右侧奖励胶囊
# （整块可点领取）。引用存入 _daily_rows。
func _build_daily_row(parent: Control, idx: int, y: float, w: float):
	var p := Panel.new()
	p.position = Vector2(0, y)
	p.size = Vector2(w, ROW_H)
	p.add_theme_stylebox_override("panel", _row_style())
	parent.add_child(p)

	# 横向排开：任务名（左）→ 进度条+数值（第二行）→ 奖励胶囊（最右，整块可点领取）。
	var nm := Label.new()
	nm.text = GameState.DAILY_TASKS[idx]["name"]
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.position = Vector2(18, 6)
	nm.size = Vector2(480, 26)
	p.add_child(nm)

	# 进度条（白框槽 + 绿色填充）
	var bar := _make_progress_bar(p, Vector2(18, 40), Color(0.45, 0.85, 0.55, 0.95))
	var pgt := Label.new()
	pgt.add_theme_font_size_override("font_size", 15)
	pgt.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	pgt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pgt.position = Vector2(426, 34)
	pgt.size = Vector2(80, 24)
	p.add_child(pgt)

	var id: String = GameState.DAILY_TASKS[idx]["id"]
	var reward: Dictionary = GameState.DAILY_TASKS[idx]
	var box := _make_reward_box(p, int(reward.get("reward_gold", 0)), int(reward.get("reward_diamond", 0)),
		Vector2(w - 18.0 - REWARD_BOX_W, 13.0), _on_claim_daily.bind(id))
	_daily_rows.append({"id": id, "box": box, "prog": pgt, "bar": bar["fg"], "inner_w": bar["inner_w"]})

# _build_bonus_row(parent, y, w)：构建「全部完成·额外奖励」行（金色高亮），含进度条与奖励胶囊，
# 引用存 _bonus_bar/_bonus_prog/_bonus_box，由 _refresh 更新。
func _build_bonus_row(parent: Control, y: float, w: float):
	var p := Panel.new()
	p.position = Vector2(0, y)
	p.size = Vector2(w, ROW_H)
	var sb := _row_style()
	sb.bg_color = Color(0.16, 0.12, 0.06, 1.0)
	sb.border_color = Color(0.75, 0.55, 0.2, 0.85)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)

	var nm := Label.new()
	nm.text = "全部完成 · 额外奖励"
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.position = Vector2(18, 6)
	nm.size = Vector2(480, 26)
	p.add_child(nm)

	# 额外奖励行同样用进度条 + 奖励胶囊，与上面三行完全一致。
	var bbar := _make_progress_bar(p, Vector2(18, 40), Color(0.95, 0.75, 0.25, 0.95))
	_bonus_bar = bbar["fg"]
	_bonus_inner_w = bbar["inner_w"]

	_bonus_prog = Label.new()
	_bonus_prog.add_theme_font_size_override("font_size", 15)
	_bonus_prog.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_bonus_prog.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bonus_prog.position = Vector2(426, 34)
	_bonus_prog.size = Vector2(80, 24)
	p.add_child(_bonus_prog)

	_bonus_box = _make_reward_box(p, int(GameState.DAILY_BONUS["reward_gold"]), int(GameState.DAILY_BONUS["reward_diamond"]),
		Vector2(w - 18.0 - REWARD_BOX_W, 13.0), _on_claim_bonus)

# _build_ach_row(parent, idx, y, w)：构建第 idx 条成就行骨架（比每日行高，容纳描述+奖励）。
# 标题/描述/进度/奖励胶囊内容由 _update_ach_row 按当前等级填充；tier 初始 -1 触发首次填充。
func _build_ach_row(parent: Control, idx: int, y: float, w: float):
	var p := Panel.new()
	p.position = Vector2(0, y)
	p.size = Vector2(w, ROW_H + ACH_EXTRA_H)
	p.add_theme_stylebox_override("panel", _row_style())
	parent.add_child(p)

	# 分级成就行：称号/描述/奖励随等级变化，具体内容由 _update_ach_row() 按
	# 当前等级填充（初始 tier=-1 触发首次填充）。
	var nm := Label.new()
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.position = Vector2(18, 6)
	nm.size = Vector2(480, 22)
	p.add_child(nm)

	var ds := Label.new()
	ds.add_theme_font_size_override("font_size", 13)
	ds.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	ds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ds.position = Vector2(18, 30)
	ds.size = Vector2(480, 18)
	p.add_child(ds)

	# 进度条（白框槽 + 绿色填充）
	var bar := _make_progress_bar(p, Vector2(18, 54), Color(0.45, 0.85, 0.55, 0.95))
	var pgt := Label.new()
	pgt.add_theme_font_size_override("font_size", 15)
	pgt.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	pgt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pgt.position = Vector2(426, 48)
	pgt.size = Vector2(80, 24)
	p.add_child(pgt)

	var id: String = GameState.ACHIEVEMENTS[idx]["id"]
	_ach_rows.append({"id": id, "panel": p, "name_lbl": nm, "desc_lbl": ds,
		"prog": pgt, "bar": bar["fg"], "inner_w": bar["inner_w"],
		"reward_box": null, "tier": -1})

# 罗马数字（等级角标）：把等级号转成 Ⅰ/Ⅱ/Ⅲ… 显示。
func _roman(n: int) -> String:
	var romans := ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ"]
	return romans[clampi(n - 1, 0, romans.size() - 1)] if n >= 1 else ""

# 按当前等级刷新一行分级成就（称号/描述/进度/奖励胶囊；等级变了就重建奖励胶囊）。
# 已达成全部等级→满条+「已达成」；当前等级可领取→高亮；否则显示进度与锁定态。
func _update_ach_row(r: Dictionary):
	var id: String = r["id"]
	var finished := GameState.ach_finished(id)
	var tier_no := GameState.ach_claimed_tier(id) + (0 if finished else 1)   # 显示用等级号
	var tname: String = GameState.ach_tier_name(id)
	var desc: String = GameState.ach_desc(id)
	if finished:
		desc = "已达成全部等级，感谢你在末日里的坚持！"

	# 等级变化（或首次）→ 更新称号/描述并重建奖励胶囊
	if int(r["tier"]) != tier_no or r["reward_box"] == null or not is_instance_valid(r["reward_box"]):
		r["tier"] = tier_no
		var tier_gold := 0
		var tier_diamond := 0
		if GameState.ach_claimed_tier(id) > 0 or not finished:
			var idx := mini(GameState.ach_claimed_tier(id), GameState.ach_tier_count(id) - 1)
			var tiers: Array = GameState._ach_def(id)["tiers"]
			tier_gold = int(tiers[idx]["reward_gold"])
			tier_diamond = int(tiers[idx]["reward_diamond"])
		r["name_lbl"].text = "%s %s" % [tname, _roman(tier_no)]
		r["desc_lbl"].text = desc
		if finished:
			r["name_lbl"].add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
		else:
			r["name_lbl"].add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		if r["reward_box"] != null and is_instance_valid(r["reward_box"]):
			r["reward_box"].queue_free()
		r["reward_box"] = _make_reward_box(r["panel"], tier_gold, tier_diamond,
			Vector2(r["panel"].size.x - 18.0 - REWARD_BOX_W, 20.0), _on_claim_ach.bind(id))

	# 进度条与数值
	var cur := GameState.ach_progress(id)
	var tgt := maxi(1, GameState.ach_target(id))
	if finished:
		cur = tgt   # 全部领完 → 满条
	r["prog"].text = "%d/%d" % [cur, tgt]
	var ratio := clampf(float(cur) / float(tgt), 0.0, 1.0)
	r["bar"].size = Vector2(r["inner_w"] * ratio, r["bar"].size.y)

	# 奖励胶囊状态
	var ast := REWARD_STATE_LOCKED
	if finished:
		ast = REWARD_STATE_CLAIMED
	elif GameState.ach_reached(id):
		ast = REWARD_STATE_READY
	_apply_reward_state(r["reward_box"], ast)

# _on_overlay_input(event)：点遮罩（左键按下）关闭面板；滚轮等其它按键交给 ScrollContainer 滚动。
func _on_overlay_input(event: InputEvent):
	# 只对左键按下关闭面板；滚轮等其它按键交给 ScrollContainer 处理滚动。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

# _close()：销毁任务面板自身（queue_free）。
func _close():
	queue_free()

# _on_tab(tab)：切换选项卡。tab="daily"/"ach"，切换两个 ScrollContainer 与内容容器可见性，
# 并重设两个选项卡的样式（选中高亮）。
func _on_tab(tab: String):
	_cur_tab = tab
	# 必须切换 ScrollContainer 本身的可见性，否则成就 Tab 会一直被隐藏的滚动容器挡住。
	_daily_scroll.visible = (tab == "daily")
	_ach_scroll.visible = (tab == "ach")
	_daily_box.visible = (tab == "daily")
	_ach_box.visible = (tab == "ach")
	_style_tab(_tab_daily, tab == "daily")
	_style_tab(_tab_ach, tab == "ach")

# _style_tab(btn, active)：设置单个选项卡的样式——active=true 高亮蓝底，false 普通灰底。
func _style_tab(btn: Button, active: bool):
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	if active:
		sb.bg_color = Color(0.30, 0.35, 0.42, 1.0)
		sb.border_color = Color(0.7, 0.75, 0.85, 0.95)
	else:
		sb.bg_color = Color(0.18, 0.18, 0.20, 1.0)
		sb.border_color = Color(0.45, 0.45, 0.45, 0.6)
	sb.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1 if active else 0.72))

# _on_claim_daily(id)：每日任务奖励胶囊点击 → 调用 GameState.claim_daily(id) 领取（刷新由信号驱动）。
func _on_claim_daily(id: String):
	GameState.claim_daily(id)

# _on_claim_bonus()：额外奖励胶囊点击 → 调用 GameState.claim_daily_bonus 领取（三任务全完成才可领）。
func _on_claim_bonus():
	GameState.claim_daily_bonus()

# _on_claim_ach(id)：成就奖励胶囊点击 → 调用 GameState.claim_achievement(id) 领取当前等级奖励。
# 领取成功飘字反馈。称号必须在领取「前」取：领取会立刻升到下一档，ach_tier_name 随即变成新档称号。
func _on_claim_ach(id: String):
	var tname := GameState.ach_tier_name(id)
	if GameState.claim_achievement(id):
		_toast("已领取「%s」奖励" % tname)

# _claimable_count()：统计当前「已达成但未领取」的奖励条目数（每日任务 + 每日额外奖励 + 成就）。
# 供一键领取按钮判断是否可点（为 0 时置灰）。
func _claimable_count() -> int:
	var n := 0
	for t in GameState.DAILY_TASKS:
		if GameState.daily_done(String(t["id"])) and not GameState.daily_is_claimed(String(t["id"])):
			n += 1
	if GameState.daily_all_done() and not GameState.daily_bonus_claimed:
		n += 1
	for a in GameState.ACHIEVEMENTS:
		var id := String(a["id"])
		if not GameState.ach_finished(id) and GameState.ach_reached(id):
			n += 1
	return n

# _on_claim_all()：一键领取——把当前所有「已达成未领取」的奖励一次性领完（每日任务 + 每日额外奖励 + 成就）。
# 逐项调用 GameState 的领取接口（各自负责校验、发奖、存档、广播），这里只汇总数量做飘字提示。
func _on_claim_all():
	var n := 0
	# 1) 每日任务
	for t in GameState.DAILY_TASKS:
		var id := String(t["id"])
		if GameState.daily_done(id) and not GameState.daily_is_claimed(id):
			if GameState.claim_daily(id):
				n += 1
	# 2) 每日「全部完成」额外奖励
	if GameState.daily_all_done() and not GameState.daily_bonus_claimed:
		if GameState.claim_daily_bonus():
			n += 1
	# 3) 成就（每项领当前等级奖励）
	for a in GameState.ACHIEVEMENTS:
		var id := String(a["id"])
		if not GameState.ach_finished(id) and GameState.ach_reached(id):
			if GameState.claim_achievement(id):
				n += 1
	if n > 0:
		_toast("一键领取 %d 项奖励" % n)

# _toast(text)：居中偏下弹出一行飘字（1.2 秒后自动 queue_free），用于领取成功等轻量反馈。
# 与 hub.gd 的同名实现保持一致（项目无共享 UI 工具脚本，故各自复制一份）。
func _toast(text: String):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 200, vh - 170)
	lbl.size = Vector2(400, 40)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

# _daily_done_count()：统计当前已完成(达成目标)的每日任务数量，用于额外奖励进度显示。
func _daily_done_count() -> int:
	var n := 0
	for t in GameState.DAILY_TASKS:
		if GameState.daily_done(t["id"]):
			n += 1
	return n

# _refresh()：任务核心刷新（被 tasks_changed 信号驱动）。遍历每日任务行——更新进度文字、进度条宽度、
# 奖励胶囊状态(已领取/未达成灰、已达成高亮)；刷新额外奖励进度与状态；遍历成就行调用 _update_ach_row。
func _refresh():
	for r in _daily_rows:
		var id: String = r["id"]
		var cur := GameState.daily_progress_of(id)
		var tgt := maxi(1, GameState.daily_target(id))
		r["prog"].text = "%d/%d" % [cur, tgt]
		# 进度条按 0~1 显示，最大到 1；条宽固定为背景宽度，避免溢出。
		var ratio := clampf(float(cur) / float(tgt), 0.0, 1.0)
		var bgw: float = r["inner_w"]
		r["bar"].size = Vector2(bgw * ratio, r["bar"].size.y)
		# 奖励胶囊状态：已领取/未达成 → 灰；已达成未领取 → 高亮可点。
		var st := REWARD_STATE_LOCKED
		if GameState.daily_is_claimed(id):
			st = REWARD_STATE_CLAIMED
		elif GameState.daily_done(id):
			st = REWARD_STATE_READY
		_apply_reward_state(r["box"], st)

	if _bonus_box != null:
		var all := GameState.daily_all_done()
		var done_n := _daily_done_count()
		_bonus_prog.text = "%d/%d" % [done_n, GameState.DAILY_TASKS.size()]
		if _bonus_bar != null:
			var bratio: float = clampf(float(done_n) / float(maxi(1, GameState.DAILY_TASKS.size())), 0.0, 1.0)
			_bonus_bar.size = Vector2(_bonus_inner_w * bratio, _bonus_bar.size.y)
		var bst := REWARD_STATE_LOCKED
		if GameState.daily_bonus_claimed:
			bst = REWARD_STATE_CLAIMED
		elif all:
			bst = REWARD_STATE_READY
		_apply_reward_state(_bonus_box, bst)

	for r in _ach_rows:
		_update_ach_row(r)

	# 一键领取按钮：有可领奖励时高亮可点，否则置灰
	if _claim_all_btn != null:
		_claim_all_btn.disabled = (_claimable_count() <= 0)
