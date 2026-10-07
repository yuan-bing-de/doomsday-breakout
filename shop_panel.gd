extends Control

# ============================================================================
# shop_panel.gd —— 商店界面（从主界面右上角「商店」按钮打开）
# 顶部：标题 + 刷新说明 + 金币/钻石胶囊 HUD（余额随 GameState.stats_changed 实时刷新）
# 商品卡片（五张，多列网格排列，一屏放得下）：
#   ① 腐肉（rotten_meat） ② 精魂（soul） ③ 医疗包（medkit）
#   ④ 手雷（grenade）     ⑤ 支援导弹（missile）
# 每张卡片：图标 / 名称 / 用途 / 来源 / 当前持有数量 / 一个购买按钮
#
# 购买规则（三条）：
#   1. 每种商品只有一种购买方式——固定数量 + 固定价格，见 SHOP_ITEMS 的 n / price
#   2. 每种商品每天只能买一次，买完按钮变「今日已购买」并置灰
#   3. 跨自然日自动刷新（GameState._ensure_shop 比对 Time 日期字符串）
#
# 商品分两类（见 SHOP_ITEMS 的 kind 字段）：
#   - "item"（背包物品）：走 GameState.add_item，背包满则不扣钱不发货
#   - "ammo"（弹药）     ：没有 ITEM_DEFS 条目，直接累加 GameState 的弹药字段
# 购买流程：校验限购 → 校验金币 → 发货（失败则中止）→ 扣金币 → 记账 → 存档 → 广播信号
# 物品与货币数据全部来自 GameState，本脚本不持有任何状态。
# ============================================================================

# 商品总表。
#   kind  = "item"（背包物品，文案与图标取自 GameState.item_def）
#           或 "ammo"（弹药，文案硬编码，持有数存在 GameState 的 ammo_var 字段）
#   n     = 一次买多少个（唯一的购买档位）
#   price = 该档位总价（金币）
# 因为每天只能买一次，档位取的是原来三档里的中间档——既不是零买试水，也不是一次囤满。
# 价格是中间档原价的 10 倍（用户要求整体上调一个数量级），用于拉开金币的消耗压力。
const SHOP_ITEMS := [
	{
		"id": "rotten_meat", "kind": "item", "n": 10, "price": 1800,
		"icon": "", "color": Color(0.58, 0.30, 0.32),
	},
	{
		"id": "soul", "kind": "item", "n": 1, "price": 6000,
		"icon": "", "color": Color(0.45, 0.65, 0.95),
	},
	{
		"id": "medkit", "kind": "item", "n": 5, "price": 9000,
		"icon": "", "color": Color(0.20, 0.78, 0.36),
	},
	{
		"id": "grenade", "kind": "ammo", "ammo_var": "grenade_ammo", "n": 20, "price": 14000,
		"name": "手雷", "use": "局内按 G 投掷，范围爆炸伤害", "source": "商店用金币购买",
		"icon": "res://art/item_grenade.png", "color": Color(0.55, 0.62, 0.30),
	},
	{
		"id": "missile", "kind": "ammo", "ammo_var": "missile_ammo", "n": 10, "price": 22000,
		"name": "支援导弹", "use": "局内按 H 呼叫，范围轰炸", "source": "商店用金币购买",
		"icon": "res://art/item_missile.png", "color": Color(0.75, 0.40, 0.28),
	},
]

# 布局常量：卡片尺寸刻意压到能在一屏内排成多列（视口基准 1152×648）
const CARD_H := 172.0
const CARD_GAP := 16.0
const MARGIN_X := 36.0

var _gold_label: Label = null                 # 顶部金币余额 Label（由 GameState.build_currency_hud 返回）
var _own_rows: Array = []                     # 每张卡片的「持有 N」行：[{entry, lbl}]
var _buy_btns: Array = []                     # 购买按钮缓存：[{btn, entry, n, price}]

# _ready()：商店入口。铺满视口后构建界面，并订阅 GameState 的金币/背包变化信号。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.stats_changed.connect(_refresh)
	GameState.bag_changed.connect(_refresh)

# _exit_tree()：面板销毁时断开信号，避免回调指向已释放的节点。
func _exit_tree():
	if not is_instance_valid(GameState):
		return
	if GameState.stats_changed.is_connected(_refresh):
		GameState.stats_changed.disconnect(_refresh)
	if GameState.bag_changed.is_connected(_refresh):
		GameState.bag_changed.disconnect(_refresh)

