extends Control

# ============================================================================
# chest_panel.gd —— 宝箱界面（从主界面「宝箱」按钮打开）
# 显示 4 个宝箱位置：空位占位；有宝箱显示图标+名称+下方解锁选项框；
# 点击「解锁」→ 进度条 + 剩余时间；解锁完成 → 「领取」发奖并腾空位。
# 数据全部来自 GameState.chests（跨场景、跨重启持久）。
#
# ★ 互斥规则（2026-10-04 用户需求）：同一时间只允许 1 个宝箱在解锁。
#   底层 GameState.start_unlock() 已强制校验，界面这里额外做两件事：
#     ① 打开界面时调 fix_multi_unlocking() 清理「旧存档里多箱同时在解」的非法状态；
#     ② 其余槽的「解锁」按钮置灰，并提示需等待。
# ============================================================================

var _slot_cards: Array = []   # 每项 dict: {slot, root, icon, name, btn, bar, remain, time, collected}，每槽一张卡片
var _help_layer: Control = null   # 宝箱系统详解弹层（「?」打开，全屏覆盖）

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 先修复可能存在的「多箱同时解锁」非法状态（互斥规则加设前的旧存档），
	# 必须在 _build() 之前，让卡片按修复后的状态渲染。
	var cleared: Array = GameState.fix_multi_unlocking()
	_build()
	if not cleared.is_empty():
		_toast("同时只能解锁 1 个宝箱，已中断多余的解锁")

# _build()：构建宝箱界面——半透明遮罩、全屏面板、标题「宝箱」、关闭按钮、标题旁「?」系统详解按钮，
# 以及按窗口铺开的 4 个宝箱卡片（GameState.CHEST_SLOT_COUNT）。每张卡片在 _build_slot 中构造并立即刷新。
func _build():
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# 全屏面板（撑满屏幕）
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.11, 0.11, 0.13, 0.98)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "宝箱"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	title.position = Vector2(40, 26)
	panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	close_btn.flat = true
	close_btn.position = Vector2(vw - 60, 22)
	close_btn.size = Vector2(44, 44)
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	# 标题右侧的「?」圆圈：点击查看宝箱系统详解
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 20)
	help_btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	help_btn.position = Vector2(124, 32)
	help_btn.size = Vector2(34, 34)
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0, 0, 0, 0)
	hs.border_color = Color(0.6, 0.62, 0.68, 0.9)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(999)
	hs.content_margin_left = 0
	hs.content_margin_right = 0
	hs.content_margin_top = 0
	hs.content_margin_bottom = 0
	help_btn.add_theme_stylebox_override("normal", hs)
	help_btn.add_theme_stylebox_override("hover", hs)
	help_btn.add_theme_stylebox_override("pressed", hs)
	help_btn.pressed.connect(_show_help)
	panel.add_child(help_btn)

	# 4 个宝箱卡片（按窗口铺开，撑满屏幕）
	var n := GameState.CHEST_SLOT_COUNT
	var margin: float = 70.0
	var gap: float = 28.0
	var card_w: float = (vw - margin * 2.0 - float(n - 1) * gap) / float(n)
	var y0: float = 132.0
	var card_h: float = vh - y0 - 40.0
	for i in range(n):
		_build_slot(panel, i, margin + float(i) * (card_w + gap), y0, card_w, card_h)

