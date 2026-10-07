extends Control

# ============================================================================
# Menu.gd —— 人物界面（主界面点「人物」进入）
# ============================================================================
# 界面规则（和「角色」右边那个 ? 里写的完全一致）：
#   · 点「未选中」的人物 → 切换为当前使用的人物（不切场景）
#   · 点「已选中」的人物 → 打开人物详情（数值面板 + 天赋升级）
#   · 带 🔒 的人物     → 未解锁，卡片上写着解锁条件，达成后自动解锁
#
# 人物的一切数值都来自 Characters.gd（基础值 + 天赋加成），
# 本文件只负责显示与交互，不写死任何数值。
#
# 游戏入口只有一个：回主界面点「开始游戏」→ 关卡选择 → 进游戏。
# 这个界面永远不会直接跳进游戏。
# ============================================================================

var _card_nodes: Array = []            # 角色卡片列表，每项 {card,label,desc,img,id}，_refresh_cards 时遍历刷新
var _hint: Label = null                # 底部规则提示文字

var _help_layer: Control = null        # 「?」规则说明弹层（全屏，覆盖在最上层）
var _detail_layer: Control = null      # 人物详情弹层
var _detail_id := ""                   # 当前正在查看详情的人物 id（空串表示未打开）
var _detail_stat_labels: Dictionary = {}   # 数值键(hp/speed/...) -> 对应数值 Label
var _detail_talent_box: VBoxContainer = null   # 多天赋行容器（在滚动容器内部）
var _detail_talent_scroll: ScrollContainer = null  # 天赋区滚动容器（天赋多时可纵向滚动，不溢出面板）
var _detail_talent_rows: Array = []            # 每行引用 [{idx, name_lbl, lv_lbl, info_lbl, btn}]
var _detail_gold_lbl: Label = null             # 详情右上角「金币：N    精魂：M」标签（精魂决定是否可升级）


# _ready()：人物界面入口。铺满视口 → 让 GameState 检查并自动解锁满足条件的人物 →
# 构建界面 → 处理 --detailshot=角色id 渲染自测参数（直接打开某人物详情）。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameState.check_character_unlocks()   # 已达成条件的人物自动解锁
	_build()
	# 渲染自测：直接打开某人物详情（离线验证布局用），如 --detailshot=police
	for a in OS.get_cmdline_args():
		if a.begins_with("--detailshot"):
			var cid := a.get_slice("=", 1)
			_show_detail(cid if cid != "" else "police")


# ----------------------------------------------------------------------------
# _build()：搭出整个界面——深色背景、标题「角色」、右侧「?」规则按钮、返回主界面按钮、
# 可滚动的 3 列角色卡片网格、底部提示。随后刷新卡片并处理详情调试参数。
# ----------------------------------------------------------------------------
func _build():
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y

	# 深色背景
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.14, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题「角色」
	var title := Label.new()
	title.text = "角色"
	title.position = Vector2(30, 20)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	add_child(title)

	# 标题右侧的「?」圆圈：点开看本界面的规则说明（和宝箱界面同一种样式）
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 20)
	help_btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	var tw: float = maxf(title.get_minimum_size().x, 40.0)
	help_btn.position = Vector2(30.0 + tw + 16.0, 26.0)
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
	add_child(help_btn)

	# 返回主界面
	var back := Button.new()
	back.text = "返回主界面"
	back.custom_minimum_size = Vector2(150, 46)
	back.position = Vector2(vw - 170, 18)
	back.pressed.connect(_on_back_pressed)
	add_child(back)

	# ====== 可滚动的角色网格 ======
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 76)
	scroll.size = Vector2(vw - 40, vh - 136)
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	var col_w: float = (vw - 60.0) / 3.0
	grid.custom_minimum_size = Vector2(scroll.size.x, 0)
	scroll.add_child(grid)

	for cid in Characters.ORDER:
		_build_card(grid, cid, col_w)

	_refresh_cards()

	# 底部提示
	_hint = Label.new()
	_hint.text = "点「未选中」的人物 = 切换人物 ｜ 点「已选中」的人物 = 查看详情"
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 20.0
	_hint.offset_top = -40.0
	_hint.offset_right = vw - 20.0
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	add_child(_hint)


