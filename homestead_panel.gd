extends Control

# ============================================================================
# homestead_panel.gd —— 家园（农田）界面 · 倾斜透视田园场景版
# ----------------------------------------------------------------------------
# 写实田园背景与土壤、作物素材合成，前后两排共 10 块可操作农田。
# 田块上不放任何按钮和文字，保持画面干净：
#   · 点击某块田 → 底部胶囊条才显示它的操作（解锁 / 种植 / 升级 / 收获）
#   · 用短角标提示成熟、选中和下一块可解锁田，避免整圈硬框打断地面。
#   · 十块耕地连续相接，以细线分区；未解锁田显示小锁（按顺序解锁）。
# 数据全部来自 GameState；场景纹理按秒重绘（生长进度 / 剩余时间刷新）。
# ============================================================================

const PW := 880.0                 # 家园面板宽
const PH := 600.0                 # 家园面板高
const SCENE_Y := 64.0             # 场景在面板内的 y 起点（标题下方）
const SW := 880                   # 场景宽（=面板宽）
const SH := 424                   # 场景高
const HORIZON := 200              # 地平线 y（天空/草地分界）
const FARM_BACKGROUND := "res://art/homestead/countryside_realistic.png"
const FARM_SOIL := "res://art/homestead/soil_realistic.png"
const FARM_CROPS := "res://art/homestead/crops_realistic.png"

# 两排田共用地面消失点；压低进深，使田面顺着照片中的草地铺开。
# 围栏脚在 y≈222，后排及作物与围栏之间留出完整草地缓冲区。
const GROUND_VP := Vector2(440.0, 145.0)
const F_TOP := 299.0
const F_BOTTOM := 360.0
const B_TOP := 246.0
const B_BOTTOM := F_TOP
const GROUND_LEFT := 76.0
const F_W := 145.6
const F_GAP := 0.0
const PLOT_PADDING := 24          # 田边羽化与直立作物的透明留边

var _bg: Image = null              # 背景（天空草地装饰，只画一次）
var _field_ground: Image = null   # 连续耕地底图，仅外轮廓与草地融合
var _scene_tex: ImageTexture = null  # 整张场景贴图（每帧 update 复用，不重建）
var _plot_cache: Dictionary = {}   # 田块内容缓存（key=田号:状态:作物:进度档），避免每帧重画
var _quads: Dictionary = {}        # 田号 -> 地面梯形 [bx0,bx1,fx1,fx0,ty,fy]
var _selected := 0                 # 当前选中田号（0=未选中）
var _strip: Control = null         # 底部胶囊条容器（按选中田状态重建）
var _soil_art: Image = null
var _crop_art: Dictionary = {}
var _harvest_all_btn: Button = null   # 右上角「一键收获」按钮（成熟田≥1 时可点）
var _plant_all_btn: Button = null     # 右上角「一键种植」按钮（有空田时可点，点击后弹作物选择）
var _plant_pick_layer: Control = null  # 「一键种植」的作物选择弹层（懒建，点完即销毁）
var _scene_scale := 1.0           # 农场场景撑满屏幕时的 cover 缩放系数
var _scene_off := Vector2.ZERO    # 农场场景在屏幕中的居中偏移（cover 缩放后）

# _ready()：家园入口。铺满视口 → 计算田块四边形坐标 → 画一次性背景 → 构建界面 →
# 订阅 stats_changed → 立即刷新 → 建一个 1 秒定时器，每秒重绘场景（生长进度/剩余时间刷新）。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compute_quads()
	_load_farm_art()
	_bg = _build_bg()
	_field_ground = _build_field_ground()
	_build()
	GameState.stats_changed.connect(_refresh)
	_refresh()
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.timeout.connect(_refresh)
	add_child(tick)
	tick.start()
	# 进入家园：先暂停 Hub 的恐怖氛围音（家园面板叠在 Hub 之上，否则两套会叠在一起），
	# 再循环播放家园温馨音。文件缺失则静默跳过。
	if has_node("/root/AudioManager"):
		AudioManager.stop_ambience()
		AudioManager.start_home()

# ---------------------------------------------------------------------------
# 田块透视梯形（场景坐标）：所有纵向边汇聚到相同消失点。
# 存入 _quads[田号] = [远缘左x, 远缘右x, 近缘右x, 近缘左x, 顶y, 底y]
# ---------------------------------------------------------------------------
func _compute_quads():
	_quads.clear()
	for row in range(2):
		var top := F_TOP if row == 0 else B_TOP
		var bottom := F_BOTTOM if row == 0 else B_BOTTOM
		for col in range(5):
			var left := GROUND_LEFT + col * (F_W + F_GAP)
			var right := left + F_W
			_quads[row * 5 + col + 1] = [_ground_x(left, top), _ground_x(right, top), _ground_x(right, bottom), _ground_x(left, bottom), top, bottom]

func _ground_x(x_at_front: float, y: float) -> float:
	return GROUND_VP.x + (x_at_front - GROUND_VP.x) * (y - GROUND_VP.y) / (F_BOTTOM - GROUND_VP.y)

# 地面深度使用倒数插值，纹理和株距同样受透视压缩。
func _plot_point(p: int, u: float, v: float) -> Vector2:
	var q: Array = _quads[p]
	var y := GROUND_VP.y + 1.0 / lerpf(1.0 / (q[4] - GROUND_VP.y), 1.0 / (q[5] - GROUND_VP.y), v)
	var t: float = (y - q[4]) / (q[5] - q[4])
	return Vector2(lerpf(lerpf(q[0], q[3], t), lerpf(q[1], q[2], t), u), y)

func _plot_rect(p: int) -> Rect2i:
	var q: Array = _quads[p]
	var left := int(floor(minf(q[0], q[3]))) - PLOT_PADDING
	var right := int(ceil(maxf(q[1], q[2]))) + PLOT_PADDING
	return Rect2i(left, int(q[4]) - PLOT_PADDING, right - left + 1, int(q[5] - q[4]) + PLOT_PADDING * 2 + 1)

