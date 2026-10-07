extends Control

# ============================================================================
# profile_panel.gd —— 个人游戏账号界面
# ============================================================================
# Hub 左上角点圆形头像打开。布局：
#   左边：大头像（圆形），正下方「修改头像」按钮 → 切到头像选择页（6 个头像格子）
#   右边：第一行 玩家ID + 「修改」按钮 → 就地变输入框，确定后保存
#   另附 等级/金币/钻石 只读行
# 头像与 ID 存 GameState（ConfigFile 持久化 user://player_profile.cfg）。
# ============================================================================

signal profile_changed              # 头像/ID 变更后发出，供主界面刷新左上角头像

const PANEL_W := 760.0               # 账号面板宽
const PANEL_H := 440.0               # 账号面板高

var _panel: Panel                    # 居中面板根
var _profile_page: Control           # 页面一：资料页
var _avatar_page: Control            # 页面二：头像选择页
var _avatar_img: TextureRect         # 资料页大头像
var _sel_ring: Panel                 # 头像选择页的黄色选中框（跟随选中项移动）
var _id_label: Label                 # 玩家ID 文字
var _id_edit: LineEdit               # ID 编辑输入框（默认隐藏）
var _id_ok_btn: Button               # ID 确定按钮
var _id_edit_btn: Button             # ID 修改按钮
var _close_btn: Button               # 关闭(✕)按钮
var _panel_title: Label              # 面板顶部标题「个人账号」（头像选择页时需隐藏，避免与「选择头像」重叠）
var _stat_labels := {}               # 只读统计行引用：{"等级":Label,"金币":Label,"钻石":Label}
var _rules_layer: Control = null     # 升级规则「?」弹层

# _ready()：账号界面入口。铺满视口 → 建遮罩/面板/资料页/头像选择页 → 刷新。
# 处理 --avatarshot 渲染自测参数（默认直接打开头像选择页）。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_overlay()
	_build_panel()
	_build_profile_page()
	_build_avatar_page()
	_refresh()
	# 渲染自测参数：直接打开头像选择页
	if "--avatarshot" in OS.get_cmdline_args():
		_show_page(true)

# _show_page(avatar)：切换 资料页/头像选择页，并同步面板标题的可见性——
# 「个人账号」与「选择头像」两个标题都在面板顶部同一位置，必须互斥显示，否则叠成乱码。
func _show_page(avatar: bool):
	_profile_page.visible = not avatar
	_avatar_page.visible = avatar
	_panel_title.visible = not avatar

# ---------------------------------------------------------------------------
# _build_overlay()：建一层半透明遮罩（挡住下层点击），作为面板底层背景。
func _build_overlay():
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 挡住下层点击
	add_child(dim)

