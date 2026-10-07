extends Control

# ============================================================================
# bag_panel.gd —— 背包界面（从主界面「背包」按钮打开）
# 左侧：40 个格子（8 列 × 5 行）
#   前 20 格免费，后 20 格锁定，每 5 格解锁一次（花金币），共 4 批
#   每格显示：物品图标 + 右下角持有数量（空格子什么都不显示）
# 右侧：选中物品的详情面板（名称 / 数量 / 用处 / 来源）
# 交互：点有物品的格子 → 右侧显示该物品的用处与来源
#       点「下一批 5 个锁定格」→ 弹确认框（是否解锁 5 个额外的背包格子？）
#       → 点带价格的选项框 → 解锁这 5 格。
# 物品数据存在 GameState.bag_items / bag_order（存档 user://bag.cfg）。
# 手雷/支援导弹是弹药展示位：不占背包容量、不存档，紧跟普通物品后面显示，
# 持有数读 GameState.grenade_ammo / missile_ammo（商店购买、局内 G/H 消耗后自动刷新）。
# 解锁进度存在 GameState.bag_unlocked（默认 20，上限 40，随存档持久化）。
# ============================================================================

const COLS := 8                        # 网格列数（8 列）
const ROWS := 5                        # 网格行数（5 行）
const TOTAL := 40                      # 背包总格数 = 8×5
const FREE := 20                       # 初始免费格数（前 20 格）
const BATCH := 5                       # 每批解锁的格数（5 格一批，共 4 批）
const UNLOCK_COSTS := [500, 1000, 2000, 4000]   # 每批(5 格)的金币价格（第1~4批）

# 弹药展示条目（手雷/支援导弹）：它们不是背包物品（无 ITEM_DEFS、不占背包容量、不存 bag.cfg），
# 持有数存在 GameState 的弹药字段（grenade_ammo / missile_ammo）。
# 展示规则：在普通物品后面追加两个常驻格，点击可看详情；背包格子不够放时自动隐藏。
const AMMO_SLOTS := [
	{
		"id": "grenade", "ammo_var": "grenade_ammo",
		"name": "手雷", "use": "局内按 G 投掷，范围爆炸伤害", "source": "商店用金币购买",
		"icon": "res://art/item_grenade.png", "color": Color(0.55, 0.62, 0.30),
		"dmg_key": "grenade_damage", "radius": 150,   # 伤害数值=当前人物算上天赋的最终值；半径同 grenade.gd BLAST_RADIUS
	},
	{
		"id": "missile", "ammo_var": "missile_ammo",
		"name": "支援导弹", "use": "局内按 H 呼叫，范围轰炸", "source": "商店用金币购买",
		"icon": "res://art/item_missile.png", "color": Color(0.75, 0.40, 0.28),
		"dmg_key": "missile_damage", "radius": 250,   # 半径同 missile.gd BLAST_RADIUS
	},
]

var _cells: Array = []                # 每格引用缓存：{sb, lock, icon, cnt}
var _selected_slot := -1               # 当前选中格序号（-1 表示未选）
var _sub_label: Label = null           # 顶部「已用 x / y 格」提示
var _dialog: Control = null            # 解锁确认弹窗根
var _dialog_price_btn: Button = null   # 弹窗里的「解锁 5 格（￥N）」按钮
var _sell_one_btn: Button = null       # 详情区「卖出 1 个」按钮（无售价的物品隐藏）
var _sell_all_btn: Button = null       # 详情区「全部卖出」按钮（无售价的物品隐藏）
var _sel_item_id := ""                 # 详情区当前选中的物品 id（卖出时用）
var _dialog_msg: Label = null          # 弹窗提示文字

# 右侧详情面板的控件引用（选中物品时显示名称/数量/用处/来源）
var _detail_icon: TextureRect = null
var _detail_name: Label = null
var _detail_count: Label = null
var _detail_use: Label = null
var _detail_source: Label = null
var _detail_empty: Label = null        # 未选中时的占位提示

# _ready()：背包入口。铺满视口后构建界面。背包数据由 GameState 持久化（user://bag.cfg）。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