# _build_slot(parent, slot, x, y, w, h)：构建单个宝箱卡片。含图标、名称、解锁/领取按钮、
# 进度条+剩余时间、解锁时长提示。控件引用存入 _slot_cards，最后调用 _refresh_slot 初刷。
# 参数 x/y/w/h 为该卡片在面板内的布局。
func _build_slot(parent: Control, slot: int, x: float, y: float, w: float, h: float):
	var root := Panel.new()
	root.position = Vector2(x, y)
	root.size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.35, 0.35, 0.4, 0.7)
	sb.set_corner_radius_all(maxi(8, int(w * 0.05)))
	root.add_theme_stylebox_override("panel", sb)
	parent.add_child(root)

	var icon_sz: float = minf(w * 0.36, h * 0.30)
	var icon := TextureRect.new()
	icon.position = Vector2(w / 2.0 - icon_sz / 2.0, h * 0.07)
	icon.size = Vector2(icon_sz, icon_sz)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(icon)

	var name_font: int = int(clampf(w * 0.11, 16.0, 34.0))
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", name_font)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0, h * 0.07 + icon_sz + h * 0.03)
	name_lbl.size = Vector2(w, name_font * 1.8)
	root.add_child(name_lbl)

	# 解锁/领取按钮（未解锁=解锁；可领取=领取）
	var bw: float = w * 0.62
	var bh: float = clampf(h * 0.10, 36.0, 64.0)
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", int(clampf(bh * 0.44, 14.0, 26.0)))
	btn.position = Vector2(w / 2.0 - bw / 2.0, h * 0.54)
	btn.size = Vector2(bw, bh)
	btn.pressed.connect(_on_slot_btn_pressed.bind(slot))
	root.add_child(btn)

	# 进度条 + 剩余时间（解锁中/可领取显示）
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.position = Vector2(w * 0.12, h * 0.72)
	bar.size = Vector2(w * 0.76, clampf(h * 0.035, 14.0, 26.0))
	bar.show_percentage = false
	root.add_child(bar)

	var remain_lbl := Label.new()
	remain_lbl.add_theme_font_size_override("font_size", int(clampf(w * 0.085, 13.0, 24.0)))
	remain_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	remain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remain_lbl.position = Vector2(0, h * 0.775)
	remain_lbl.size = Vector2(w, 26)
	root.add_child(remain_lbl)

	# 解锁所需时间提示
	var time_lbl := Label.new()
	time_lbl.add_theme_font_size_override("font_size", int(clampf(w * 0.07, 12.0, 20.0)))
	time_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_lbl.position = Vector2(0, h * 0.88)
	time_lbl.size = Vector2(w, 22)
	root.add_child(time_lbl)

	_slot_cards.append({"slot": slot, "root": root, "icon": icon, "name": name_lbl,
		"btn": btn, "bar": bar, "remain": remain_lbl, "time": time_lbl, "collected": false})
	_refresh_slot(slot)

# _on_overlay_input(event)：点遮罩（鼠标按下）关闭宝箱面板。注：仅认按下，避免误触发。
func _on_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_close()

# _close()：销毁宝箱面板自身（queue_free）。
func _close():
	queue_free()

# _toast(text)：屏幕居中偏下弹出一行飘字（1.2 秒后自动释放），用于「已有宝箱正在解锁」等轻量提示。
func _toast(text: String):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 220, vh - 150)
	lbl.size = Vector2(440, 40)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

# ============================================================
#  宝箱系统详解（点标题右侧「?」弹出，分条陈述）
# UI 铁律体现：获取概率/解锁时长/奖励等规则不放进常驻界面，而是放进「?」弹层。
# ============================================================
func _show_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		return
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	_help_layer = Control.new()
	_help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_help_layer)   # 加在主面板之后 → 显示在其上
	# 全屏面板（撑满屏幕）
	var p := Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.99)
	p.add_theme_stylebox_override("panel", ps)
	_help_layer.add_child(p)
	# 标题
	var t := Label.new()
	t.text = "宝箱系统详解"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	t.position = Vector2(40, 26)
	p.add_child(t)
	# 关闭
	var cb := Button.new()
	cb.text = "×"
	cb.add_theme_font_size_override("font_size", 28)
	cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cb.flat = true
	cb.position = Vector2(vw - 56, 18)
	cb.size = Vector2(40, 40)
	cb.pressed.connect(_close_help)
	p.add_child(cb)
	# 分条正文（撑满）
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(64, 116)
	vbox.size = Vector2(vw - 128, vh - 170)
	vbox.add_theme_constant_override("separation", 18)
	p.add_child(vbox)
	for line in _help_lines():
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(vw - 128, 0)
		vbox.add_child(l)

# _close_help()：销毁宝箱系统详解弹层并清空引用。
func _close_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = null

# _help_lines()：返回宝箱系统详解文案——来源(每击杀 N 个丧尸掉箱)、四种宝箱(概率/解锁时长/奖励)，
# 全部从 GameState 数据动态生成，数值改动无需改文案。
func _help_lines() -> Array:
	var lines: Array = []
	lines.append("1. 获取：每击杀 %d 个丧尸，随机获得 1 个宝箱，自动放入空槽位。" % GameState.CHEST_KILL_INTERVAL)
	lines.append("2. 解锁：同一时间只能解锁 1 个宝箱，其余需排队等待（已完成可领取的不占用名额）。")
	lines.append("3. 四种宝箱（出现概率 / 解锁时长 / 奖励）：")
	for tp in GameState.CHEST_ORDER:
		var d = GameState.CHEST_DEFS[tp]
		var reward := "%d 金币" % int(d["reward_gold"])
		if int(d["reward_diamond"]) > 0:
			reward += " + %d 钻石" % int(d["reward_diamond"])
		lines.append("     · %s   概率 %d%%   解锁 %s   奖励 %s" % [
			d["name"], int(round(float(d["prob"]) * 100.0)), _fmt_dur(int(d["unlock_sec"])), reward])
	return lines