# _build_panel()：构建居中账号面板（绿边圆角）+ 标题「个人账号」+ 关闭按钮(✕)，并处理 --closetest 自测。
func _build_panel():
	_panel = Panel.new()
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	_panel.position = Vector2((vw - PANEL_W) / 2.0, (vh - PANEL_H) / 2.0)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.15, 0.98)
	sb.border_color = Color(0.4, 1.0, 0.6, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	# 标题
	var t := Label.new()
	t.text = "个人账号"
	t.position = Vector2(PANEL_W / 2.0 - 60, 14)
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	_panel.add_child(t)
	_panel_title = t   # 存引用：切到头像选择页时要隐藏，否则和「选择头像」叠字
	# 关闭按钮（右上角 ✕）
	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.add_theme_font_size_override("font_size", 22)
	_close_btn.custom_minimum_size = Vector2(44, 44)
	_close_btn.position = Vector2(PANEL_W - 56, 12)
	_close_btn.pressed.connect(queue_free)
	_panel.add_child(_close_btn)
	# 行为自测：验证 ✕ 按钮信号能触发关闭
	if "--closetest" in OS.get_cmdline_args():
		_close_btn.pressed.emit()
		print("CLOSETEST ok=", _close_btn.is_queued_for_deletion())
		get_tree().quit()

# _make_button(txt, pos, sz, fs)：复用的按钮构造器，在 _panel 内 (pos) 处建一个 sz 尺寸、fs 字号的按钮。
func _make_button(txt: String, pos: Vector2, sz: Vector2, fs: int = 20) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = sz
	b.position = pos
	b.size = sz
	_panel.add_child(b)
	return b

# ---------------------------------------------------------------------------
# 页面一：资料页（左头像+修改头像按钮，右 ID+修改，下面统计行）
# ---------------------------------------------------------------------------
# _build_profile_page()：构建资料页——左大头像+圆形描边+「修改头像」按钮；右玩家ID+「修改」按钮+
# 就地编辑框/确定按钮（默认隐藏）；下方等级/金币/钻石只读行；右上「?」升级规则按钮。
# 整页 mouse_filter=IGNORE 以免挡住 ✕（子按钮仍可点）。
func _build_profile_page():
	_profile_page = Control.new()
	_profile_page.position = Vector2.ZERO
	_profile_page.size = Vector2(PANEL_W, PANEL_H)
	# 必须 IGNORE：否则这个铺满面板的透明 Control 会截住所有点击，
	# 导致底下的 ✕ 关闭按钮收不到（子按钮不受影响，仍可点击）
	_profile_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_profile_page)

	# 左：头像 + 圆形描边圈
	var ring := Panel.new()
	ring.position = Vector2(52, 82)
	ring.size = Vector2(192, 192)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0)
	rsb.border_color = Color(0.4, 1.0, 0.6, 0.95)
	rsb.set_border_width_all(3)
	rsb.set_corner_radius_all(999)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", rsb)
	_profile_page.add_child(ring)
	_avatar_img = TextureRect.new()
	_avatar_img.position = Vector2(58, 88)
	_avatar_img.size = Vector2(180, 180)
	_avatar_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_img.stretch_mode = TextureRect.STRETCH_SCALE
	_profile_page.add_child(_avatar_img)
	# 头像正下方「修改头像」按钮（手绘草图样式）
	var chg := Button.new()
	chg.text = "修改头像"
	chg.add_theme_font_size_override("font_size", 22)
	chg.custom_minimum_size = Vector2(200, 52)
	chg.position = Vector2(48, 296)
	chg.size = Vector2(200, 52)
	chg.pressed.connect(_on_change_avatar_pressed)
	_profile_page.add_child(chg)

	# 右：第一行 玩家ID + 修改
	var id_title := Label.new()
	id_title.text = "玩家ID"
	id_title.position = Vector2(330, 92)
	id_title.add_theme_font_size_override("font_size", 20)
	id_title.add_theme_color_override("font_color", Color(0.65, 0.7, 0.7))
	_profile_page.add_child(id_title)
	_id_label = Label.new()
	_id_label.position = Vector2(330, 124)
	_id_label.add_theme_font_size_override("font_size", 30)
	_id_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_profile_page.add_child(_id_label)
	_id_edit_btn = Button.new()
	_id_edit_btn.text = "修改"
	_id_edit_btn.add_theme_font_size_override("font_size", 18)
	_id_edit_btn.custom_minimum_size = Vector2(88, 40)
	_id_edit_btn.position = Vector2(600, 124)
	_id_edit_btn.size = Vector2(88, 40)
	_id_edit_btn.pressed.connect(_on_edit_id_pressed)
	_profile_page.add_child(_id_edit_btn)
	# ID 编辑（就地替换，默认隐藏）
	_id_edit = LineEdit.new()
	_id_edit.position = Vector2(330, 126)
	_id_edit.size = Vector2(250, 40)
	_id_edit.max_length = 12
	_id_edit.add_theme_font_size_override("font_size", 22)
	_id_edit.visible = false
	_id_edit.text_submitted.connect(func(_s): _on_id_ok_pressed())
	_profile_page.add_child(_id_edit)
	_id_ok_btn = Button.new()
	_id_ok_btn.text = "确定"
	_id_ok_btn.add_theme_font_size_override("font_size", 18)
	_id_ok_btn.custom_minimum_size = Vector2(88, 40)
	_id_ok_btn.position = Vector2(600, 126)
	_id_ok_btn.size = Vector2(88, 40)
	_id_ok_btn.visible = false
	_id_ok_btn.pressed.connect(_on_id_ok_pressed)
	_profile_page.add_child(_id_ok_btn)

	# 右：统计只读行（等级/金币/钻石）
	var rows := [
		["等级", "Lv.%d" % GameState.level],
		["金币", "%d" % GameState.gold],
		["钻石", "%d" % GameState.diamonds],
	]
	for i in range(rows.size()):
		var y := 200.0 + i * 52.0
		var k := Label.new()
		k.text = rows[i][0]
		k.position = Vector2(330, y)
		k.add_theme_font_size_override("font_size", 20)
		k.add_theme_color_override("font_color", Color(0.65, 0.7, 0.7))
		_profile_page.add_child(k)
		var v := Label.new()
		v.text = rows[i][1]
		v.position = Vector2(430, y - 4)
		v.add_theme_font_size_override("font_size", 26)
		v.add_theme_color_override("font_color", Color(1, 1, 1))
		_profile_page.add_child(v)
		_stat_labels[rows[i][0]] = v

	# 升级规则「?」按钮（圆形，点击查看升级/钻石规则说明）
	var rules_btn := Button.new()
	rules_btn.text = "?"
	rules_btn.add_theme_font_size_override("font_size", 22)
	rules_btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	rules_btn.flat = true
	rules_btn.position = Vector2(650, 192)
	rules_btn.size = Vector2(44, 44)
	var qsb := StyleBoxFlat.new()
	qsb.bg_color = Color(0, 0, 0, 0)
	qsb.border_color = Color(0.6, 0.62, 0.68, 0.9)
	qsb.set_border_width_all(2)
	qsb.set_corner_radius_all(999)
	rules_btn.add_theme_stylebox_override("normal", qsb)
	rules_btn.add_theme_stylebox_override("hover", qsb)
	rules_btn.add_theme_stylebox_override("pressed", qsb)
	rules_btn.pressed.connect(_show_rules_popup)
	_profile_page.add_child(rules_btn)