# _build()：构建背包界面——全屏面板、标题、已用格数提示、关闭按钮、左网格(40 格) +
# 右详情面板 + 解锁确认弹窗；订阅 GameState 的 bag_changed/stats_changed 信号并首次刷新。
# 网格布局按视口动态计算 cell 尺寸，保证格子正方形且居中。
func _build():
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# 全屏深色面板
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	# 标题
	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.position = Vector2(36, 22)
	panel.add_child(title)

	# 已用格数提示
	_sub_label = Label.new()
	_sub_label.text = "已用 %d / %d 格" % [GameState.bag_used_slots(), GameState.bag_unlocked]
	_sub_label.add_theme_font_size_override("font_size", 14)
	_sub_label.add_theme_color_override("font_color", Color(0.62, 0.64, 0.68))
	_sub_label.position = Vector2(38, 58)
	panel.add_child(_sub_label)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	close_btn.flat = true
	close_btn.position = Vector2(vw - 48, 16)
	close_btn.size = Vector2(36, 36)
	close_btn.pressed.connect(queue_free)
	panel.add_child(close_btn)

	# ---- 布局：左网格 + 右详情 ----
	var margin: float = 36.0
	var top_res: float = 88.0       # 给标题留高度
	var bot_res: float = 40.0
	var detail_w: float = clampf(vw * 0.30, 280.0, 372.0)
	var sep: float = 22.0
	var grid_area_w: float = vw - margin * 2.0 - detail_w - sep
	var gap: float = 10.0
	var avail_w: float = grid_area_w - (COLS - 1) * gap
	var avail_h: float = vh - top_res - bot_res - (ROWS - 1) * gap
	var cell: float = maxf(40.0, minf(avail_w / float(COLS), avail_h / float(ROWS)))
	var grid_w: float = COLS * cell + (COLS - 1) * gap
	var grid_h: float = ROWS * cell + (ROWS - 1) * gap
	var gx: float = margin
	var gy: float = top_res + (vh - top_res - bot_res - grid_h) / 2.0
	var lock_sz: float = cell * 0.4
	var lock_tex := _make_lock_texture(int(maxf(20.0, lock_sz)))
	var cnt_font: int = int(clampf(cell * 0.26, 12.0, 20.0))
	var icon_sz: float = cell * 0.64

	for i in range(TOTAL):
		var r := i / COLS
		var c := i % COLS
		var slot := Panel.new()
		slot.position = Vector2(gx + c * (cell + gap), gy + r * (cell + gap))
		slot.size = Vector2(cell, cell)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(maxi(6, int(cell * 0.10)))
		sb.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", sb)
		panel.add_child(slot)

		# 物品图标（空格子隐藏）
		var icon := TextureRect.new()
		icon.texture = null
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(cell / 2.0 - icon_sz / 2.0, cell / 2.0 - icon_sz / 2.0)
		icon.size = Vector2(icon_sz, icon_sz)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		slot.add_child(icon)

		# 右下角数量
		var cnt := Label.new()
		cnt.add_theme_font_size_override("font_size", cnt_font)
		cnt.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		cnt.add_theme_constant_override("outline_size", 4)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cnt.position = Vector2(4, cell - cnt_font * 1.5 - 4)
		cnt.size = Vector2(cell - 8, cnt_font * 1.5)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt.visible = false
		slot.add_child(cnt)

		# 锁定图标（未解锁格显示）
		var lock := TextureRect.new()
		lock.texture = lock_tex
		lock.position = Vector2(cell / 2.0 - lock_sz / 2.0, cell / 2.0 - lock_sz / 2.0)
		lock.size = Vector2(lock_sz, lock_sz)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lock)

		# 点击层（整格可点）
		var hit := Button.new()
		hit.text = ""
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(_on_slot_clicked.bind(i))
		slot.add_child(hit)

		_cells.append({"sb": sb, "lock": lock, "icon": icon, "cnt": cnt})

	# 右侧详情面板
	_build_detail(panel, vw - margin - detail_w, top_res, detail_w, vh - top_res - bot_res)

	# 解锁确认弹窗
	_build_unlock_dialog(vw, vh)

	GameState.bag_changed.connect(_refresh)
	GameState.stats_changed.connect(_refresh)
	_refresh()