# _build()：构建家园面板——半透明遮罩、居中相框面板、标题「家园」、「?」规则按钮、关闭按钮、
# 整张场景贴图 + 点击层、底部胶囊条。规则说明同样放进「?」弹层（UI 铁律：规则不直贴界面）。
func _build():
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var scene_scale := maxf(vw / SW, vh / SH)        # cover 缩放：撑满整屏且保持农场比例
	_scene_scale = scene_scale
	_scene_off = Vector2((vw - SW * scene_scale) / 2.0, (vh - SH * scene_scale) / 2.0)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # 家园面板撑满整个游戏窗口
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.08, 0.05, 1.0)       # 不透明深色底（农场贴图会铺满覆盖）
	ps.set_border_width_all(0)
	ps.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "家园"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	title.position = Vector2(24, 14)
	panel.add_child(title)

	# 规则说明「?」按钮（规则不写死在界面上，点开才看）
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 18)
	help_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	help_btn.position = Vector2(112, 20)
	help_btn.size = Vector2(30, 30)
	var hbs := StyleBoxFlat.new()
	hbs.bg_color = Color(0.20, 0.15, 0.08, 0.9)
	hbs.set_border_width_all(1)
	hbs.border_color = Color(0.95, 0.72, 0.30, 0.8)
	hbs.set_corner_radius_all(15)
	help_btn.add_theme_stylebox_override("normal", hbs)
	help_btn.add_theme_stylebox_override("hover", hbs)
	help_btn.add_theme_stylebox_override("pressed", hbs)
	help_btn.pressed.connect(_toggle_help.bind(panel))
	panel.add_child(help_btn)

	# 关闭按钮：深色胶囊底 + 金边 + 大号 ×，压在明亮农场图上也要一眼可见
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	_anchor_top_right(close_btn, 12.0, 12.0, 48.0, 48.0)
	var cbs := StyleBoxFlat.new()
	cbs.bg_color = Color(0.10, 0.08, 0.05, 0.88)      # 深棕半透明底，和面板风格一致
	cbs.set_border_width_all(2)
	cbs.border_color = Color(0.95, 0.72, 0.30, 0.95)  # 金边醒目
	cbs.set_corner_radius_all(24)
	close_btn.add_theme_stylebox_override("normal", cbs)
	var cbh := cbs.duplicate()
	cbh.bg_color = Color(0.30, 0.20, 0.10, 0.95)      # 悬停提亮，反馈明显
	close_btn.add_theme_stylebox_override("hover", cbh)
	close_btn.add_theme_stylebox_override("pressed", cbs)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	# 右上角两个「一键」按钮：一键种植 + 一键收获（都套醒目金边框；状态在 _refresh 里更新）
	_plant_all_btn = _make_prominent_button("一键种植", Vector2.ZERO, Vector2(118, 48))
	_anchor_top_right(_plant_all_btn, 194.0, 12.0, 118.0, 48.0)
	_plant_all_btn.pressed.connect(_on_plant_all)
	panel.add_child(_plant_all_btn)

	_harvest_all_btn = _make_prominent_button("一键收获", Vector2.ZERO, Vector2(110, 48))
	_anchor_top_right(_harvest_all_btn, 70.0, 12.0, 110.0, 48.0)
	_harvest_all_btn.pressed.connect(_on_harvest_all)
	panel.add_child(_harvest_all_btn)

	# 场景画面：按 cover 缩放铺满整屏（保持农场比例，超出部分裁掉）
	var scene := TextureRect.new()
	scene.position = _scene_off
	scene.size = Vector2(SW * _scene_scale, SH * _scene_scale)
	scene.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene.stretch_mode = TextureRect.STRETCH_SCALE
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.texture = _render_scene()
	panel.add_child(scene)

	# 场景点击层（撑满整屏，点击坐标在 _on_scene_input 里反算回农场场景空间）
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_scene_input)
	panel.add_child(catcher)
	# 标题及关闭按钮在场景和点击层上方，保持可见、可操作。
	panel.move_child(title, -1)
	panel.move_child(help_btn, -1)
	panel.move_child(close_btn, -1)
	panel.move_child(_plant_all_btn, -1)
	panel.move_child(_harvest_all_btn, -1)

	# 底部胶囊条（贴屏幕底部，横向铺满）——同样锚底边，避免 expand 视口下被顶出可视区
	_strip = Control.new()
	_strip.anchor_left = 0.0
	_strip.anchor_top = 1.0
	_strip.anchor_right = 1.0
	_strip.anchor_bottom = 1.0
	_strip.offset_left = 24.0
	_strip.offset_right = -24.0
	_strip.offset_top = -92.0
	_strip.offset_bottom = -16.0
	panel.add_child(_strip)

# 规则说明弹层（? 按钮开关）
var _help_popup: Control = null

# _toggle_help(panel)：点击「?」开关规则说明弹层（已开则关，未开则建一个半透明面板显示规则文案）。
func _toggle_help(panel: Control):
	if _help_popup != null and is_instance_valid(_help_popup):
		_help_popup.queue_free()
		_help_popup = null
		return
	_help_popup = PanelContainer.new()
	_help_popup.position = Vector2((get_viewport().get_visible_rect().size.x - 780.0) / 2.0, 110.0)
	_help_popup.size = Vector2(780.0, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.97)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.72, 0.30, 0.9)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	_help_popup.add_theme_stylebox_override("panel", sb)
	panel.add_child(_help_popup)
	var lb := Label.new()
	lb.text = "· 点击田块进行 解锁 / 种植 / 升级 / 收获\n· 腐肉靠击杀丧尸掉落\n· 农田按顺序解锁，解锁耗 金币 + 腐肉\n· 作物成熟后收获「作物」进背包，可在背包里卖出换金币\n· 升级只耗腐肉，每级 +20% 产量"
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_popup.add_child(lb)