# ---------------------------------------------------------------------------
# 页面二：头像选择页（6 格头像，点击即选）
# ---------------------------------------------------------------------------
# _build_avatar_page()：构建头像选择页——标题、3×2 共 6 个头像按钮（点击即选并保存）、
# 跟随选中项移动的黄色选中框、返回按钮。初始隐藏，由「修改头像」切到本页。
func _build_avatar_page():
	_avatar_page = Control.new()
	_avatar_page.position = Vector2.ZERO
	_avatar_page.size = Vector2(PANEL_W, PANEL_H)
	_avatar_page.visible = false
	_avatar_page.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 同理，别挡住 ✕
	_panel.add_child(_avatar_page)

	var t := Label.new()
	t.text = "选择头像"
	t.position = Vector2(PANEL_W / 2.0 - 52, 14)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	_avatar_page.add_child(t)

	# 3 列 × 2 行，格子 110×110
	for i in range(GameState.AVATAR_COUNT):
		var n: int = i + 1
		var col := i % 3
		var row := int(i / 3.0)
		var pos := Vector2(150 + col * 170.0, 70 + row * 150.0)
		# 选中框（黄色圆环，跟随选中项移动）
		# 底圈
		var ring := Panel.new()
		ring.position = pos - Vector2(6, 6)
		ring.size = Vector2(122, 122)
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0, 0, 0, 0)
		rsb.border_color = Color(0.35, 0.38, 0.42, 0.9)
		rsb.set_border_width_all(2)
		rsb.set_corner_radius_all(999)
		ring.add_theme_stylebox_override("panel", rsb)
		_avatar_page.add_child(ring)
		var btn := TextureButton.new()
		btn.texture_normal = load("res://art/avatars/avatar_%d.png" % n)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.position = pos
		btn.size = Vector2(110, 110)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_avatar_picked.bind(n))
		_avatar_page.add_child(btn)
	_sel_ring = Panel.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0, 0, 0, 0)
	ssb.border_color = Color(1.0, 0.85, 0.3, 1.0)
	ssb.set_border_width_all(4)
	ssb.set_corner_radius_all(999)
	_sel_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel_ring.add_theme_stylebox_override("panel", ssb)
	_sel_ring.size = Vector2(128, 128)
	_avatar_page.add_child(_sel_ring)

	var back := Button.new()
	back.text = "返回"
	back.add_theme_font_size_override("font_size", 20)
	back.custom_minimum_size = Vector2(140, 48)
	back.position = Vector2(40, PANEL_H - 70)
	back.size = Vector2(140, 48)
	back.pressed.connect(_on_back_from_avatars)
	_avatar_page.add_child(back)

# ---------------------------------------------------------------------------
# _refresh()：刷新资料页——头像贴图、玩家ID、等级/金币/钻石只读行，并复位 ID 编辑态；
# 把黄色选中框移到当前 avatar_index 对应的头像格位置。
func _refresh():
	_avatar_img.texture = GameState.avatar_texture()
	_id_label.text = GameState.player_id
	_id_label.visible = true
	_id_edit_btn.visible = true
	_id_edit.visible = false
	_id_ok_btn.visible = false
	_stat_labels["等级"].text = "Lv.%d" % GameState.level
	_stat_labels["金币"].text = "%d" % GameState.gold
	_stat_labels["钻石"].text = "%d" % GameState.diamonds
	# 选中框位置：3 列布局
	var idx: int = GameState.avatar_index - 1
	var col := idx % 3
	var row := int(idx / 3.0)
	_sel_ring.position = Vector2(150 + col * 170.0, 70 + row * 150.0) - Vector2(9, 9)