# ============================================================
#  右侧详情面板：显示选中物品的名称 / 数量 / 用处 / 来源
# ============================================================
# _build_detail(parent, x, y, w, h)：在 (x,y) 处构建右侧详情面板。含图标、名称、持有数量、
# 分隔线、「用处」「来源」两段说明。参数均为面板内布局坐标与尺寸。
func _build_detail(parent: Control, x: float, y: float, w: float, h: float):
	var dp := Panel.new()
	dp.name = "DetailPanel"
	dp.position = Vector2(x, y)
	dp.size = Vector2(w, h)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.14, 0.145, 0.175, 0.96)
	ds.set_border_width_all(2)
	ds.border_color = Color(0.34, 0.36, 0.42, 0.95)
	ds.set_corner_radius_all(12)
	dp.add_theme_stylebox_override("panel", ds)
	parent.add_child(dp)

	var pad: float = 20.0
	var inner_w: float = w - pad * 2.0

	# 未选中时的提示
	_detail_empty = Label.new()
	_detail_empty.text = "点击左侧格子中的物品\n查看它的用处和来源"
	_detail_empty.add_theme_font_size_override("font_size", 15)
	_detail_empty.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
	_detail_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_empty.position = Vector2(pad, 0)
	_detail_empty.size = Vector2(inner_w, h)
	_detail_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.add_child(_detail_empty)

	var iw: float = 92.0
	_detail_icon = TextureRect.new()
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.position = Vector2((w - iw) / 2.0, pad + 6)
	_detail_icon.size = Vector2(iw, iw)
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.add_child(_detail_icon)

	_detail_name = _make_label(dp, pad, pad + iw + 14, inner_w, 30, 22,
		Color(0.96, 0.96, 0.96), HORIZONTAL_ALIGNMENT_CENTER)
	_detail_count = _make_label(dp, pad, pad + iw + 48, inner_w, 22, 14,
		Color(0.72, 0.75, 0.80), HORIZONTAL_ALIGNMENT_CENTER)

	# 分隔线
	var line := ColorRect.new()
	line.color = Color(0.32, 0.34, 0.39, 0.9)
	line.position = Vector2(pad, pad + iw + 80)
	line.size = Vector2(inner_w, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.add_child(line)

	var cy: float = pad + iw + 96
	var use_title := _make_label(dp, pad, cy, inner_w, 20, 13, Color(0.60, 0.72, 0.52))
	use_title.text = "用处"
	cy += 24
	_detail_use = _make_label(dp, pad, cy, inner_w, 84, 16, Color(0.90, 0.92, 0.94))
	_detail_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cy += 88
	var src_title := _make_label(dp, pad, cy, inner_w, 20, 13, Color(0.72, 0.66, 0.48))
	src_title.text = "来源"
	cy += 24
	_detail_source = _make_label(dp, pad, cy, inner_w, 84, 16, Color(0.90, 0.92, 0.94))
	_detail_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cy += 90

	# ---- 卖出区（只有有售价的物品才显示；默认隐藏）----
	# 「卖1 个」/「全部卖出」两个按钮；由 _show_detail 根据当前选中物品的 ITEM_SELL_PRICE 决定显隐。
	var bw: float = (inner_w - 10.0) * 0.5
	_sell_one_btn = Button.new()
	_sell_one_btn.text = "卖出 1 个"
	_sell_one_btn.add_theme_font_size_override("font_size", 16)
	_sell_one_btn.position = Vector2(pad, cy)
	_sell_one_btn.size = Vector2(bw, 44)
	_sell_one_btn.pressed.connect(_on_sell_one)
	dp.add_child(_sell_one_btn)

	_sell_all_btn = Button.new()
	_sell_all_btn.add_theme_font_size_override("font_size", 16)
	_sell_all_btn.position = Vector2(pad + bw + 10.0, cy)
	_sell_all_btn.size = Vector2(bw, 44)
	_sell_all_btn.pressed.connect(_on_sell_all)
	dp.add_child(_sell_all_btn)

# _make_label(...)：复用的 Label 构造器，在 (x,y) 处建一个 w×h、指定字号/颜色/对齐的 Label
# 并加入 parent，返回引用方便后续改文本。默认左对齐，可传 halign 改居中。
func _make_label(parent: Control, x: float, y: float, w: float, h: float,
		font_size: int, col: Color,
		halign: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = halign
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# _show_detail(item_id)：在右侧详情面板展示某物品——图标、名称、持有数量、用处、来源。
# 物品定义(名称/用处/来源)来自 GameState.item_def。
func _show_detail(item_id: String):
	var d := GameState.item_def(item_id)
	if d.is_empty():
		_clear_detail()
		return
	_sel_item_id = item_id
	_detail_empty.visible = false
	_detail_icon.visible = true
	_detail_icon.texture = GameState.item_icon_tex(item_id)
	_detail_name.text = String(d.get("name", item_id))
	_detail_count.text = "持有数量：%d" % GameState.item_count(item_id)
	_detail_use.text = String(d.get("use", "暂无说明"))
	_detail_source.text = String(d.get("source", "未知"))
	# 卖出区：只有物品在 ITEM_SELL_PRICE 里且持有 > 0 时才显示
	var price := GameState.item_sell_price(item_id)
	var have := GameState.item_count(item_id)
	var can_sell := price > 0 and have > 0
	if _sell_one_btn != null:
		_sell_one_btn.visible = can_sell
		_sell_one_btn.text = "卖出 1 个\n+%d 金币" % price
	if _sell_all_btn != null:
		_sell_all_btn.visible = can_sell
		_sell_all_btn.text = "全部卖出（%d 个）\n+%d 金币" % [have, price * have]

# _on_sell_one()：卖出当前选中物品的 1 个。
func _on_sell_one():
	if _sel_item_id == "":
		return
	var price := GameState.item_sell_price(_sel_item_id)
	var got := GameState.sell_item(_sel_item_id, 1)
	if got > 0:
		_toast("卖出 %s ×1，获得 %d 金币" % [GameState.item_name(_sel_item_id), price * got])
	# 卖完最后一件时该物品已不在背包 → 切回空详情
	if GameState.item_count(_sel_item_id) <= 0:
		_clear_detail()
	_refresh()
	_show_detail(_sel_item_id)

# _on_sell_all()：卖出当前选中物品的全部持有数量。
func _on_sell_all():
	if _sel_item_id == "":
		return
	var id := _sel_item_id
	var price := GameState.item_sell_price(id)
	var had := GameState.item_count(id)
	var got := GameState.sell_all_of(id)
	if got > 0:
		_toast("卖出 %s ×%d，获得 %d 金币" % [GameState.item_name(id), got, price * got])
	_clear_detail()
	_refresh()
	if had - got > 0:
		_show_detail(id)

# _clear_detail()：清空右侧详情（恢复占位提示、隐藏图标、清空文本）。取消选中时调用。
func _clear_detail():
	_detail_empty.visible = true
	_detail_icon.visible = false
	_detail_icon.texture = null
	_detail_name.text = ""
	_detail_count.text = ""
	_detail_use.text = ""
	_detail_source.text = ""
	_sel_item_id = ""
	if _sell_one_btn != null:
		_sell_one_btn.visible = false
	if _sell_all_btn != null:
		_sell_all_btn.visible = false

# 下一批（5 格）解锁价格
# _next_batch_cost()：返回下一批(5 格)解锁所需金币。按当前已解锁数换算批次下标(0~3)，
# 落到 UNLOCK_COSTS 对应价格。
func _next_batch_cost() -> int:
	var unlocked: int = GameState.bag_unlocked
	# 第几批（0 起）：20→0, 25→1, 30→2, 35→3
	var batch_idx: int = clampi((unlocked - FREE) / BATCH, 0, UNLOCK_COSTS.size() - 1)
	return int(UNLOCK_COSTS[batch_idx])

# _refresh()：背包核心刷新。遍历 40 格——已解锁格显示物品图标+数量，未解锁格显示灰底+锁
# （下一批 5 格额外绿边高亮）；选中格金边。若选中格已失效则清空详情。并同步已用格数与弹窗状态。
func _refresh():
	var unlocked: int = GameState.bag_unlocked
	var order: Array = GameState.bag_order
	for i in range(_cells.size()):
		var cel: Dictionary = _cells[i]
		var sb: StyleBoxFlat = cel["sb"]
		var lock: TextureRect = cel["lock"]
		var icon: TextureRect = cel["icon"]
		var cnt: Label = cel["cnt"]
		if i < unlocked:
			# 已解锁：普通格子
			sb.bg_color = Color(0.16, 0.17, 0.20, 0.95)
			sb.border_color = Color(0.42, 0.44, 0.48, 0.9)
			lock.visible = false
			# 有物品则显示图标 + 数量；物品后面跟两个弹药展示位（手雷/支援导弹）
			if i < order.size():
				var id := String(order[i])
				icon.texture = GameState.item_icon_tex(id)
				icon.visible = true
				cnt.text = str(GameState.item_count(id))
				cnt.visible = true
			elif i - order.size() < AMMO_SLOTS.size():
				var ammo: Dictionary = AMMO_SLOTS[i - order.size()]
				icon.texture = _ammo_icon_tex(ammo)
				icon.visible = true
				cnt.text = str(int(GameState.get(String(ammo["ammo_var"]))))
				cnt.visible = true
			else:
				icon.visible = false
				cnt.visible = false
		else:
			# 未解锁：暗色 + 锁
			sb.bg_color = Color(0.10, 0.10, 0.12, 0.95)
			sb.border_color = Color(0.42, 0.34, 0.34, 0.85)
			lock.visible = true
			icon.visible = false
			cnt.visible = false
		# 下一批 5 格：绿边高亮（点它弹解锁框）
		if i >= unlocked and i < unlocked + BATCH:
			sb.border_color = Color(0.5, 0.85, 0.45, 0.95)
		# 选中格：金色高亮
		if i == _selected_slot:
			sb.border_color = Color(1.0, 0.84, 0.32, 1.0)
	# 选中格被解锁/物品被消耗后清空选中（弹药展示位也算有效选中目标）
	if _selected_slot >= 0:
		if _selected_slot >= unlocked or _selected_slot >= order.size() + AMMO_SLOTS.size():
			_selected_slot = -1
			_clear_detail()
		elif _selected_slot < order.size():
			_show_detail(String(order[_selected_slot]))
		else:
			_show_ammo_detail(AMMO_SLOTS[_selected_slot - order.size()])
	# 同步「已用 x / y 格」
	if _sub_label != null:
		_sub_label.text = "已用 %d / %d 格" % [GameState.bag_used_slots(), GameState.bag_unlocked]
	# 弹窗开着时同步价格/可点状态
	if _dialog != null and _dialog.visible:
		_sync_dialog()

# ============================================================
#  解锁确认弹窗
# ============================================================
# _build_unlock_dialog(vw, vh)：构建解锁 5 格的确认弹窗（遮罩 + 居中面板 + 提示文字 +
# 价格按钮 + 取消按钮），初始隐藏。价格按钮文字/可点状态在 _sync_dialog 里动态更新。
func _build_unlock_dialog(vw: float, vh: float):
	_dialog = Control.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dialog)
	# 半透明遮罩（点空白处取消）
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.gui_input.connect(_on_dim_input)
	_dialog.add_child(dim)
	# 弹窗面板
	var pw: float = 460.0
	var ph: float = 210.0
	var panel := Panel.new()
	panel.position = Vector2((vw - pw) / 2.0, (vh - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.13, 0.13, 0.16, 0.99)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.5, 0.5, 0.55, 0.9)
	ps.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", ps)
	_dialog.add_child(panel)
	# 提示文字
	_dialog_msg = Label.new()
	_dialog_msg.text = "是否解锁 5 个额外的背包格子？"
	_dialog_msg.add_theme_font_size_override("font_size", 20)
	_dialog_msg.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_dialog_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_msg.position = Vector2(20, 52)
	_dialog_msg.size = Vector2(pw - 40, 30)
	panel.add_child(_dialog_msg)
	# 价格选项框（点击解锁）
	_dialog_price_btn = Button.new()
	_dialog_price_btn.add_theme_font_size_override("font_size", 22)
	_dialog_price_btn.position = Vector2(90, 118)
	_dialog_price_btn.size = Vector2(pw - 180, 56)
	_dialog_price_btn.pressed.connect(_do_unlock)
	panel.add_child(_dialog_price_btn)
	# 取消按钮
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	cancel.flat = true
	cancel.position = Vector2(pw - 84, 12)
	cancel.size = Vector2(72, 30)
	cancel.pressed.connect(_hide_dialog)
	panel.add_child(cancel)
	_dialog.hide()

# _sync_dialog()：刷新弹窗价格按钮文字「解锁 5 格（￥N）」与可点状态
# （已全满或金币不足则禁用）。
func _sync_dialog():
	var cost := _next_batch_cost()
	_dialog_price_btn.text = "解锁 5 格（￥%d）" % cost
	_dialog_price_btn.disabled = (GameState.bag_unlocked >= TOTAL) or (GameState.gold < cost)

# _show_unlock_dialog()：已全满则忽略；否则同步价格并显示弹窗。
func _show_unlock_dialog():
	if GameState.bag_unlocked >= TOTAL:
		return
	_sync_dialog()
	_dialog.show()

# _hide_dialog()：隐藏解锁确认弹窗。
func _hide_dialog():
	_dialog.hide()

# _on_slot_clicked(i)：点击某格。未解锁格中，只有「下一批 5 格」点开解锁弹窗，其余未解锁格忽略；
# 已解锁格：有物品则选中并显示详情（再次点同一格取消选中），空格子取消选中。最后刷新。
func _on_slot_clicked(i: int):
	# 未解锁格：只有「下一批 5 格」点了会弹解锁框
	if i >= GameState.bag_unlocked:
		if i < GameState.bag_unlocked + BATCH:
			_show_unlock_dialog()
		return
	# 已解锁格：有物品或弹药展示位就选中并显示详情，空格子取消选中
	if i < GameState.bag_order.size():
		if _selected_slot == i:
			_selected_slot = -1
			_clear_detail()
		else:
			_selected_slot = i
			_show_detail(String(GameState.bag_order[i]))
	elif i - GameState.bag_order.size() < AMMO_SLOTS.size():
		if _selected_slot == i:
			_selected_slot = -1
			_clear_detail()
		else:
			_selected_slot = i
			_show_ammo_detail(AMMO_SLOTS[i - GameState.bag_order.size()])
	else:
		_selected_slot = -1
		_clear_detail()
	_refresh()

# _ammo_icon_tex(ammo)：弹药条目图标——优先读 art/ 下的 PNG，缺文件时画纯色方块兜底，永不为 null。
func _ammo_icon_tex(ammo: Dictionary) -> Texture2D:
	var path := String(ammo.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	var col: Color = ammo.get("color", Color(0.6, 0.6, 0.6))
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(6, 26):
		for x in range(6, 26):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

# _show_ammo_detail(ammo)：右侧详情展示弹药条目（手雷/支援导弹）。
# 它们不是背包物品（无 item_def），文案取自 AMMO_SLOTS，持有数读 GameState 弹药字段；
# 伤害数值取当前选中人物算上天赋加成后的最终伤害（Characters.stats_for），并标注爆炸半径。
func _show_ammo_detail(ammo: Dictionary):
	_detail_empty.visible = false
	_detail_icon.visible = true
	_detail_icon.texture = _ammo_icon_tex(ammo)
	_detail_name.text = String(ammo.get("name", ""))
	_detail_count.text = "持有数量：%d" % int(GameState.get(String(ammo["ammo_var"])))
	var dmg: int = int(GameState.char_stats(GameState.selected_character).get(String(ammo.get("dmg_key", "")), 0))
	_detail_use.text = "%s\n伤害 %d · 爆炸半径 %d" % [String(ammo.get("use", "暂无说明")), dmg, int(ammo.get("radius", 0))]
	_detail_source.text = String(ammo.get("source", "未知"))
	# 弹药不是背包物品、不可卖→ 隐藏卖出区
	_sel_item_id = ""
	if _sell_one_btn != null:
		_sell_one_btn.visible = false
	if _sell_all_btn != null:
		_sell_all_btn.visible = false

# _toast(text)：屏幕底部居中飘一行提示（1.4 秒淡出）。卖出物品时反馈收益。
func _toast(text: String):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 300.0, vh - 96.0)
	lbl.size = Vector2(600, 32)
	add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.8)
	tw.tween_callback(lbl.queue_free)