# _on_overlay_input(event)：点遮罩（左键按下）关闭整个家园面板。
func _on_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

# _close()：销毁家园面板自身（queue_free）。关家园前停温馨音、恢复 Hub 恐怖氛围音。
func _close():
	if has_node("/root/AudioManager"):
		AudioManager.stop_home()
		AudioManager.start_ambience()
	queue_free()

# _on_scene_input(event)：点场景（左键按下）→ 反查点到哪块田(_plot_at)并选中，刷新界面。
func _on_scene_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击坐标在屏幕空间，反算回农场场景空间（cover 缩放 + 居中偏移）再 hit-test
		var sp := Vector2((event.position.x - _scene_off.x) / _scene_scale, (event.position.y - _scene_off.y) / _scene_scale)
		_selected = _plot_at(sp)
		_refresh()

# _plot_at(pos)：场景坐标 hit-test，返回命中的田号(1~10)，未命中返回 0。
# 绘制与点击共用梯形，逐行插值左右边界。
func _plot_at(pos: Vector2) -> int:
	for p in range(1, 11):
		var q: Array = _quads[p]
		if pos.y < q[4] or pos.y > q[5]:
			continue
		var t: float = (pos.y - q[4]) / (q[5] - q[4])
		var xl: float = lerpf(q[0], q[3], t)
		var xr: float = lerpf(q[1], q[2], t)
		if pos.x >= xl and pos.x <= xr:
			return p
	return 0

# ---------------------------------------------------------------------------
# 刷新：重绘场景 + 重建底部条（点田/解锁/种植/收获/升级后都会调用）
# ---------------------------------------------------------------------------
func _refresh():
	if _strip == null:
		return
	_render_scene()
	_rebuild_strip()
	# 一键按钮状态：有成熟田→一键收获可点；有空田→一键种植可点
	if _harvest_all_btn != null or _plant_all_btn != null:
		var any_ready := false
		var any_empty := false
		for p in range(1, 11):
			var st := GameState.plot_state(p)
			if st == 3:
				any_ready = true
			elif st == 1:
				any_empty = true
		if _harvest_all_btn != null:
			_harvest_all_btn.disabled = not any_ready
		if _plant_all_btn != null:
			_plant_all_btn.disabled = not any_empty

# ---------------------------------------------------------------------------
# 场景绘制：背景 + 后排田 + 前排田 + 描边
# ---------------------------------------------------------------------------
# _render_scene()：合成整张场景贴图。先 blit 背景，再按 后排→前排 顺序叠加田块（前排压住后排），
# 最后给选中田(亮金边)/成熟田(金边)/下一块可解锁田(暗金边)描边。复用 _scene_tex 对象避免频繁重建。
func _render_scene() -> Texture2D:
	var frame := Image.create(SW, SH, false, Image.FORMAT_RGBA8)
	frame.blit_rect(_bg, Rect2i(0, 0, SW, SH), Vector2i.ZERO)
	frame.blend_rect(_field_ground, Rect2i(0, 0, SW, SH), Vector2i.ZERO)
	_draw_field_grid(frame)
	for p in range(6, 11):    # 后排先画（被前排遮挡）
		_blend_plot(frame, p)
	for p in range(1, 6):
		_blend_plot(frame, p)
	for p in range(1, 11):
		var st := GameState.plot_state(p)
		if p == _selected:
			_draw_quad_outline(frame, p, Color(1.0, 0.88, 0.48, 0.8), 2)
		elif st == 3:
			_draw_quad_outline(frame, p, Color(0.96, 0.83, 0.48, 0.55))
		elif st == 0 and p == GameState.homestead_unlocked + 1:
			_draw_quad_outline(frame, p, Color(0.90, 0.79, 0.52, 0.55))
	if _scene_tex == null:
		_scene_tex = ImageTexture.create_from_image(frame)
	else:
		_scene_tex.update(frame)
	return _scene_tex

# 连续田地共用纹理与外边缘，内部不留草缝；分隔线只画一次。
func _draw_field_grid(img: Image):
	var line := Color(0.78, 0.64, 0.39, 0.65)
	for col in range(6):
		var x := GROUND_LEFT + col * F_W
		_draw_ground_mark(img, Vector2(_ground_x(x, B_TOP), B_TOP), Vector2(x, F_BOTTOM), line, 1)
	for y in [B_TOP, F_TOP, F_BOTTOM]:
		_draw_ground_mark(img, Vector2(_ground_x(GROUND_LEFT, y), y), Vector2(_ground_x(GROUND_LEFT + 5.0 * F_W, y), y), line, 1)

# 透明内容图含作物留边，按同一梯形包围盒放回场景。
func _blend_plot(frame: Image, p: int):
	var img := _plot_image(p)
	frame.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), _plot_rect(p).position)

# 地面内侧的短角标，只提示可交互状态，不再描成一块发光的硬板。
func _draw_quad_outline(img: Image, p: int, col: Color, th := 1):
	for u in [0.05, 0.95]:
		for v in [0.10, 0.90]:
			var corner := _plot_point(p, u, v)
			_draw_ground_mark(img, corner, _plot_point(p, u + (0.13 if u < 0.5 else -0.13), v), col, th)
			_draw_ground_mark(img, corner, _plot_point(p, u, v + (0.16 if v < 0.5 else -0.16)), col, th)

func _draw_ground_mark(img: Image, a: Vector2, b: Vector2, col: Color, thickness: int):
	var steps := maxi(1, int(ceil(a.distance_to(b))))
	for i in range(steps + 1):
		var pt := a.lerp(b, float(i) / steps)
		for dy in range(thickness):
			_blend_px(img, int(pt.x), int(pt.y) + dy, Color(col.r, col.g, col.b), col.a)