# ----------------------------------------------------------------------------
# _build_card(grid, cid, col_w)：构建单张角色卡片（立绘 + 名字 + 解锁条件/天赋提示）。
# 仅已解锁人物绑定点击；把控件引用存入 _card_nodes 供 _refresh_cards 复用。cid 人物 id。
# ----------------------------------------------------------------------------
func _build_card(grid: GridContainer, cid: String, col_w: float):
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(col_w, 262)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# 立绘
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(col_w - 20, 190)
	img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	img.texture = _load_art(cid)
	vbox.add_child(img)

	# 名字
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# 解锁条件 / 天赋提示
	var desc := Label.new()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.custom_minimum_size = Vector2(col_w - 24, 40)
	vbox.add_child(desc)

	# 只有「已解锁」的人物可点；点了之后是切人还是看详情由 _on_card_input 判断
	if GameState.is_unlocked(cid):
		card.gui_input.connect(_on_card_input.bind(cid))

	_card_nodes.append({"card": card, "label": label, "desc": desc, "img": img, "id": cid})
	grid.add_child(card)


# _load_art(cid)：加载角色立绘。先取 Characters.front_art 路径，回退到 res://art/<cid>.png，
# 都没有则画一个占位灰块。返回 Texture2D。
func _load_art(cid: String) -> Texture2D:
	var path := Characters.front_art(cid)
	if not ResourceLoader.exists(path):
		path = "res://art/%s.png" % cid
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.5, 0.6))
	return ImageTexture.create_from_image(img)


# ----------------------------------------------------------------------------
# _on_card_input(event, cid)：卡片点击回调（仅左键按下）。未解锁忽略；
# 已选中的人物→打开详情；未选中→切换为当前使用人物并保存，刷新卡片与提示。
# ----------------------------------------------------------------------------
func _on_card_input(event: InputEvent, cid: String):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not GameState.is_unlocked(cid):
		return
	if cid == GameState.selected_character:
		_show_detail(cid)                 # 已选中 → 进详情
		return
	GameState.selected_character = cid    # 未选中 → 切换人物
	GameState.save_profile()
	_refresh_cards()
	if _hint != null:
		_hint.text = "已切换为「%s」｜再点一次这张卡片可以查看详情" % Characters.display_name(cid)


# ----------------------------------------------------------------------------
# _refresh_cards()：遍历 _card_nodes，按「锁定/选中/普通」三态重设每张卡片的文字、配色、
# 立绘亮度(moderate)与边框样式。解锁条件、天赋简称等文案都来自 GameState/Characters。
# ----------------------------------------------------------------------------
func _refresh_cards():
	for item in _card_nodes:
		var card: PanelContainer = item["card"]
		var label: Label = item["label"]
		var desc: Label = item["desc"]
		var img: TextureRect = item["img"]
		var cid: String = item["id"]
		var nm: String = Characters.display_name(cid)
		var locked: bool = not GameState.is_unlocked(cid)
		var sel: bool = (cid == GameState.selected_character) and not locked

		if locked:
			label.text = "%s 🔒" % nm
			label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			desc.text = "解锁条件：" + GameState.unlock_progress_text(cid)
			desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
			img.modulate = Color(0.32, 0.32, 0.32, 1.0)
		elif sel:
			label.text = "%s（已选中）" % nm
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			desc.text = "%s\n点一次进详情" % _talent_short(cid)
			desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.6))
			img.modulate = Color(1, 1, 1, 1)
		else:
			label.text = "%s（点击选择）" % nm
			label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88))
			desc.text = _talent_short(cid)
			desc.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
			img.modulate = Color(0.78, 0.78, 0.78, 1.0)

		card.add_theme_stylebox_override("panel", _card_style(locked, sel))


# _talent_short(cid)：返回该人物的天赋简称串（如「天赋：A · B」）；无天赋则「天赋：待设计」。
func _talent_short(cid: String) -> String:
	if not Characters.has_talent(cid):
		return "天赋：待设计"
	var names: Array = []
	for i in range(Characters.talent_count(cid)):
		names.append(Characters.talent_name(cid, i))
	return "天赋：" + " · ".join(names)