# _on_change_avatar_pressed()：点「修改头像」→ 切到头像选择页并刷新选中框。
func _on_change_avatar_pressed():
	_show_page(true)
	_refresh()

# _on_back_from_avatars()：头像选择页「返回」→ 切回资料页。
func _on_back_from_avatars():
	_show_page(false)

# _on_avatar_picked(n)：在头像选择页点第 n 个头像→保存 avatar_index、刷新、返回资料页、
# 并发出 profile_changed 通知主界面更新左上角头像。
func _on_avatar_picked(n: int):
	GameState.avatar_index = n
	GameState.save_profile()
	_refresh()
	_on_back_from_avatars()
	profile_changed.emit()

# _on_edit_id_pressed()：点「修改」→ 隐藏 ID 文字与修改按钮，显示输入框+确定按钮，预填当前 ID 并全选聚焦。
func _on_edit_id_pressed():
	_id_label.visible = false
	_id_edit_btn.visible = false
	_id_edit.visible = true
	_id_ok_btn.visible = true
	_id_edit.text = GameState.player_id
	_id_edit.grab_focus()
	_id_edit.select_all()

# _on_id_ok_pressed()：点「确定」→ 取输入框文本（去首尾空格），非空则保存 player_id 并发出 profile_changed，再刷新复位。
func _on_id_ok_pressed():
	var s: String = _id_edit.text.strip_edges()
	if s != "":
		GameState.player_id = s
		GameState.save_profile()
		profile_changed.emit()
	_refresh()

# ---------------------------------------------------------------------------
# 升级规则「?」弹窗
# ---------------------------------------------------------------------------
# _show_rules_popup()：点「?」弹出升级规则说明（经验获取/升级条件/奖励/提示框位置/局内升级延迟发放）。
# 遮罩仅认鼠标按下关闭，避免「秒开秒关」。
func _show_rules_popup():
	if _rules_layer != null and is_instance_valid(_rules_layer):
		return
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	_rules_layer = Control.new()
	_rules_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rules_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 【坑】gui_input 对鼠标移动(motion)也会触发，不过滤会"秒开秒关"→ 只认鼠标按下
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_rules_popup())
	_rules_layer.add_child(dim)
	var pw := 580.0
	var ph := 400.0
	var box := Panel.new()
	box.position = Vector2(vw / 2.0 - pw / 2.0, vh / 2.0 - ph / 2.0)
	box.size = Vector2(pw, ph)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.11, 0.12, 0.15, 0.99)
	bs.border_color = Color(0.4, 1.0, 0.6, 0.9)
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", bs)
	_rules_layer.add_child(box)
	var t := Label.new()
	t.text = "升级规则"
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	t.position = Vector2(28, 18)
	box.add_child(t)
	var cb := Button.new()
	cb.text = "✕"
	cb.add_theme_font_size_override("font_size", 22)
	cb.flat = true
	cb.position = Vector2(pw - 52, 14)
	cb.size = Vector2(40, 40)
	cb.pressed.connect(func(): _close_rules_popup())
	box.add_child(cb)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(30, 74)
	vbox.size = Vector2(pw - 60, ph - 104)
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)
	for line in _rules_lines():
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(l)

# _close_rules_popup()：销毁升级规则弹层并清空引用。
func _close_rules_popup():
	if _rules_layer != null and is_instance_valid(_rules_layer):
		_rules_layer.queue_free()
	_rules_layer = null

# _rules_lines()：返回升级规则说明的几条文案。
func _rules_lines() -> Array:
	return [
		"1. 经验获取：击杀丧尸 +10 经验（在战斗中累计）。",
		"2. 升级条件：升到下一级所需经验 = 1000 + 当前等级 × 100（等级越高越难升，最高 100 级）。",
		"3. 升级奖励：每升 1 级，获得等于“新等级数”的钻石（例如升到 5 级得 5 钻石）。",
		"4. 提示框位置：升级提示框只在主界面（大厅）弹出。",
		"5. 局内升级：若在战斗中升级，钻石奖励不会立即发放，会推迟到你返回主界面时，随升级提示框逐个累加到账号（顶部钻石数随弹窗递增）。",
	]