# _setp(img, x, y, col)：安全 set_pixel（越界不写），像素绘制基础工具。
func _setp(img: Image, x: int, y: int, col: Color):
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

# _blend_px(img, x, y, col, a)：安全像素混合（当前色 lerp 到 col，权重 a），用于阴影/高光渐变。
func _blend_px(img: Image, x: int, y: int, col: Color, a: float):
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, a))

# ---------------------------------------------------------------------------
# 背景与作物素材只加载一次；田块绘制与点击共用投影坐标。
# ---------------------------------------------------------------------------
func _load_art_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

func _load_farm_art():
	_soil_art = _load_art_image(FARM_SOIL)
	if _soil_art != null:
		_soil_art.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var atlas := _load_art_image(FARM_CROPS)
	if atlas == null:
		return
	# 三株植物按实际透明间隙分区，西瓜藤占更宽的右侧区域。
	var cuts := [0.0, 0.31, 0.612, 1.0]
	for i in range(GameState.CROP_ORDER.size()):
		var x0 := int(round(atlas.get_width() * cuts[i]))
		var x1 := int(round(atlas.get_width() * cuts[i + 1]))
		var cell := atlas.get_region(Rect2i(x0, 0, x1 - x0, atlas.get_height()))
		var used := cell.get_used_rect()
		if used.has_area():
			_crop_art[GameState.CROP_ORDER[i]] = cell.get_region(used)

# _build_bg()：优先使用写实背景；素材缺失时保留原有背景作为兜底。返回 Image。
func _build_bg() -> Image:
	var background := _load_art_image(FARM_BACKGROUND)
	if background != null:
		background.resize(SW, SH, Image.INTERPOLATE_LANCZOS)
		return background
	var img := Image.create(SW, SH, false, Image.FORMAT_RGBA8)
	var sky_top := Color(0.40, 0.68, 0.94)
	var sky_bot := Color(0.80, 0.90, 0.98)
	var gr_top := Color(0.46, 0.69, 0.33)
	var gr_bot := Color(0.27, 0.49, 0.22)
	for y in range(SH):
		var c: Color
		if y < HORIZON:
			c = sky_top.lerp(sky_bot, float(y) / HORIZON)
		else:
			c = gr_top.lerp(gr_bot, float(y - HORIZON) / (SH - HORIZON))
		for x in range(SW):
			img.set_pixel(x, y, c)
	# 太阳 + 光晕
	_ellipse(img, 105, 48, 22, 22, Color(1.0, 0.96, 0.65))
	for y in range(10, 90):
		for x in range(65, 150):
			var d := Vector2(x, y).distance_to(Vector2(105, 48))
			if d > 22 and d < 42:
				_blend_px(img, x, y, Color(1.0, 0.98, 0.80), 0.30 * (1.0 - (d - 22) / 20.0))
	# 云（三团）
	_ellipse(img, 300, 44, 42, 13, Color(0.98, 0.99, 1.0))
	_ellipse(img, 330, 40, 26, 10, Color(0.98, 0.99, 1.0))
	_ellipse(img, 272, 47, 22, 9, Color(0.96, 0.98, 1.0))
	_ellipse(img, 620, 72, 36, 11, Color(0.97, 0.98, 1.0))
	_ellipse(img, 646, 68, 22, 9, Color(0.97, 0.98, 1.0))
	_ellipse(img, 470, 24, 24, 8, Color(0.97, 0.98, 1.0))
	# 远山（两叠）
	for x in range(SW):
		var hy := HORIZON - 18 - 14 * sin(x * 0.011 + 1.7) - 8 * sin(x * 0.023 + 0.4)
		for y in range(int(hy), HORIZON):
			img.set_pixel(x, y, Color(0.58, 0.74, 0.47))
	for x in range(SW):
		var hy2 := HORIZON - 6 - 10 * sin(x * 0.017 + 4.2) - 6 * sin(x * 0.031 + 2.1)
		for y in range(int(hy2), HORIZON):
			img.set_pixel(x, y, Color(0.40, 0.62, 0.33))
	# 栅栏（横杆 + 立柱，在地平线下方）
	for y in range(196, 199):
		for x in range(26, 855):
			img.set_pixel(x, y, Color(0.60, 0.45, 0.29))
	for y in range(204, 207):
		for x in range(26, 855):
			img.set_pixel(x, y, Color(0.56, 0.42, 0.27))
	for i in range(15):
		var px := 32 + i * 58
		for y in range(192, 213):
			for dx in range(4):
				img.set_pixel(px + dx, y, Color(0.50, 0.37, 0.23))
	# 两棵树
	_draw_tree(img, 46, 246, 1.0)
	_draw_tree(img, 836, 250, 1.15)
	# 草地噪点 + 小花
	for i in range(900):
		var rx := int(fposmod(sin(i * 12.9898) * 43758.5453, 1.0) * SW)
		var ry := HORIZON + int(fposmod(sin(i * 78.233) * 12543.2, 1.0) * (SH - HORIZON))
		if i % 9 == 0:
			_setp(img, rx, ry, Color(0.95, 0.90, 0.45))
			_setp(img, rx + 1, ry, Color(0.95, 0.95, 0.95))
		elif i % 2 == 0:
			_blend_px(img, rx, ry, Color(0.20, 0.40, 0.18), 0.5)
		else:
			_blend_px(img, rx, ry, Color(0.55, 0.78, 0.40), 0.4)
	return img