# _card_style(locked, sel)：根据卡片状态返回对应边框/底色样式（锁定灰暗、选中金边、普通灰边）。
func _card_style(locked: bool, sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	if locked:
		sb.bg_color = Color(0.12, 0.12, 0.16, 1)
		sb.border_color = Color(0.28, 0.28, 0.32, 1)
		sb.set_border_width_all(1)
	elif sel:
		sb.bg_color = Color(0.20, 0.17, 0.08, 1)
		sb.border_color = Color(1.0, 0.82, 0.25, 1)
		sb.set_border_width_all(3)
	else:
		sb.bg_color = Color(0.13, 0.13, 0.18, 1)
		sb.border_color = Color(0.5, 0.5, 0.58, 1)
		sb.set_border_width_all(1)
	return sb


# _on_back_pressed()：点「返回主界面」→ 切回 Hub 场景。
func _on_back_pressed():
	get_tree().change_scene_to_file("res://Hub.tscn")


# ============================================================================
# 「?」规则说明（全屏，和宝箱界面的 ? 同一种做法）
# UI 铁律体现：角色界面的规则说明不直接贴在界面上，而是放进「?」弹层，点击才展示。
# ============================================================================
func _show_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y

	_help_layer = Control.new()
	_help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_help_layer)   # 加在所有内容之后 → 显示在最上层

	var p := Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.99)
	p.add_theme_stylebox_override("panel", ps)
	_help_layer.add_child(p)

	var t := Label.new()
	t.text = "角色界面说明"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	t.position = Vector2(40, 26)
	p.add_child(t)

	var cb := Button.new()
	cb.text = "×"
	cb.add_theme_font_size_override("font_size", 28)
	cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cb.flat = true
	cb.position = Vector2(vw - 56, 18)
	cb.size = Vector2(40, 40)
	cb.pressed.connect(_close_help)
	p.add_child(cb)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(64, 116)
	vbox.size = Vector2(vw - 128, vh - 170)
	vbox.add_theme_constant_override("separation", 20)
	p.add_child(vbox)

	for line in _help_lines():
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(vw - 128, 0)
		vbox.add_child(l)


# _help_lines()：返回规则说明的几条文案（如何切换/查看人物、解锁、四项数值、天赋作用范围）。
func _help_lines() -> Array:
	return [
		"1. 点击「未选中」的人物 → 切换为当前使用的人物（选完回主界面点「开始游戏」进游戏）。",
		"2. 点击「已选中」的人物 → 打开该人物的详情界面（数值面板 + 天赋）。",
		"3. 带 🔒 的人物尚未解锁，卡片上直接写着解锁条件，达成后自动解锁。",
		"4. 人物数值共四项：生命值 / 移速 / 手雷伤害 / 支援导弹伤害，均为人物的基础数值。",
		"5. 天赋升级只提升该人物的天赋技能，与被天赋影响的数值无关的其他项不会变动。",
	]


# _close_help()：销毁「?」规则弹层并清空引用。
func _close_help():
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = null