# _on_dim_input(event)：弹窗遮罩被鼠标按下时取消（关闭弹窗）。
func _on_dim_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_hide_dialog()

# _do_unlock()：点价格按钮真正解锁——扣金币、bag_unlocked +5（封顶 40）、保存、发 stats_changed 信号、
# 关闭弹窗。金币不足则直接返回（按钮本身也已禁用，这里是二次保护）。
func _do_unlock():
	if GameState.bag_unlocked >= TOTAL:
		_hide_dialog()
		return
	var cost := _next_batch_cost()
	if GameState.gold < cost:
		return
	GameState.gold -= cost
	GameState.bag_unlocked = mini(GameState.bag_unlocked + BATCH, TOTAL)
	GameState.save_profile()
	GameState.stats_changed.emit()
	_hide_dialog()

# _make_lock_texture(size)：用 Image 画一个小锁图标（锁环 + 锁体），不依赖素材，返回贴图。
func _make_lock_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var col := Color(0.72, 0.74, 0.78, 0.9)
	var cx := size / 2.0
	var body_l := size * 0.26
	var body_r := size * 0.74
	var body_t := size * 0.46
	var body_b := size * 0.82
	var sr := size * 0.18
	var scy := size * 0.44
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var is_body: bool = p.x >= body_l and p.x <= body_r and p.y >= body_t and p.y <= body_b
			var d := Vector2(cx, scy).distance_to(p)
			var is_shackle: bool = d <= sr and d >= sr - maxf(2.0, size * 0.10) and p.y <= scy
			if is_body or is_shackle:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