# _draw_tree(img, tx, ty, s)：在背景画一棵简单的树（树干 + 三团树冠），s 为缩放系数。
func _draw_tree(img: Image, tx: int, ty: int, s: float):
	var trunk := Color(0.42, 0.30, 0.18)
	for y in range(ty - int(52 * s), ty):
		for dx in range(-int(4 * s), int(4 * s) + 1):
			_setp(img, tx + dx, y, trunk)
	_ellipse(img, tx, ty - int(66 * s), int(28 * s), int(26 * s), Color(0.24, 0.48, 0.22))
	_ellipse(img, tx - int(14 * s), ty - int(78 * s), int(15 * s), int(13 * s), Color(0.32, 0.58, 0.27))
	_ellipse(img, tx + int(15 * s), ty - int(56 * s), int(13 * s), int(12 * s), Color(0.18, 0.40, 0.18))

# ---------------------------------------------------------------------------
# 连续耕地底图（整片土地共用纹理，仅外轮廓羽化）
# ---------------------------------------------------------------------------
func _build_field_ground() -> Image:
	var far_left: Array = _quads[6]
	var far_right: Array = _quads[10]
	var near_left: Array = _quads[1]
	var near_right: Array = _quads[5]
	var q: Array = [far_left[0], far_right[1], near_right[2], near_left[3], B_TOP, F_BOTTOM]
	var h := F_BOTTOM - B_TOP
	var img := Image.create(SW, SH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var left_normal := sqrt(1.0 + pow((q[3] - q[0]) / h, 2))
	var right_normal := sqrt(1.0 + pow((q[2] - q[1]) / h, 2))
	var inv_top: float = 1.0 / (q[4] - GROUND_VP.y)
	var inv_bottom: float = 1.0 / (q[5] - GROUND_VP.y)
	for gy in range(int(q[4]) - 4, int(q[5]) + 5):
		var t: float = (gy + 0.5 - q[4]) / h
		var xl := lerpf(q[0], q[3], t)
		var xr := lerpf(q[1], q[2], t)
		var v := clampf((inv_top - 1.0 / (gy + 0.5 - GROUND_VP.y)) / (inv_top - inv_bottom), 0.0, 1.0)
		for gx in range(int(xl) - 5, int(xr) + 6):
			var edge := minf(minf((gx + 0.5 - xl) / left_normal, (xr - gx - 0.5) / right_normal), minf(gy + 0.5 - q[4], q[5] - gy - 0.5))
			var roughness := sin(gx * 0.73 + gy * 1.61) * 1.1 + sin(gx * 1.79 - gy * 0.57) * 0.8 + sin(gx * 0.18 + gy * 0.37) * 1.2
			var coverage := smoothstep(-1.2, 4.0, edge + roughness)
			if coverage <= 0.0:
				continue
			var color := Color(0.34, 0.25, 0.15)
			if _soil_art != null:
				var ground_x := GROUND_VP.x + (gx + 0.5 - GROUND_VP.x) * (F_BOTTOM - GROUND_VP.y) / (gy + 0.5 - GROUND_VP.y)
				var tx := posmod(int(ground_x * 0.9), _soil_art.get_width())
				var ty := posmod(int(v * 370.0), _soil_art.get_height())
				color = _soil_art.get_pixel(tx, ty).lerp(Color(0.36, 0.27, 0.16), 0.20)
			var grass := _bg.get_pixel(gx, gy)
			var light := clampf(0.86 + grass.get_luminance() * 0.45, 0.90, 1.08)
			color = Color(color.r * light, color.g * light, color.b * light, coverage)
			# 近缘的小范围接触暗部保留草叶，不形成悬空田板的厚边。
			var contact := (1.0 - smoothstep(0.0, 3.0, q[5] - gy)) * 0.12
			color = color.darkened(contact)
			img.set_pixel(gx, gy, color)
	return img

# 单块田只叠加作物或小锁，底下始终是相连的耕地。
# 按田号、状态、作物和生长阶段缓存。
func _plot_image(p: int) -> Image:
	var st := GameState.plot_state(p)
	var crop_id := ""
	var ratio := 0.0
	if st >= 2:
		crop_id = String(GameState.farm_plots[p]["crop"])
		ratio = GameState.plot_grow_ratio(p) if st == 2 else 1.0
	var key := "%d:%d:%s:%d" % [p, st, crop_id, int(ratio * 10.0)]
	if _plot_cache.has(key):
		return _plot_cache[key]
	var bounds := _plot_rect(p)
	var img := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if st == 0:
		var center := Vector2i(_plot_point(p, 0.5, 0.55)) - bounds.position
		var lock_size := 24 if p <= 5 else 20
		_draw_lock(img, center.x + 1, center.y + 1, lock_size, Color(0.11, 0.09, 0.05, 0.8))
		_draw_lock(img, center.x, center.y, lock_size, Color(0.98, 0.94, 0.79))

	# 作物根部与纹理共用地面投影；直立叶片可以自然越过田的远缘。
	if st >= 2 and _crop_art.has(crop_id):
		var source: Image = _crop_art[crop_id]
		var growth := lerpf(0.32, 0.88, ratio) if st == 2 else 1.0
		for v in [0.24, 0.54, 0.84]:
			var base := _plot_point(p, 0.5, v)
			var scale := (base.y - GROUND_VP.y) / (F_BOTTOM - GROUND_VP.y)
			var plant_w := maxi(5, int(30.0 * scale * growth))
			var plant_h := maxi(5, int(plant_w * float(source.get_height()) / source.get_width()))
			var plant := source.duplicate()
			plant.resize(plant_w, plant_h, Image.INTERPOLATE_LANCZOS)
			for u in [0.16, 0.38, 0.60, 0.82]:
				var pos := Vector2i(_plot_point(p, u, v)) - bounds.position
				for sy in range(-2, 3):
					for sx in range(-plant_w / 3, plant_w / 3 + 1):
						var fade := maxf(0.0, 1.0 - pow(float(sx) / maxf(1.0, plant_w / 3.0), 2) - pow(sy / 2.0, 2))
						_blend_px(img, pos.x + sx + 2, pos.y + sy, Color(0.09, 0.08, 0.04), fade * 0.25)
				img.blend_rect(plant, Rect2i(0, 0, plant_w, plant_h), Vector2i(pos.x - plant_w / 2, pos.y - plant_h + 2))

	_plot_cache[key] = img
	return img

# ---------------------------------------------------------------------------
# 底部胶囊条：按选中田的状态显示操作（点田后才出现对应操作，保持画面干净）
# ---------------------------------------------------------------------------
# _rebuild_strip()：清空旧条，按当前选中田(_selected)状态重建底部胶囊条：
# 未选中→提示；锁定且非下一块→「未解锁」提示；下一块可解锁→需求+解锁按钮；
# 空地→各作物种植胶囊+升级胶囊；生长中→信息+升级；成熟→信息+收获+升级。
func _rebuild_strip():
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.free()
	var W := _strip.size.x
	if _selected == 0:
		var cap := _make_capsule(W)
		cap.position = Vector2(0, 6)
		_strip.add_child(cap)
		var lb := _cap_label(cap, "点击场景中的一块田，进行 解锁 / 种植 / 升级 / 收获", Color(0.85, 0.75, 0.58), 15)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return

	var p := _selected
	var st := GameState.plot_state(p)
	var is_next := (p == GameState.homestead_unlocked + 1)

	if st == 0 and not is_next:
		# 更靠后的锁定田
		var cap := _make_capsule(W)
		cap.position = Vector2(0, 6)
		_strip.add_child(cap)
		var lb := _cap_label(cap, "农田 %d · 未解锁（需要按顺序先解锁前一块）" % p, Color(0.75, 0.70, 0.62), 16)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif st == 0 and is_next:
		# 下一块可解锁：需求 + 解锁按钮
		var cap := _make_capsule(W)
		cap.position = Vector2(0, 6)
		_strip.add_child(cap)
		var hb := _cap_hbox(cap)
		var c := GameState.plot_unlock_cost(p)
		var info := _hb_label(hb, "解锁 农田 %d 需要  %d 金币 + %d 腐肉" % [p, int(c["gold"]), int(c["meat"])], 18)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var confirm := Button.new()
		confirm.text = "解锁"
		confirm.add_theme_font_size_override("font_size", 18)
		confirm.disabled = not GameState.can_unlock_next()
		_apply_pill_btn_style(confirm, GameState.can_unlock_next())
		confirm.pressed.connect(_on_confirm_unlock)
		hb.add_child(confirm)
	elif st == 1:
		# 空地：3 个作物胶囊 + 升级胶囊
		var up_w := 232.0
		var gap := 10.0
		var cw := (W - up_w - 3 * gap) / 3.0
		for i in range(GameState.CROP_ORDER.size()):
			var cid: String = GameState.CROP_ORDER[i]
			var c: Dictionary = GameState.CROPS[cid]
			var cap := _make_capsule(cw)
			cap.position = Vector2(i * (cw + gap), 6)
			_strip.add_child(cap)
			var hb := _cap_hbox(cap, 8)
			var info := _hb_label(hb, "%s\n%s · 产%d个" % [String(c["name"]), _fmt_time(float(c["grow_sec"]) * 1000.0), GameState.crop_yield(p, cid)], 13)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := Button.new()
			b.text = "种"
			b.add_theme_font_size_override("font_size", 16)
			b.custom_minimum_size = Vector2(44, 36)
			_apply_pill_btn_style(b, true)
			b.pressed.connect(_on_pick_crop.bind(p, cid))
			hb.add_child(b)
		_add_upgrade_capsule(p, 3 * (cw + gap), up_w)
	elif st == 2:
		# 生长中：信息 + 升级
		var up_w := 232.0
		var cap := _make_capsule(W - up_w - 10.0)
		cap.position = Vector2(0, 6)
		_strip.add_child(cap)
		var crop_id := String(GameState.farm_plots[p]["crop"])
		var lb := _cap_label(cap, "农田 %d · %s 生长中 · 剩余 %s" % [p, String(GameState.CROPS[crop_id]["name"]), _fmt_time(GameState.plot_remaining_ms(p))], Color(0.85, 0.95, 0.80), 16)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_add_upgrade_capsule(p, W - up_w, up_w)
	else:
		# 成熟：信息 + 收获 + 升级
		var up_w := 232.0
		var hv_w := 190.0
		var cap := _make_capsule(W - up_w - hv_w - 20.0)
		cap.position = Vector2(0, 6)
		_strip.add_child(cap)
		var crop_id := String(GameState.farm_plots[p]["crop"])
		var y_gain := GameState.crop_yield(p, crop_id)
		var lb := _cap_label(cap, "农田 %d · %s 已成熟" % [p, String(GameState.CROPS[crop_id]["name"])], Color(1.0, 0.92, 0.6), 16)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hcap := _make_capsule(hv_w)
		hcap.position = Vector2(W - up_w - hv_w - 10.0, 6)
		_strip.add_child(hcap)
		var hb := _cap_hbox(hcap)
		var hb2 := Button.new()
		hb2.text = "收获 +%d 个" % y_gain
		hb2.add_theme_font_size_override("font_size", 16)
		hb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_pill_btn_style(hb2, true)
		hb2.pressed.connect(_on_harvest.bind(p))
		hb.add_child(hb2)
		_add_upgrade_capsule(p, W - up_w, up_w)

# _add_upgrade_capsule(p, x, w)：在胶囊条 x 处加一个「升级」胶囊（显示 Lv→下一级与腐肉花费，
# 满级显示「满级」并禁用）。按钮点击调用 _on_confirm_upgrade。
func _add_upgrade_capsule(p: int, x: float, w: float):
	var cap := _make_capsule(w)
	cap.position = Vector2(x, 6)
	_strip.add_child(cap)
	var hb := _cap_hbox(cap, 8)
	var lv := GameState.homestead_level(p)
	var maxed := lv >= GameState.HOMESTEAD_MAX_LEVEL
	var info := _hb_label(hb, "已满级 Lv.%d" % lv if maxed else "Lv.%d→%d · %d腐肉" % [lv, lv + 1, GameState.plot_upgrade_cost(p)], 13)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = "满级" if maxed else "升级"
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(56, 36)
	b.disabled = maxed or not GameState.can_upgrade_plot(p)
	_apply_pill_btn_style(b, not b.disabled)
	b.pressed.connect(_on_confirm_upgrade.bind(p))
	hb.add_child(b)

# _on_confirm_unlock()：点「解锁」→ 调用 GameState.unlock_next_plot 解锁下一块田并刷新。
func _on_confirm_unlock():
	if GameState.unlock_next_plot():
		_refresh()

# _on_pick_crop(p, crop_id)：点某作物「种」→ 在田 p 种下 crop_id，刷新。
func _on_pick_crop(p: int, crop_id: String):
	if GameState.plant_crop(p, crop_id):
		_refresh()

# _on_confirm_upgrade(p)：点「升级」→ 调用 GameState.upgrade_plot 升级田 p 并刷新。
func _on_confirm_upgrade(p: int):
	if GameState.upgrade_plot(p):
		_refresh()

# _on_harvest(p)：点「收获」→ 作物进背包，飘字提示「+N 个作物名」。背包满则提示背包已满（农田不收）。
func _on_harvest(p: int):
	var crop_id := String(GameState.farm_plots.get(p, {}).get("crop", ""))
	var n := GameState.harvest(p)
	if n > 0:
		var nm := String(GameState.CROPS.get(crop_id, {}).get("name", "作物"))
		_toast("+%d 个%s（可在背包卖出换金币）" % [n, nm])
	elif crop_id != "":
		_toast("背包已满，放不下%s，请先清理背包" % String(GameState.CROPS.get(crop_id, {}).get("name", "作物")))
	_refresh()

# _anchor_top_right(c, right_margin, top, w, h)：把控件 c 锚定到「面板右上角」并按边距摆位。
#   right_margin = 距右边界的距离，w/h = 控件尺寸。
#   为什么不用 position.x = vw - 常数：项目 stretch aspect="expand"，窗口比例变化时可见视口
#   会比基准 1152 更宽，用 vw 算出的绝对坐标会把按钮顶出可视区（表现为「×」消失或按钮被裁）。
#   锚定右边界后无论视口多宽都稳定贴边。
func _anchor_top_right(c: Control, right_margin: float, top: float, w: float, h: float):
	c.anchor_left = 1.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 0.0
	c.offset_left = -right_margin - w
	c.offset_right = -right_margin
	c.offset_top = top
	c.offset_bottom = top + h

# _make_prominent_button(text, pos, sz)：构造右上角「一键」类操作按钮——深色底 + 3px 亮金边框 + 金色描边文字，
# 在明亮农场图上也一眼可见。悬停/按下用更亮的底色反馈。
func _make_prominent_button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(1.0, 0.89, 0.58))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 3)
	b.position = pos
	b.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.17, 0.05, 0.95)
	sb.set_border_width_all(3)                      # 3px 粗金边 = 醒目指视
	sb.border_color = Color(1.0, 0.80, 0.32, 1.0)
	sb.set_corner_radius_all(12)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.40, 0.28, 0.10, 0.98)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