# _on_slot_btn_pressed(slot)：宝箱卡片按钮点击。状态1(已就位未解锁)→开始解锁倒计时；
# 状态3(已解锁完成可领取)→领取奖励弹窗、标记 collected、刷新该槽。状态0/2 按钮不可见不触发。
func _on_slot_btn_pressed(slot: int):
	var st := GameState.chest_state(slot)
	if st == 1:
		if GameState.any_chest_unlocking():
			_toast("已有宝箱正在解锁，请先等待完成")
			return
		GameState.start_unlock(slot)
	elif st == 3:
		var reward: Dictionary = GameState.collect_chest(slot)
		if not reward.is_empty():
			_show_reward_popup(reward)
		for card in _slot_cards:
			if card["slot"] == slot:
				card["collected"] = true
		_refresh_slot(slot)

# ============================================================
#  领取奖励提示弹窗（点击「领取」后弹出，展示获得的金币/钻石）
# ============================================================
# _show_reward_popup(reward)：弹窗展示本次领取的宝箱奖励。reward 含 type/gold/diamond，
# 从 CHEST_DEFS 取名称与图标，全屏拦截层防止误触下层按钮（仅认鼠标按下关闭）。
func _show_reward_popup(reward: Dictionary):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# 全屏拦截层（盖在宝箱面板之上，避免误触下层按钮）
	var pop := Control.new()
	pop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pop)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	# 【坑】gui_input 对鼠标移动(motion)也会触发，不过滤会"秒开秒关"→ 只认鼠标按下
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			pop.queue_free())
	pop.add_child(shade)

	var pw := 440.0
	var ph := 340.0
	var box := Panel.new()
	box.position = Vector2(vw / 2.0 - pw / 2.0, vh / 2.0 - ph / 2.0)
	box.size = Vector2(pw, ph)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.14, 0.14, 0.17, 1.0)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.95, 0.75, 0.15, 0.95)
	bs.set_corner_radius_all(16)
	box.add_theme_stylebox_override("panel", bs)
	pop.add_child(box)

	var def = GameState.CHEST_DEFS[reward["type"]]

	var icon_sz := 96.0
	var icon := TextureRect.new()
	icon.position = Vector2(pw / 2.0 - icon_sz / 2.0, 28)
	icon.size = Vector2(icon_sz, icon_sz)
	icon.texture = _chest_icon_texture(reward["type"])
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var title := Label.new()
	title.text = "领取成功"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 34 + icon_sz)
	title.size = Vector2(pw, 40)
	box.add_child(title)

	var gold: int = int(reward["gold"])
	var diamond: int = int(reward["diamond"])
	var info_txt := "%s\n获得 %d 金币" % [def["name"], gold]
	if diamond > 0:
		info_txt += "\n获得 %d 钻石" % diamond
	var info := Label.new()
	info.text = info_txt
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.position = Vector2(0, 34 + icon_sz + 48)
	info.size = Vector2(pw, 96)
	box.add_child(info)

	var ok := Button.new()
	ok.text = "确定"
	ok.add_theme_font_size_override("font_size", 22)
	ok.position = Vector2(pw / 2.0 - 70, ph - 62)
	ok.size = Vector2(140, 44)
	ok.pressed.connect(func(): pop.queue_free())
	box.add_child(ok)