# ============================================================================
# 人物详情界面
#   左：放大的立绘    右：数值面板（生命值/移速/手雷伤害/支援导弹伤害/换弹时间）
#   下：天赋（名称 + 说明 + 当前效果 + 升级按钮，按钮上写明升级所需精魂）
# 布局坐标常量：rx/rw 为右侧数值面板起点与宽度；ty/t_h 为下方天赋区起点与高度。
# ============================================================================
func _show_detail(cid: String):
	if _detail_layer != null and is_instance_valid(_detail_layer):
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y
	_detail_id = cid
	_detail_stat_labels = {}

	_detail_layer = Control.new()
	_detail_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_detail_layer)

	var p := Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.13, 0.99)
	p.add_theme_stylebox_override("panel", ps)
	_detail_layer.add_child(p)

	# ---- 关闭 ----
	var cb := Button.new()
	cb.text = "×"
	cb.add_theme_font_size_override("font_size", 28)
	cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cb.flat = true
	cb.position = Vector2(vw - 56, 18)
	cb.size = Vector2(40, 40)
	cb.pressed.connect(_close_detail)
	p.add_child(cb)

	# ---- 金币 / 精魂（看能不能升级）----
	_detail_gold_lbl = Label.new()
	_detail_gold_lbl.add_theme_font_size_override("font_size", 20)
	_detail_gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_detail_gold_lbl.position = Vector2(vw - 620, 28)
	_detail_gold_lbl.size = Vector2(550, 30)
	_detail_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(_detail_gold_lbl)

	# ---- 左：放大立绘 ----
	var art := TextureRect.new()
	art.texture = _load_art(cid)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(40.0, 84.0)
	art.size = Vector2(vw * 0.38, vh - 150.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(art)

	# ---- 右：数值面板 ----
	var rx: float = vw * 0.46
	var rw: float = vw - rx - 40.0

	var name_lbl := Label.new()
	name_lbl.text = Characters.display_name(cid)
	name_lbl.add_theme_font_size_override("font_size", 40)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	name_lbl.position = Vector2(rx, 84)
	name_lbl.size = Vector2(rw, 52)
	p.add_child(name_lbl)

	var rows := [
		["hp", "生命值"],
		["speed", "移速"],
		["grenade_damage", "手雷伤害"],
		["missile_damage", "支援导弹伤害"],
		["reload_time", "换弹时间"],
	]
	var y0: float = 152.0
	var row_h: float = 42.0
	for i in range(rows.size()):
		var key: String = rows[i][0]
		var cn: String = rows[i][1]
		var ry: float = y0 + float(i) * row_h

		var row_bg := Panel.new()
		row_bg.position = Vector2(rx, ry)
		row_bg.size = Vector2(rw, row_h - 8.0)
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0.14, 0.14, 0.18, 1.0)
		rsb.set_corner_radius_all(8)
		row_bg.add_theme_stylebox_override("panel", rsb)
		row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(row_bg)

		var nl := Label.new()
		nl.text = cn
		nl.add_theme_font_size_override("font_size", 22)
		nl.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		nl.position = Vector2(rx + 20.0, ry + 6.0)
		nl.size = Vector2(rw * 0.5, row_h - 12.0)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(nl)

		var vl := Label.new()
		vl.add_theme_font_size_override("font_size", 22)
		vl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		vl.position = Vector2(rx + rw * 0.5, ry + 6.0)
		vl.size = Vector2(rw * 0.5 - 20.0, row_h - 12.0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(vl)
		_detail_stat_labels[key] = vl

	# ---- 下：天赋 ----
	var ty: float = y0 + float(rows.size()) * row_h + 12.0
	var t_h: float = maxf(130.0, vh - ty - 20.0)
	var t_bg := Panel.new()
	t_bg.position = Vector2(rx, ty)
	t_bg.size = Vector2(rw, t_h)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.13, 0.12, 0.10, 1.0)
	tsb.border_color = Color(0.45, 0.38, 0.20, 0.9)
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(10)
	t_bg.add_theme_stylebox_override("panel", tsb)
	t_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(t_bg)

	# ---- 下：天赋（多天赋，每行一个，独立升级）----
	var t_title := Label.new()
	t_title.text = "天赋"
	t_title.add_theme_font_size_override("font_size", 20)
	t_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	t_title.position = Vector2(rx + 20.0, ty + 6.0)
	t_title.size = Vector2(rw - 40.0, 24.0)
	p.add_child(t_title)

	# 天赋列表放进 ScrollContainer：天赋多时纵向滚动，内容不再溢出面板被截掉
	_detail_talent_scroll = ScrollContainer.new()
	_detail_talent_scroll.position = Vector2(rx + 16.0, ty + 34.0)
	_detail_talent_scroll.size = Vector2(rw - 32.0, maxf(80.0, t_h - 42.0))
	_detail_talent_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(_detail_talent_scroll)

	_detail_talent_box = VBoxContainer.new()
	_detail_talent_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_talent_box.add_theme_constant_override("separation", 6)
	_detail_talent_scroll.add_child(_detail_talent_box)

	_build_talent_rows(cid)

	_refresh_detail()


# _on_upgrade_pressed(idx)：天赋升级按钮回调。idx 为该人物的天赋序号，调用 GameState 升级，
# 仅提升该天赋等级，不动其它数值；随后刷新详情与卡片。
func _on_upgrade_pressed(idx: int):
	if _detail_id == "":
		return
	GameState.upgrade_talent(_detail_id, idx)   # 只提升该天赋等级，不动其他数值
	_refresh_detail()
	_refresh_cards()


# ----------------------------------------------------------------------------
# _refresh_detail()：按当前天赋等级重算并刷新数值面板与天赋区。
# 数值由 Characters.stats_for(cid, 天赋等级) 计算；换弹时间额外乘角色换弹乘区。
# 同时刷新金币数、调用 _refresh_talent_rows 更新每行说明与升级按钮。
# ----------------------------------------------------------------------------
func _refresh_detail():
	if _detail_layer == null or _detail_id == "":
		return
	var cid := _detail_id
	var st := Characters.stats_for(cid, GameState.char_talent_lvs(cid))

	if _detail_stat_labels.has("hp"):
		_detail_stat_labels["hp"].text = str(int(st["hp"]))
	if _detail_stat_labels.has("speed"):
		_detail_stat_labels["speed"].text = "%d" % int(round(float(st["speed"])))
	if _detail_stat_labels.has("grenade_damage"):
		_detail_stat_labels["grenade_damage"].text = str(int(st["grenade_damage"]))
	if _detail_stat_labels.has("missile_damage"):
		_detail_stat_labels["missile_damage"].text = str(int(st["missile_damage"]))
	if _detail_stat_labels.has("reload_time"):
		# 换弹时间 = 当前武器基础换弹 × 角色换弹乘区（警察「快速换弹」天赋），精确到 0.1 秒
		var aid := Weapons.get_active_id()
		if Weapons.DATA.has(aid):
			var base := Weapons.effective_reload(aid)
			var mul := float(st.get("reload_mul", 1.0))
			_detail_stat_labels["reload_time"].text = "%.1f" % (base * mul)
		else:
			_detail_stat_labels["reload_time"].text = "-"

	if _detail_gold_lbl != null:
		_detail_gold_lbl.text = "金币：%d    精魂：%d" % [GameState.gold, GameState.item_count("soul")]

	# ---- 天赋（多天赋行）----
	_refresh_talent_rows()