# _on_harvest_all()：点「一键收获」→ 把所有成熟田的作物收进背包，飘字提示总个数。
func _on_harvest_all():
	var got := GameState.harvest_all()
	if got > 0:
		_toast("一键收获 +%d 个作物（可在背包卖出换金币）" % got)
	_refresh()

# _on_plant_all()：点「一键种植」→ 弹出作物选择层（再点一次或点空白关闭）。种植本身在选中作物时执行。
func _on_plant_all():
	if _plant_pick_layer != null and is_instance_valid(_plant_pick_layer):
		_hide_plant_pick()
		return
	_build_plant_pick()

# _build_plant_pick()：懒建作物选择弹层——屏幕上方居中的面板，列出 GameState.CROP_ORDER 里所有作物
# （名称 · 成熟时长 · 产量个数），点一个即种到全部空田。弹层后添加 = 位于最上层，不会被点击层挡住。
func _build_plant_pick():
	_plant_pick_layer = Control.new()
	_plant_pick_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plant_pick_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plant_pick_layer)

	var vw := get_viewport().get_visible_rect().size.x
	var row_h := 52.0
	var pw := 460.0
	var ph: float = 76.0 + row_h * float(GameState.CROP_ORDER.size())
	var pick := Panel.new()
	pick.position = Vector2(vw / 2.0 - pw / 2.0, 96.0)
	pick.size = Vector2(pw, ph)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	sb.set_border_width_all(3)
	sb.border_color = Color(1.0, 0.80, 0.32, 1.0)
	sb.set_corner_radius_all(12)
	pick.add_theme_stylebox_override("panel", sb)
	_plant_pick_layer.add_child(pick)

	var t := Label.new()
	t.text = "选择要种植的作物"
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	t.position = Vector2(20, 16)
	t.size = Vector2(pw - 40, 28)
	pick.add_child(t)

	for i in range(GameState.CROP_ORDER.size()):
		var cid: String = GameState.CROP_ORDER[i]
		var c: Dictionary = GameState.CROPS[cid]
		var b := Button.new()
		b.text = "%s · %s · 产%d 个" % [String(c["name"]), _fmt_time(float(c["grow_sec"]) * 1000.0), int(c["yield_count"])]
		b.add_theme_font_size_override("font_size", 17)
		b.position = Vector2(20, 56 + float(i) * row_h)
		b.size = Vector2(pw - 40.0, 44.0)
		_apply_pill_btn_style(b, true)
		b.pressed.connect(_on_plant_all_pick.bind(cid))
		pick.add_child(b)