# _build()：构建商店界面——全屏深色底、标题、刷新说明、关闭按钮、顶部货币 HUD，
# 以及一个 ScrollContainer 包裹的商品网格（多列，视口宽够就排 3 列，否则 2 列）。
func _build():
	var vw := get_viewport().get_visible_rect().size.x

	# 全屏深色底
	var panel := Panel.new()
	panel.name = "ShopRoot"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	# 标题
	var title := Label.new()
	title.text = "商店"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.position = Vector2(MARGIN_X, 20)
	panel.add_child(title)

	# 刷新说明：紧跟标题右侧，把「限购一次 / 每日刷新」讲清楚
	var hint := Label.new()
	hint.text = "每种商品每日限购 1 次，次日 00:00 刷新"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	hint.position = Vector2(MARGIN_X + 74, 32)
	panel.add_child(hint)

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

	# 顶部货币 HUD（金币 + 钻石），金币 Label 留给 _refresh 更新
	var hud := GameState.build_currency_hud(self, MARGIN_X, 62.0)
	_gold_label = hud["gold"]

	# ---- 商品卡片区（多列网格，一屏放得下；仍包 ScrollContainer 兜底窄窗口）----
	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 110.0       # 顶部留出标题 + 说明 + 货币 HUD
	scroll.offset_bottom = -20.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var usable_w: float = vw - MARGIN_X * 2.0
	# 宽屏排 3 列；窄窗口退回 2 列，避免卡片被压得太窄看不清文字
	var cols := 3 if usable_w >= 900.0 else 2
	var card_w: float = (usable_w - CARD_GAP * float(cols - 1)) / float(cols)
	var count := SHOP_ITEMS.size()
	var rows: int = ceili(float(count) / float(cols))
	var pad_top := 8.0
	var pad_bottom := 20.0
	var content_h: float = pad_top + float(rows) * CARD_H + float(maxi(0, rows - 1)) * CARD_GAP + pad_bottom

	var content := Control.new()
	content.name = "ShopContent"
	content.custom_minimum_size = Vector2(vw, content_h)
	scroll.add_child(content)

	for i in range(count):
		var entry: Dictionary = SHOP_ITEMS[i]
		var col := i % cols
		var row := i / cols
		var x := MARGIN_X + float(col) * (card_w + CARD_GAP)
		var y := pad_top + float(row) * (CARD_H + CARD_GAP)
		_build_item_card(content, entry, x, y, card_w)

	_refresh()

# _entry_text(entry, key)：取商品文案。背包物品从 GameState.item_def 取（name/use/source），
# 弹药则用 SHOP_ITEMS 里硬编码的中文（它们不是背包物品，没有 item_def）。
func _entry_text(entry: Dictionary, key: String) -> String:
	if String(entry.get("kind", "item")) != "item":
		return String(entry.get(key, ""))
	var id := String(entry["id"])
	var fallback := ""
	if key == "name":
		fallback = id
	return String(GameState.item_def(id).get(key, fallback))