# _refresh_slot(slot)：按 GameState.chest_state 刷新单张宝箱卡片——
# 0 空位(全隐)、已领取(collected 标记后显「已领取 ✓」)、1 可解锁(显「解锁」按钮)、
# 2 解锁中(显进度条+剩余时间)、3 可领取(显「领取」按钮)。状态2/3 的进度条由 _process 持续更新。
func _refresh_slot(slot: int):
	var card = null
	for c in _slot_cards:
		if c["slot"] == slot:
			card = c
	if card == null:
		return
	var st := GameState.chest_state(slot)
	var c = GameState.chests[slot]
	if st == 0:
		card["icon"].texture = null
		card["name"].text = "空位"
		card["btn"].visible = false
		card["bar"].visible = false
		card["remain"].text = ""
		card["time"].text = ""
		return
	var def = GameState.CHEST_DEFS[c["type"]]
	card["icon"].texture = _chest_icon_texture(c["type"])
	card["name"].text = def["name"]
	card["time"].text = "解锁需 %s" % _fmt_dur(int(def["unlock_sec"]))
	if card["collected"]:
		card["btn"].visible = false
		card["bar"].visible = false
		card["remain"].text = "已领取 ✓"
		return
	if st == 1:
		card["btn"].visible = true
		card["btn"].text = "解锁"
		# 同一时间只允许一个宝箱解锁：有别的宝箱在解锁中，本按钮置灰等待
		card["btn"].disabled = GameState.any_chest_unlocking()
		card["bar"].visible = false
		card["remain"].text = ""
	elif st == 2:
		card["btn"].visible = false
		card["bar"].visible = true
		card["remain"].text = "剩余 " + _fmt_time(GameState.remaining_ms(slot))
	elif st == 3:
		card["btn"].visible = true
		card["btn"].text = "领取"
		card["bar"].visible = true
		card["remain"].text = "可领取"

# _process(_delta)：每帧更新「解锁中(状态2)」卡片的进度条与剩余时间，以及「可领取(状态3)」
# 卡片的满条与「领取」按钮（领过则标记 collected 后不再显按钮）。保证倒计时实时可见。
func _process(_delta: float):
	var busy := GameState.any_chest_unlocking()   # 是否已有宝箱在解锁（互斥：其余槽位置灰等待）
	for c in _slot_cards:
		var slot: int = c["slot"]
		var st := GameState.chest_state(slot)
		if st == 2:
			var total := float(GameState.CHEST_DEFS[GameState.chests[slot]["type"]]["unlock_sec"]) * 1000.0
			var rem := GameState.remaining_ms(slot)
			c["bar"].visible = true
			c["bar"].value = 1.0 - (rem / total)
			c["remain"].text = "剩余 " + _fmt_time(rem)
		elif st == 3 and not c["collected"]:
			c["bar"].visible = true
			c["bar"].value = 1.0
			if not c["btn"].visible:
				c["btn"].visible = true
				c["btn"].text = "领取"
			c["remain"].text = "可领取"
		elif st == 1:
			# 同步互斥状态：正在解锁的那一个完成后，其余按钮自动恢复可点
			c["btn"].disabled = busy

# 宝箱图标：优先加载 art/chest_类型.png 精绘贴图（GameState._tex_from_png 读原始字节，无需编辑器导入）；
# 缺文件时退回代码画的简易图标
func _chest_icon_texture(type: String) -> Texture2D:
	var t := GameState._tex_from_png("res://art/chest_%s.png" % type)
	if t != null:
		return t
	return _chest_icon_procedural(GameState.CHEST_DEFS[type]["color"])

# _chest_icon_procedural(col)：兜底图标——代码画箱体+盖(提亮)+锁扣，返回 ImageTexture。
func _chest_icon_procedural(col: Color) -> Texture2D:
	var s := 72
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Rect2(8, 26, s - 16, s - 34)
	for yy in range(int(body.position.y), int(body.position.y + body.size.y)):
		for xx in range(int(body.position.x), int(body.position.x + body.size.x)):
			img.set_pixel(xx, yy, col)
	var lid := Rect2(8, 16, s - 16, 14)
	for yy in range(int(lid.position.y), int(lid.position.y + lid.size.y)):
		for xx in range(int(lid.position.x), int(lid.position.x + lid.size.x)):
			img.set_pixel(xx, yy, col.lightened(0.18))
	var lock := Rect2(s / 2 - 5, 30, 10, 14)
	for yy in range(int(lock.position.y), int(lock.position.y + lock.size.y)):
		for xx in range(int(lock.position.x), int(lock.position.x + lock.size.x)):
			img.set_pixel(xx, yy, Color(0.15, 0.12, 0.08, 1.0))
	return ImageTexture.create_from_image(img)

# _fmt_time(ms)：毫秒转 HH:MM:SS 或 MM:SS 字符串（剩余时间显示）。
func _fmt_time(ms: float) -> String:
	var s := int(ms / 1000.0)
	var h := s / 3600
	s %= 3600
	var m := s / 60
	s %= 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]

# _fmt_dur(sec)：秒转「N小时」或「N分钟」字符串（解锁时长提示）。
func _fmt_dur(sec: int) -> String:
	var h := sec / 3600
	var m := (sec % 3600) / 60
	if h > 0:
		return "%d小时" % h
	return "%d分钟" % m