# _on_plant_all_pick(cid)：选中作物 → 种到所有「空地」（plot_state==1）田里，飘字报种了几块，然后关弹层。
func _on_plant_all_pick(cid: String):
	var n := 0
	for p in range(1, 11):
		if GameState.plot_state(p) == 1 and GameState.plant_crop(p, cid):
			n += 1
	_hide_plant_pick()
	if n > 0:
		_toast("一键种植 %d 块田（%s）" % [n, String(GameState.CROPS[cid]["name"])])
	_refresh()

# _hide_plant_pick()：销毁作物选择弹层。
func _hide_plant_pick():
	if _plant_pick_layer != null and is_instance_valid(_plant_pick_layer):
		_plant_pick_layer.queue_free()
	_plant_pick_layer = null

# _toast(text)：居中偏下飘字（1.2 秒后自动释放），用于收获/解锁等轻量反馈。
func _toast(text: String):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 200, vh * 0.5)
	lbl.size = Vector2(400, 44)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

# ---------------------------------------------------------------------------
# 胶囊/标签小工具
# ---------------------------------------------------------------------------
# _make_capsule(w)：构造一个圆角胶囊 PanelContainer（金边、半透明暖色底），宽 w、高 64。返回待用。
func _make_capsule(w: float) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.size = Vector2(w, 64)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.11, 0.06, 0.95)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.72, 0.30, 0.95)
	sb.set_corner_radius_all(32)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	cap.add_theme_stylebox_override("panel", sb)
	return cap