# _entry_icon_tex(entry)：取商品图标。背包物品走 GameState.item_icon_tex（内部已兜底）；
# 弹药直接读 art/ 下的 PNG，缺文件时画一个纯色方块，保证不崩溃。
func _entry_icon_tex(entry: Dictionary) -> Texture2D:
	if String(entry.get("kind", "item")) == "item":
		return GameState.item_icon_tex(String(entry["id"]))
	var path := String(entry.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	var col: Color = entry.get("color", Color(0.6, 0.6, 0.6))
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for yy in range(6, s - 6):
		for xx in range(6, s - 6):
			img.set_pixel(xx, yy, col)
	return ImageTexture.create_from_image(img)

# _entry_count(entry)：取当前持有数量。背包物品读 item_count，弹药读 GameState 的弹药字段。
func _entry_count(entry: Dictionary) -> int:
	if String(entry.get("kind", "item")) == "item":
		return GameState.item_count(String(entry["id"]))
	return int(GameState.get(String(entry["ammo_var"])))

# _build_item_card(parent, entry, x, y, card_w)：构建一张紧凑商品卡片（172 高）。
# 内容：图标（52×52）/ 名称 / 用途 / 来源 / 当前持有数量 + 一个购买按钮。
# 持有数存进 _own_rows、按钮存进 _buy_btns，供 _refresh 更新。
func _build_item_card(parent: Control, entry: Dictionary, x: float, y: float, card_w: float) -> void:
	var item_id := String(entry["id"])

	var card := Panel.new()
	card.name = "%sCard" % item_id
	card.position = Vector2(x, y)
	card.size = Vector2(card_w, CARD_H)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.14, 0.14, 0.17, 0.95)
	cs.border_color = Color(0.40, 0.40, 0.40, 0.8)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	# 图标（64×64）。_entry_icon_tex 内部已做兜底：缺 PNG 时画占位色块，永不为 null。
	var icon := TextureRect.new()
	var tex := _entry_icon_tex(entry)
	if tex != null:
		icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(12, 12)
	icon.size = Vector2(64, 64)
	card.add_child(icon)

	var text_x := 88.0
	var text_w: float = card_w - text_x - 14.0

	# 名称
	var name_lbl := Label.new()
	name_lbl.text = _entry_text(entry, "name")
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	name_lbl.position = Vector2(text_x, 12)
	name_lbl.size = Vector2(text_w, 24)
	card.add_child(name_lbl)

	# 用途
	var use_lbl := Label.new()
	use_lbl.text = "用途：%s" % _entry_text(entry, "use")
	use_lbl.add_theme_font_size_override("font_size", 11)
	use_lbl.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	use_lbl.position = Vector2(text_x, 38)
	use_lbl.size = Vector2(text_w, 18)
	card.add_child(use_lbl)

	# 来源
	var src_lbl := Label.new()
	src_lbl.text = "来源：%s" % _entry_text(entry, "source")
	src_lbl.add_theme_font_size_override("font_size", 11)
	src_lbl.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	src_lbl.position = Vector2(text_x, 56)
	src_lbl.size = Vector2(text_w, 18)
	card.add_child(src_lbl)

	# 当前持有数量（存进 _own_rows，_refresh 按商品刷新）
	var own_lbl := Label.new()
	own_lbl.text = "持有 %d" % _entry_count(entry)
	own_lbl.add_theme_font_size_override("font_size", 13)
	own_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.60))
	own_lbl.position = Vector2(text_x, 78)
	own_lbl.size = Vector2(text_w, 20)
	card.add_child(own_lbl)
	_own_rows.append({"entry": entry, "lbl": own_lbl})

	# 唯一的购买按钮：固定数量 + 固定价格
	var n := int(entry["n"])
	var price := int(entry["price"])
	var btn := Button.new()
	btn.name = "%sBuyBtn" % item_id
	btn.add_theme_font_size_override("font_size", 14)
	btn.position = Vector2(14.0, 118.0)
	btn.size = Vector2(card_w - 28.0, 42)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_buy.bind(entry, n, price))
	card.add_child(btn)
	_buy_btns.append({"btn": btn, "entry": entry, "n": n, "price": price})

# _refresh()：同步顶部金币余额、每张卡片的持有数量，以及购买按钮的状态。
# 按钮三种状态：今日已买（置灰，文案「今日已购买」）/ 金币不足（置灰）/ 可购买（高亮）。
func _refresh():
	if _gold_label != null:
		_gold_label.text = "%d" % GameState.gold
	for row in _own_rows:
		var lbl: Label = row["lbl"]
		if is_instance_valid(lbl):
			lbl.text = "持有 %d" % _entry_count(row["entry"])
	for e in _buy_btns:
		var btn: Button = e["btn"]
		if not is_instance_valid(btn):
			continue
		var id := String(Dictionary(e["entry"]).get("id", ""))
		if not GameState.shop_can_buy(id):
			btn.text = "今日已购买"
			btn.disabled = true
		else:
			btn.text = "购买 ×%d（%d 金币）" % [int(e["n"]), int(e["price"])]
			btn.disabled = GameState.gold < int(e["price"])

# _on_buy(entry, n, price)：购买 n 个指定商品。
# 顺序：校验今日限购 → 校验金币 → 按 kind 发货（背包满则中止且不扣钱）
#      → 扣金币 → 记入今日已买 → 存档（profile + tasks）→ 广播 → 飘字 → 刷新。
func _on_buy(entry: Dictionary, n: int, price: int):
	var item_id := String(entry["id"])
	if not GameState.shop_can_buy(item_id):
		_toast("今日已购买，明日刷新")
		return
	if GameState.gold < price:
		_toast("金币不足")
		return
	if String(entry.get("kind", "item")) == "item":
		# 先尝试入包再扣钱：add_item 背包满会返回 false，避免扣了钱没拿到东西
		if not GameState.add_item(item_id, n):
			_toast("背包已满，放不下")
			return
	else:
		# 弹药不是背包物品（无 ITEM_DEFS 条目，不能走 add_item），直接累加 GameState 的弹药字段
		var prop := String(entry["ammo_var"])
		GameState.set(prop, int(GameState.get(prop)) + n)
	GameState.gold -= price
	GameState.shop_mark_bought(item_id)
	GameState.save_profile()
	GameState.save_tasks()      # shop_bought 存在 tasks 档里，必须单独存一次
	GameState.stats_changed.emit()
	_toast("购买成功 ×%d" % n)
	_refresh()

# _toast(text)：居中偏下弹出一行飘字（1.2 秒后自动 queue_free），用于金币不足等轻量反馈。
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