# ----------------------------------------------------------------------------
# _build_talent_rows(cid)：按人物天赋数量动态生成每行（名称/等级/说明/升级按钮）。
# 无天赋则显示「待设计」占位；有则逐行构造并存入 _detail_talent_rows，行间加分隔线。
# ----------------------------------------------------------------------------
func _build_talent_rows(cid: String):
	if _detail_talent_box == null:
		return
	for c in _detail_talent_box.get_children():
		c.queue_free()
	_detail_talent_rows = []
	if not Characters.has_talent(cid):
		var none := Label.new()
		none.text = "天赋：待设计\n\n该人物的天赋技能尚未填写（由你设计）。\n填写位置：Characters.gd 中该人物数据里的 talents 字段。"
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_talent_box.add_child(none)
		return
	var cnt: int = Characters.talent_count(cid)
	for i in range(cnt):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)

		var top := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		var lv_lbl := Label.new()
		lv_lbl.add_theme_font_size_override("font_size", 15)
		lv_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		top.add_child(lv_lbl)
		row.add_child(top)

		var info_lbl := Label.new()
		info_lbl.add_theme_font_size_override("font_size", 13)
		info_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.95))
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info_lbl)

		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(0, 24)
		btn.pressed.connect(_on_upgrade_pressed.bind(i))
		row.add_child(btn)

		_detail_talent_box.add_child(row)
		_detail_talent_rows.append({"idx": i, "name_lbl": name_lbl, "lv_lbl": lv_lbl, "info_lbl": info_lbl, "btn": btn})

		if i < cnt - 1:
			_detail_talent_box.add_child(HSeparator.new())


# ----------------------------------------------------------------------------
# _refresh_talent_rows()：按当前天赋等级刷新每行——等级 Lv x/y、说明、当前/升级后效果、
# 升级按钮文字与可点状态（精魂不足置灰）。已满级则按钮显示「已满级」并禁用。
# ----------------------------------------------------------------------------
func _refresh_talent_rows():
	var cid := _detail_id
	if _detail_talent_box == null or cid == "":
		return
	for r in _detail_talent_rows:
		var idx: int = int(r["idx"])
		var lv: int = GameState.char_talent_lv(cid, idx)
		var mx: int = Characters.talent_max_level(cid, idx)
		r["name_lbl"].text = Characters.talent_name(cid, idx)
		r["lv_lbl"].text = "Lv %d / %d" % [lv, mx]
		var bonus := Characters.talent_bonus_text(cid, idx, lv)
		# 精简为两行：说明 + （已满级→当前效果 / 未满级→当前→升级后）。
		# 「已满级」状态由按钮文字表达，不再单独占一行。
		var lines: Array = []
		lines.append("说明：%s" % Characters.talent_desc(cid, idx))
		if lv < mx:
			lines.append("当前 %s → 升级后 %s" % [bonus, Characters.talent_bonus_text(cid, idx, lv + 1)])
		else:
			lines.append("当前效果：%s" % (bonus if bonus != "" else "无加成"))
		r["info_lbl"].text = "\n".join(lines)
		var btn: Button = r["btn"]
		if lv >= mx:
			btn.disabled = true
			btn.text = "已满级（Lv %d）" % mx
		else:
			var cost: int = Characters.talent_soul_cost(lv)
			btn.text = "升级到 Lv %d（%d 精魂）" % [lv + 1, cost]
			# 置灰判定复用 GameState.can_upgrade_talent，与实际升级时的校验同源，
			# 避免「按钮显示可点、点了却失败」的不一致（该函数同时校验精魂与满级）
			btn.disabled = not GameState.can_upgrade_talent(cid, idx)


# _close_detail()：销毁人物详情弹层，清空所有详情相关引用，并刷新卡片高亮状态。
func _close_detail():
	if _detail_layer != null and is_instance_valid(_detail_layer):
		_detail_layer.queue_free()
	_detail_layer = null
	_detail_id = ""
	_detail_stat_labels = {}
	_detail_talent_box = null
	_detail_talent_scroll = null
	_detail_talent_rows = []
	_detail_gold_lbl = null
	_refresh_cards()