# _cap_hbox(cap, sep)：在胶囊内加一个 HBoxContainer（横向排布文字与按钮），sep 为子项间距。
func _cap_hbox(cap: PanelContainer, sep := 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", sep)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(hb)
	return hb

# _hb_label(hb, text, fs)：在 HBox 里加一个文字 Label（金色、垂直居中），返回引用。
func _hb_label(hb: HBoxContainer, text: String, fs: int) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lb)
	return lb

# _cap_label(cap, text, col, fs)：在胶囊内加一个居中对齐的文字 Label（用于单行提示）。
func _cap_label(cap: PanelContainer, text: String, col: Color, fs: int) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(lb)
	return lb

# _apply_pill_btn_style(btn, enabled)：给胶囊内按钮套圆角描边样式；enabled=true 高亮金边，
# false 灰边灰字（相当于禁用态外观，按钮 enabled 由调用方另行设置）。
func _apply_pill_btn_style(btn: Button, enabled: bool):
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	if enabled:
		sb.bg_color = Color(0.30, 0.20, 0.10, 0.95)
		sb.border_color = Color(1.0, 0.75, 0.20, 0.95)
	else:
		sb.bg_color = Color(0.10, 0.10, 0.12, 0.9)
		sb.border_color = Color(0.4, 0.4, 0.4, 0.6)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6) if enabled else Color(0.55, 0.55, 0.58))

# _fmt_time(ms)：毫秒转 HH:MM:SS 或 MM:SS 字符串，用于剩余时间显示。
func _fmt_time(ms: float) -> String:
	var s := int(ms / 1000.0)
	var h := s / 3600
	s %= 3600
	var m := s / 60
	s %= 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]

# ---------------------------------------------------------------------------
# 像素小工具
# ---------------------------------------------------------------------------
# _dot(img, cx, cy, r, col)：以 (cx,cy) 为圆心 r 为半径画实心圆点。
func _dot(img: Image, cx: int, cy: int, r: int, col: Color):
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				_setp(img, x, y, col)

# _ellipse(img, cx, cy, rx, ry, col)：在 (cx,cy) 处画一个 rx×ry 的实心椭圆。
func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, col: Color):
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := float(x - cx) / float(maxi(rx, 1))
			var dy := float(y - cy) / float(maxi(ry, 1))
			if dx * dx + dy * dy <= 1.0:
				_setp(img, x, y, col)

# _melon(img, cx, cy, col, s)：画一个西瓜（椭圆+深色条纹），用于成熟西瓜作物。
func _melon(img: Image, cx: int, cy: int, col: Color, s: float):
	var rx := int(8 * s)
	var ry := int(5 * s)
	var dk := Color(col.r * 0.45, col.g * 0.45, col.b * 0.45)
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := float(x - cx) / float(maxi(rx, 1))
			var dy := float(y - cy) / float(maxi(ry, 1))
			if dx * dx + dy * dy <= 1.0:
				_setp(img, x, y, dk if (x * 3 + y) % 7 < 3 else col)

# 锁：锁梁（圆环）+ 锁体 + 钥匙孔（绘制在锁定田中央，提示未解锁）
func _draw_lock(img: Image, cx: int, cy: int, size: int, col: Color):
	var body_w := size * 0.62
	var body_h := size * 0.46
	var bx := cx - body_w / 2.0
	var by := cy - size * 0.02
	for y in range(cy - size, cy + size):
		for x in range(cx - size, cx + size):
			var py := float(y)
			if py < by:
				var d := Vector2(x + 0.5, py + 0.5).distance_to(Vector2(cx, by))
				if py >= by - size * 0.42 and d <= size * 0.26 and d >= size * 0.26 - size * 0.07:
					_setp(img, x, y, col)
			if float(x) >= bx and float(x) <= bx + body_w and py >= by and py <= by + body_h:
				_setp(img, x, y, col)
	# 钥匙孔
	var kx := int(cx)
	var ky := int(by + body_h * 0.45)
	_dot(img, kx, ky, maxi(1, int(size * 0.06)), Color(0.10, 0.10, 0.14))
	for dy in range(int(size * 0.10)):
		_setp(img, kx, ky + dy, Color(0.10, 0.10, 0.14))
