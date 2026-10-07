extends Control

# ============================================================================
# hub.gd —— 游戏主界面（进入游戏后第一个看到的界面）
# ============================================================================
# 布局：
#   左上角：玩家头像 + 等级(Lv.1) + 经验
#   正上方：金币(金色) + 钻石 及数量（初始均 0）
#   最下方一行：武器 / 人物 / 图鉴 / 宝箱 / 开始游戏（5个灰黑色选项框）
# 数据全部来自 GameState（等级/经验/金币/钻石），监听 stats_changed 实时刷新。
# ============================================================================

# 顶栏货币 HUD 的标签引用（由 GameState.build_currency_hud 返回，键为 "gold"/"diamond"）
var _cur_labels: Dictionary = {}
var _level_label: Label                 # 左上角「Lv.N」等级文字
var _exp_label: Label                   # 左上角「EXP x/y」经验文字
var _exp_bar: ProgressBar               # 左上角经验进度条
var _name_label: Label                  # 头像下方玩家名字（取自 GameState.player_id）
var _levelup_queue: Array = []          # 待显示的升级提示等级队列（局内升级延迟到此弹出）
var _levelup_popup_open: bool = false   # 是否已有升级弹窗开着（保证一次只弹一个）
const LampFlicker := preload("res://lamp_flicker.gd")
var _lamp_material: ShaderMaterial     # 原图灯泡、灯晕与局部反光的统一材质
var _lamp_elapsed := 0.0

# ---- 武器面板成员（面板里所有动态控件引用都缓存在这里，_refresh 时直接改它们）----
var _weapon_panel: Control = null           # 武器面板根节点（其实是 overlay 遮罩，show/hide 控制显隐）
var _weapon_tab_pistol: Button = null       # "手枪"选项卡按钮
var _weapon_tab_machine: Button = null      # "机枪"选项卡按钮
var _weapon_sprite: TextureRect = null      # 左半屏的枪械图片
var _weapon_img_base: Rect2 = Rect2(40, 0, 520, 430)  # 枪图基准框（panel_scale 缩放、居中用的参考矩形）
var _weapon_name_label: Label = null        # 枪械名称（图片下方居中）
var _weapon_count_label: Label = null        # 枪械序号 n/m（名称同行右端）
var _weapon_stat_damage: Label = null       # 「伤害」数值
var _weapon_stat_rate: Label = null         # 「射速」数值
var _weapon_stat_magazine: Label = null     # 「弹夹」数值
var _weapon_stat_reload: Label = null        # 「换弹」数值
var _weapon_price_label: Button = null      # 购买/装备/已装备 按钮（复用价格框位置）
var _weapon_upgrade_label: Label = null      # 强化等级标签（如「Lv.2/10」）
var _weapon_upgrade_gold_btn: Button = null  # 强化「升1级 · N 金币」按钮
var _weapon_upgrade_diamond_btn: Button = null  # 强化「升1级 · N 钻石」按钮
var _homestead_side_btn: Button = null      # 右侧「家园」小框按钮（全屏子面板打开时隐藏）
var _task_side_btn: Button = null           # 右侧「任务」小框按钮（全屏子面板打开时隐藏）
var _task_badge: Control = null             # 任务按钮右上角红点（有成就可领时显示）
var _weapon_cur_tab: String = "pistol"      # 当前选项卡："pistol" / "machine_gun"
var _weapon_cur_id: String = "pistol_m1911" # 当前预览/操作的武器 ID
var _sel_slot: int = 0                       # 装备栏：当前选中的槽（点「装备」时优先装到这里）
var _slot_btns: Array = []                   # 4 个装备栏槽的 Panel（含底色/边框样式）
var _slot_icons: Array = []                  # 4 个槽内的武器图标 TextureRect
var _slot_names: Array = []                  # 4 个槽内的武器名/解锁条件 Label
var _slot_locks: Array = []                  # 4 个槽内的锁图标（仅在锁定槽显示）
var _slot_rects: Array = []                  # 4 个槽在装备栏容器内的矩形（拖拽落点判定用）
var _drag_from := -1                         # 拖拽起始槽下标（-1 = 未在拖）
var _drag_to := -1                           # 当前悬停的目标槽下标（高亮提示）
var _drag_mouse_down := false                # 鼠标是否仍按着（拖拽期间）
var _drag_started := false                   # 是否已越过长按阈值（区分点击 vs 拖拽）
var _drag_hold_ms := 0                          # 鼠标按下的时间戳（毫秒），用于长按判定
var _drag_ghost: Control = null              # 跟随鼠标的半透明幽灵预览
var _slot_confirm: Control = null            # 装备槽解锁确认弹层（点锁定槽时弹出，点确定才真扣钻石）

# _ready()：主界面入口。先把整块铺满视口，再依次搭建背景、顶部、底部、武器面板、
# 设置按钮/面板、右侧家园/任务小框；应用音量、绑定 GameState 的 stats_changed/level_up 信号；
# 最后把局内累计的升级提示(pending_levelups)顺序弹出，并处理若干渲染/行为自测命令行参数。
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_top_left()
	_build_top_center()
	_build_bottom_buttons()
	_build_weapon_panel()
	_build_settings_button()
	_build_shop_button()
	_build_settings_panel()
	_build_task_button()
	GameState.apply_ui_volume()
	# 主界面氛围音：进场后循环播放（音量已由上面 apply_ui_volume 切到「主界面音量」滑块）
	AudioManager.start_ambience()
	GameState.stats_changed.connect(_refresh)
	GameState.level_up.connect(_on_level_up)
	# 成就「可领取」红点：统计数值变化(stats_changed)与领取状态变化(tasks_changed)都要刷新
	GameState.stats_changed.connect(_refresh_task_badge)
	GameState.tasks_changed.connect(_refresh_task_badge)
	_refresh()
	# 返回主界面时，把局内累计的升级提示（pending_levelups）顺序弹出。
	# 钻石不在局内发放，等这里随升级弹窗逐个累加到账号（顶部钻石数随弹窗递增）。
	_levelup_queue.append_array(GameState.pending_levelups)
	_process_levelup_queue()
	# 渲染自测参数：自动打开个人账号界面
	if "--profileshot" in OS.get_cmdline_args():
		_open_profile()
	# 行为自测：换头像→存档→重置→读档
	if "--profiletest" in OS.get_cmdline_args():
		_open_profile()
		_profile_panel._on_avatar_picked(3)
		var ok_pick: bool = GameState.avatar_index == 3
		GameState.player_id = "测试元冰"
		GameState.save_profile()
		GameState.avatar_index = 1
		GameState.player_id = "幸存者_0001"
		GameState.save_profile()
		GameState.load_profile()
		print("PROFILETEST ok pick=", ok_pick, " reset=", GameState.avatar_index == 1 and GameState.player_id == "幸存者_0001")
		get_tree().quit()
	# 行为自测：钻石买断解锁装备格（测完还原钻石与已解锁列表，不污染真实存档）
	if "--slotunlocktest" in OS.get_cmdline_args():
		var d0 := GameState.diamonds
		var slots0: Array = GameState.weapon_unlocked_slots.duplicate()
		# 测试1：钻石充足，依次解锁槽2(100)、槽3(300)
		GameState.diamonds = 500
		GameState.weapon_unlocked_slots = []
		var ok2 := Weapons.unlock_slot(2) and Weapons.is_slot_unlocked(2) and GameState.diamonds == 400
		var ok3 := Weapons.unlock_slot(3) and Weapons.is_slot_unlocked(3) and GameState.diamonds == 100
		# 测试2：重复解锁已解锁槽 → false（不会重复扣钻）
		var ok_dup := not Weapons.unlock_slot(2) and GameState.diamonds == 100
		# 测试3：钻石不足（重置已解锁状态，钻石=50，槽3需300）→ 解锁失败且槽仍锁定、钻石不变
		GameState.weapon_unlocked_slots = []
		GameState.diamonds = 50
		var ok_broke := (not Weapons.unlock_slot(3)) and (not Weapons.is_slot_unlocked(3)) and GameState.diamonds == 50
		# 还原真实存档
		GameState.diamonds = d0
		GameState.weapon_unlocked_slots = slots0
		GameState.save_profile()
		var all_ok := ok2 and ok3 and ok_dup and ok_broke
		print("SLOTUNLOCKTEST ok=", all_ok, " ok2=", ok2, " ok3=", ok3, " ok_dup=", ok_dup, " ok_broke=", ok_broke)
		get_tree().quit()
	if "--homesteadshot" in OS.get_cmdline_args():
		_open_homestead()
	# 渲染自测：农田1=生长中、并先点出作物选择条（不落盘，不污染存档）
	if "--farmgrow" in OS.get_cmdline_args():
		GameState.farm_plots[1] = {"crop": "tomato", "ready_end": int(Time.get_unix_time_from_system() * 1000.0) + 90000}
		GameState.farm_plots[3] = {"crop": "potato", "ready_end": int(Time.get_unix_time_from_system() * 1000.0) + 20000}
		_open_homestead()
	# 渲染自测：农田1=已成熟（不落盘）
	if "--farmready" in OS.get_cmdline_args():
		GameState.farm_plots[1] = {"crop": "watermelon", "ready_end": int(Time.get_unix_time_from_system() * 1000.0) - 5000}
		_open_homestead()
	# 渲染自测：自动打开武器面板（验证侧边框隐藏/价格显示）
	if "--weaponshot" in OS.get_cmdline_args():
		_show_weapon_panel()
		if "--weapon-buy" in OS.get_cmdline_args():
			_weapon_cur_tab = "machine_gun"
			_weapon_cur_id = "mg_mp5"
			_on_weapon_tab("machine_gun")

# 每六秒短暂闪烁一次，灯泡、灯晕和附近反光使用同一强度。
func _process(delta: float) -> void:
	if _lamp_material == null:
		return
	_lamp_elapsed += delta
	_lamp_material.set_shader_parameter("lamp_strength", LampFlicker.strength_at_time(_lamp_elapsed))

# _exit_tree()：离开主界面时兜底停止氛围音。覆盖所有离局路径（进关卡、关卡选择、人物界面等），
# 避免漏掉某条分支导致氛围音一直响。start_ambience 本身是幂等的，重新进主界面仍能正常播放。
func _exit_tree():
	AudioManager.stop_ambience()

# 背景直接使用局部灯光材质，UV 锚定灯泡；不再额外叠加白色圆点。
func _build_background():
	var bg := TextureRect.new()
	bg.name = "HubBackground"
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = 0.0
	bg.offset_top = 0.0
	bg.offset_right = 0.0
	bg.offset_bottom = 0.0
	bg.texture = load("res://art/hub_background.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -10
	_lamp_material = LampFlicker.create_material()
	bg.material = _lamp_material
	add_child(bg)

var _avatar_btn: TextureButton   # 左上角头像（点击打开个人账号界面）
var _profile_panel: Control      # 当前打开的账号界面（自测用）

# _build_top_left()：搭建左上角玩家信息区——圆形描边头像（点击打开账号界面）、
# 等级「Lv.N」、经验「EXP x/y」、经验进度条。数值初始取自 GameState。
func _build_top_left():
	# 头像圆形描边圈
	var ring := Panel.new()
	ring.position = Vector2(16, 16)
	ring.size = Vector2(92, 92)
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(0, 0, 0, 0)
	ring_sb.border_color = Color(0.4, 1.0, 0.6, 0.95)
	ring_sb.set_border_width_all(3)
	ring_sb.set_corner_radius_all(999)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", ring_sb)
	add_child(ring)
	# 头像（圆形 PNG，点击打开个人账号界面）
	_avatar_btn = TextureButton.new()
	_avatar_btn.texture_normal = GameState.avatar_texture()
	_avatar_btn.ignore_texture_size = true
	_avatar_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_btn.position = Vector2(20, 20)
	_avatar_btn.size = Vector2(84, 84)
	_avatar_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar_btn.pressed.connect(_open_profile)
	AudioManager.attach_click(_avatar_btn)
	add_child(_avatar_btn)
	# 等级
	_level_label = Label.new()
	_level_label.text = "Lv.%d" % GameState.level
	_level_label.position = Vector2(116, 24)
	_level_label.add_theme_font_size_override("font_size", 28)
	_level_label.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(_level_label)
	# 经验
	_exp_label = Label.new()
	if GameState.is_max_level():
		_exp_label.text = "EXP MAX"
	else:
		_exp_label.text = "EXP %d/%d" % [GameState.exp, GameState.exp_per_level(GameState.level)]
	_exp_label.position = Vector2(116, 60)
	_exp_label.add_theme_font_size_override("font_size", 16)
	_exp_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	add_child(_exp_label)
	# 经验进度条（位于 EXP 文字下方）
	_exp_bar = ProgressBar.new()
	_exp_bar.min_value = 0.0
	_exp_bar.max_value = 1.0
	_exp_bar.show_percentage = false
	_exp_bar.position = Vector2(116, 86)
	_exp_bar.size = Vector2(168, 14)
	_exp_bar.value = GameState.exp_progress_ratio()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.10, 0.14, 0.12, 1.0)
	bsb.set_corner_radius_all(7)
	bsb.set_border_width_all(2)
	bsb.border_color = Color(0.4, 1.0, 0.6, 0.95)   # 绿边，和头像圈/升级框一致
	_exp_bar.add_theme_stylebox_override("background", bsb)
	var bsf := StyleBoxFlat.new()
	bsf.bg_color = Color(0.35, 0.95, 0.55, 1.0)      # 鲜活绿填充
	bsf.set_corner_radius_all(7)
	_exp_bar.add_theme_stylebox_override("fill", bsf)
	add_child(_exp_bar)
	# 玩家名字（显示在头像信息区下方）。取自 GameState.player_id（可在个人账号面板修改并存档），
	# 放在经验进度条下面、同一列 x=116，不挪动 Lv/EXP/进度条任何位置。
	_name_label = Label.new()
	_name_label.text = GameState.player_id
	_name_label.position = Vector2(116, 106)
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.82))
	add_child(_name_label)

# _open_profile()：打开个人账号界面。若已打开则忽略（防重复叠加），
# 否则实例化 profile_panel、订阅其 profile_changed 信号刷新头像，并隐藏齿轮/侧边小框。
func _open_profile():
	# 防重复：面板已打开就不再叠加一个
	if _profile_panel != null and is_instance_valid(_profile_panel):
		return
	_profile_panel = preload("res://profile_panel.gd").new()
	_profile_panel.profile_changed.connect(_refresh_avatar)
	add_child(_profile_panel)
	_hide_gear_while(_profile_panel)

# 子面板（宝箱/个人账号/武器等）打开时隐藏右上角齿轮 + 右侧家园/任务小框，关闭后恢复。
# 做法：隐藏侧边 chrome，并订阅 panel 的 tree_exited（关闭）来恢复显示。
func _hide_gear_while(panel: Control):
	_set_side_chrome_visible(false)
	panel.tree_exited.connect(_restore_gear)

# _restore_gear()：子面板关闭后回调，恢复右上角齿轮与右侧家园/任务小框的可见性。
# 顺手刷新任务按钮红点：领取完成就关掉面板后，红点应立即消失。
func _restore_gear():
	_set_side_chrome_visible(true)
	_refresh_task_badge()

# 右上角齿轮 + 右侧家园/任务小框，统一开关（全屏子面板打开时必须藏，否则浮在面板之上）。
# 参数 v=true 显示、false 隐藏。
func _set_side_chrome_visible(v: bool):
	if _settings_gear_root != null:
		_settings_gear_root.visible = v
	if _shop_gear_root != null:
		_shop_gear_root.visible = v
	if _homestead_side_btn != null and is_instance_valid(_homestead_side_btn):
		_homestead_side_btn.visible = v
	if _task_side_btn != null and is_instance_valid(_task_side_btn):
		_task_side_btn.visible = v

# _refresh_avatar()：账号界面改了头像后回调，刷新左上角头像贴图为最新头像。
func _refresh_avatar():
	if _avatar_btn != null:
		_avatar_btn.texture_normal = GameState.avatar_texture()
	# 头像变更信号同时可能伴随玩家 ID 变更（改名字后 profile_changed 也会发），一并刷新名字
	if _name_label != null:
		_name_label.text = GameState.player_id

# _build_top_center()：在屏幕正上方居中放置金币/钻石胶囊 HUD。
# 两组胶囊总宽 = 2×130 + 30，故起点 = 视口中线 - 145 才是真正居中。委托 GameState 生成。
func _build_top_center():
	var cx := get_viewport().get_visible_rect().size.x / 2.0
	# 两组胶囊总宽 = 2×130 + 1×30 = 290，起始点 = 中心 - 145 才是真正居中
	var start_x := cx - 145
	_cur_labels = GameState.build_currency_hud(self, start_x, 16)

# _build_bottom_buttons()：在屏幕底部贴边铺一条 HBoxContainer，等分 7 个框
# （武器/人物/图鉴/宝箱/副本/背包/开始游戏）。圆角设为 0 让它们连成一条底栏，
# 窗口缩放时因锚定底边而始终贴边。每个框绑定 _on_bottom_button(idx)。
func _build_bottom_buttons():
	# 7 个选项框：武器 / 人物 / 图鉴 / 宝箱 / 副本 / 背包 / 开始游戏
	# 锚定容器贴屏幕底边并横向铺满——窗口缩放/最大化时底部始终贴边
	# （stretch 用 canvas_items+expand，窗口变宽可视区域跟着变，固定坐标会留缝）
	var labels: Array[String] = ["武器", "人物", "图鉴", "宝箱", "副本", "背包", "开始游戏"]
	var box_h: float = 70.0

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 0
	bar.offset_right = 0
	bar.offset_bottom = 0
	bar.offset_top = -box_h
	bar.add_theme_constant_override("separation", 0)
	add_child(bar)

	# 灰黑色按钮样式（与游戏内菜单一致）
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	normal_style.border_width_left = 1
	normal_style.border_width_top = 2
	normal_style.border_width_right = 1
	normal_style.border_width_bottom = 0
	normal_style.border_color = Color(0.45, 0.45, 0.45, 0.8)
	# 连接在一起时不需要圆角
	normal_style.corner_radius_top_left = 0
	normal_style.corner_radius_top_right = 0
	normal_style.corner_radius_bottom_left = 0
	normal_style.corner_radius_bottom_right = 0
	normal_style.content_margin_left = 10
	normal_style.content_margin_right = 10
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.28, 0.95)
	hover_style.border_width_left = 1
	hover_style.border_width_top = 2
	hover_style.border_width_right = 1
	hover_style.border_width_bottom = 0
	hover_style.border_color = Color(0.6, 0.6, 0.6, 0.9)
	hover_style.corner_radius_top_left = 0
	hover_style.corner_radius_top_right = 0
	hover_style.corner_radius_bottom_left = 0
	hover_style.corner_radius_bottom_right = 0
	hover_style.content_margin_left = 10
	hover_style.content_margin_right = 10
	hover_style.content_margin_top = 8
	hover_style.content_margin_bottom = 8

	for i in range(labels.size()):
		var btn := Button.new()
		btn.text = labels[i]
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", normal_style)
		btn.custom_minimum_size = Vector2(0, box_h)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 7 个框等分满宽、互相紧贴（圆角已设 0 → 连成一条底栏），首尾框贴左右角，撑满整条底边
		btn.size_flags_stretch_ratio = 1.0
		btn.pressed.connect(_on_bottom_button.bind(i))
		bar.add_child(btn)

# _on_bottom_button(idx)：底部 7 个框的点击回调。idx 对应构建顺序——
# 0 武器(开武器面板) / 1 人物(切到 Menu 场景) / 2 图鉴(开图鉴面板) / 3 宝箱(开宝箱面板) /
# 4 副本(开发中) / 5 背包(开背包面板) / 6 开始游戏(进关卡选择场景)。
func _on_bottom_button(idx: int):
	# 主界面选项框点击反馈音效（文件缺失时 play_click 内部静默跳过，不影响功能）
	AudioManager.play_click()
	match idx:
		0:   # 武器 → 武器面板
			_show_weapon_panel()
		1:   # 人物 → 选人界面
			get_tree().change_scene_to_file("res://Menu.tscn")
		2:   # 图鉴 → 丧尸图鉴面板
			_open_codex()
		3:   # 宝箱 → 宝箱界面
			_open_chest()
		4:   # 副本 → 无尽模式
			_open_endless()
		5:   # 背包 → 背包界面
			_open_bag()
		6:   # 开始游戏 → 关卡选择界面（再由「开始」进入游戏）
			get_tree().change_scene_to_file("res://LevelSelect.tscn")

# _show_coming_soon(name)：占位提示，功能未实装（图鉴/副本）时打印日志。
func _show_coming_soon(name: String):
	print("「%s」功能开发中..." % name)

# ============================================================
#  武器面板
# ============================================================
# _build_weapon_panel()：构建武器面板（半透明遮罩 + 全屏面板）。
# 内部含：选项卡(手枪/机枪)、左半屏枪图+切换箭头+名称/序号、右半屏四条数值、
# 价格/装备按钮、强化(金币/钻石)按钮、底部 4 槽装备栏。所有控件引用缓存在成员变量，
# 初始隐藏，最后刷新首把武器显示。注意：函数内大量坐标常量针对视口尺寸动态计算。
func _build_weapon_panel():
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# 半透明遮罩（点击关闭）
	var overlay := ColorRect.new()
	overlay.name = "WeaponOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(_on_weapon_overlay_input)
	add_child(overlay)

	# 面板主体（全屏：撑满整个武器界面）
	var panel := Control.new()
	panel.name = "WeaponPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(panel)

	# 面板背景
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.12, 0.12, 0.13, 0.96)
	panel_bg.border_width_left = 2
	panel_bg.border_width_top = 2
	panel_bg.border_width_right = 2
	panel_bg.border_width_bottom = 2
	panel_bg.border_color = Color(0.5, 0.5, 0.5, 0.7)
	panel_bg.corner_radius_top_left = 10
	panel_bg.corner_radius_top_right = 10
	panel_bg.corner_radius_bottom_left = 10
	panel_bg.corner_radius_bottom_right = 10

	# Panel 直接应用 StyleBox，避免创建不挂到场景树的 ColorRect。
	var panel_ctrl := Panel.new()
	panel_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_ctrl.add_theme_stylebox_override("panel", panel_bg)
	panel.add_child(panel_ctrl)

	# ---- 关闭按钮（右上角 ×）----
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	close_btn.flat = true
	close_btn.position = Vector2(vw - 44, 8)
	close_btn.size = Vector2(36, 36)
	close_btn.pressed.connect(_hide_weapon_panel)
	panel.add_child(close_btn)

	# ---- 选项卡区域 ----
	var tab_y: float = 14.0
	var tab_h: float = 38.0
	var tab_w: float = 110.0

	var tab_style_normal := StyleBoxFlat.new()
	tab_style_normal.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	tab_style_normal.border_width_top = 2
	tab_style_normal.border_width_left = 2
	tab_style_normal.border_width_right = 2
	tab_style_normal.border_width_bottom = 0
	tab_style_normal.border_color = Color(0.45, 0.45, 0.45, 0.6)
	tab_style_normal.corner_radius_top_left = 6
	tab_style_normal.corner_radius_top_right = 6

	var tab_style_active := StyleBoxFlat.new()
	tab_style_active.bg_color = Color(0.30, 0.35, 0.42, 1.0)
	tab_style_active.border_width_top = 2
	tab_style_active.border_width_left = 2
	tab_style_active.border_width_right = 2
	tab_style_active.border_width_bottom = 0
	tab_style_active.border_color = Color(0.7, 0.75, 0.85, 0.9)
	tab_style_active.corner_radius_top_left = 6
	tab_style_active.corner_radius_top_right = 6

	# 手枪选项卡
	var btn_pistol := Button.new()
	btn_pistol.text = "手枪"
	btn_pistol.add_theme_font_size_override("font_size", 18)
	btn_pistol.position = Vector2(80, tab_y)
	btn_pistol.size = Vector2(tab_w, tab_h)
	btn_pistol.add_theme_stylebox_override("normal", tab_style_active)
	btn_pistol.add_theme_stylebox_override("hover", tab_style_active)
	btn_pistol.pressed.connect(_on_weapon_tab.bind("pistol"))
	panel.add_child(btn_pistol)
	_weapon_tab_pistol = btn_pistol

	# 机枪选项卡
	var btn_machine := Button.new()
	btn_machine.text = "机枪"
	btn_machine.add_theme_font_size_override("font_size", 18)
	btn_machine.position = Vector2(80 + tab_w, tab_y)
	btn_machine.size = Vector2(tab_w, tab_h)
	btn_machine.add_theme_stylebox_override("normal", tab_style_normal)
	btn_machine.add_theme_stylebox_override("hover", tab_style_normal)
	btn_machine.pressed.connect(_on_weapon_tab.bind("machine_gun"))
	panel.add_child(btn_machine)
	_weapon_tab_machine = btn_machine

	# 选项卡底部横线
	var tab_line := ColorRect.new()
	tab_line.color = Color(0.45, 0.45, 0.45, 0.6)
	tab_line.position = Vector2(80, tab_y + tab_h)
	tab_line.size = Vector2(tab_w * 2, 2)
	panel.add_child(tab_line)

	# ---- 内容区域分割线的 y 坐标 ----
	var content_y: float = tab_y + tab_h + 6

	# ---- 左侧：枪械图片（带暗色背景，铺满左半屏）----
	var img_x: float = 40.0
	var img_w: float = vw * 0.44
	var img_h: float = vh - content_y - 170.0
	var img_bg := ColorRect.new()
	img_bg.color = Color(0.08, 0.08, 0.09, 1.0)
	img_bg.position = Vector2(img_x, content_y)
	img_bg.size = Vector2(img_w, img_h)
	panel.add_child(img_bg)

	# 武器图安全区：框内四周留边（左右各 52 清开两侧箭头，上下 24），
	# 宽枪（M249/AK47 横向比例大）适配时不会顶满边框、也不会盖住箭头
	var pad_x: float = 52.0
	var pad_y: float = 24.0
	var safe := Rect2(img_x + pad_x, content_y + pad_y, img_w - pad_x * 2.0, img_h - pad_y * 2.0)
	_weapon_sprite = TextureRect.new()
	_weapon_sprite.position = safe.position
	_weapon_sprite.size = safe.size
	# 在安全区内完整显示枪械，保持比例并居中
	_weapon_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.add_child(_weapon_sprite)
	_weapon_img_base = safe

	# 枪械切换箭头（← →）
	var arrow_style := StyleBoxFlat.new()
	arrow_style.bg_color = Color(0.20, 0.20, 0.22, 0.9)
	arrow_style.border_width_left = 1; arrow_style.border_width_top = 1
	arrow_style.border_width_right = 1; arrow_style.border_width_bottom = 1
	arrow_style.border_color = Color(0.5, 0.5, 0.5, 0.6)
	arrow_style.corner_radius_top_left = 6; arrow_style.corner_radius_top_right = 6
	arrow_style.corner_radius_bottom_left = 6; arrow_style.corner_radius_bottom_right = 6

	var btn_prev := Button.new()
	btn_prev.text = "←"
	btn_prev.add_theme_font_size_override("font_size", 28)
	btn_prev.add_theme_stylebox_override("normal", arrow_style)
	btn_prev.add_theme_stylebox_override("hover", arrow_style)
	btn_prev.add_theme_stylebox_override("pressed", arrow_style)
	btn_prev.position = Vector2(img_x + 4, content_y + img_h / 2.0 - 45)
	btn_prev.size = Vector2(40, 90)
	btn_prev.pressed.connect(_on_weapon_prev)
	panel.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = "→"
	btn_next.add_theme_font_size_override("font_size", 28)
	btn_next.add_theme_stylebox_override("normal", arrow_style)
	btn_next.add_theme_stylebox_override("hover", arrow_style)
	btn_next.add_theme_stylebox_override("pressed", arrow_style)
	btn_next.position = Vector2(img_x + img_w - 42, content_y + img_h / 2.0 - 45)
	btn_next.size = Vector2(38, 90)
	btn_next.pressed.connect(_on_weapon_next)
	panel.add_child(btn_next)

	# 枪械名称（图片下方）
	_weapon_name_label = Label.new()
	_weapon_name_label.add_theme_font_size_override("font_size", 18)
	_weapon_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_name_label.position = Vector2(img_x, content_y + img_h - 34)
	_weapon_name_label.size = Vector2(img_w, 28)
	panel.add_child(_weapon_name_label)

	# 枪械序号（n/m，放在名称同一行右端）
	_weapon_count_label = Label.new()
	_weapon_count_label.add_theme_font_size_override("font_size", 16)
	_weapon_count_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_weapon_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_count_label.position = Vector2(img_x, content_y + img_h - 34)
	_weapon_count_label.size = Vector2(img_w, 28)
	panel.add_child(_weapon_count_label)

	# ---- 右侧：数值面板（铺满右半屏）----
	var stat_x: float = vw * 0.52
	var stat_w: float = vw * 0.44

	# 数值框通用样式
	var stat_box_style := StyleBoxFlat.new()
	stat_box_style.bg_color = Color(0.10, 0.10, 0.11, 0.9)
	stat_box_style.border_width_left = 1
	stat_box_style.border_width_top = 1
	stat_box_style.border_width_right = 1
	stat_box_style.border_width_bottom = 1
	stat_box_style.border_color = Color(0.4, 0.4, 0.4, 0.6)
	stat_box_style.corner_radius_top_left = 6
	stat_box_style.corner_radius_top_right = 6
	stat_box_style.corner_radius_bottom_left = 6
	stat_box_style.corner_radius_bottom_right = 6
	stat_box_style.content_margin_left = 16
	stat_box_style.content_margin_right = 16
	stat_box_style.content_margin_top = 10
	stat_box_style.content_margin_bottom = 10

	# 四个数值框（伤害/射速/弹夹/换弹）
	_build_stat_row(panel, stat_x, content_y + 8, stat_w, 60, stat_box_style, "伤害", "_dmg")
	_build_stat_row(panel, stat_x, content_y + 74, stat_w, 60, stat_box_style, "射速", "_rate")
	_build_stat_row(panel, stat_x, content_y + 140, stat_w, 60, stat_box_style, "弹夹", "_mag")
	_build_stat_row(panel, stat_x, content_y + 206, stat_w, 60, stat_box_style, "换弹", "_reload")

	# 查找对应的 Label（用 name 匹配）
	for c in panel.get_children():
		if c is Label and c.name == "stat_val_dmg":
			_weapon_stat_damage = c
		elif c is Label and c.name == "stat_val_rate":
			_weapon_stat_rate = c
		elif c is Label and c.name == "stat_val_mag":
			_weapon_stat_magazine = c
		elif c is Label and c.name == "stat_val_reload":
			_weapon_stat_reload = c

	# ---- 价格框（下方）----
	var price_style := StyleBoxFlat.new()
	price_style.bg_color = Color(0.18, 0.14, 0.08, 0.95)
	price_style.border_width_left = 1
	price_style.border_width_top = 1
	price_style.border_width_right = 1
	price_style.border_width_bottom = 1
	price_style.border_color = Color(0.7, 0.55, 0.2, 0.8)
	price_style.corner_radius_top_left = 6
	price_style.corner_radius_top_right = 6
	price_style.corner_radius_bottom_left = 6
	price_style.corner_radius_bottom_right = 6
	price_style.content_margin_left = 20
	price_style.content_margin_right = 20
	price_style.content_margin_top = 12
	price_style.content_margin_bottom = 12

	var price_style_disabled := StyleBoxFlat.new()
	price_style_disabled.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	price_style_disabled.border_width_left = 1; price_style_disabled.border_width_top = 1
	price_style_disabled.border_width_right = 1; price_style_disabled.border_width_bottom = 1
	price_style_disabled.border_color = Color(0.4, 0.4, 0.4, 0.6)
	price_style_disabled.corner_radius_top_left = 6; price_style_disabled.corner_radius_top_right = 6
	price_style_disabled.corner_radius_bottom_left = 6; price_style_disabled.corner_radius_bottom_right = 6

	# 购买 / 装备 / 已装备 按钮（复用价格框位置 stat_x, content_y+280）
	var action_btn := Button.new()
	action_btn.add_theme_font_size_override("font_size", 22)
	action_btn.add_theme_stylebox_override("normal", price_style)
	action_btn.add_theme_stylebox_override("hover", price_style)
	action_btn.add_theme_stylebox_override("pressed", price_style)
	action_btn.add_theme_stylebox_override("disabled", price_style_disabled)
	action_btn.position = Vector2(stat_x, content_y + 280)
	action_btn.size = Vector2(stat_w, 54)
	action_btn.pressed.connect(_on_weapon_action_pressed)
	panel.add_child(action_btn)
	_weapon_price_label = action_btn

	# ---- 强化（升级）区：已购买的枪可花金币 / 钻石升级 ----
	var up_label := Label.new()
	up_label.add_theme_font_size_override("font_size", 16)
	up_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40, 1))
	up_label.position = Vector2(stat_x, content_y + 344)
	up_label.size = Vector2(stat_w, 22)
	panel.add_child(up_label)
	_weapon_upgrade_label = up_label

	var gold_btn := Button.new()
	gold_btn.add_theme_font_size_override("font_size", 18)
	gold_btn.position = Vector2(stat_x, content_y + 372)
	gold_btn.size = Vector2(stat_w / 2.0 - 6, 44)
	gold_btn.pressed.connect(_on_weapon_upgrade.bind("gold"))
	panel.add_child(gold_btn)
	_weapon_upgrade_gold_btn = gold_btn

	var dia_btn := Button.new()
	dia_btn.add_theme_font_size_override("font_size", 18)
	dia_btn.position = Vector2(stat_x + stat_w / 2.0 + 6, content_y + 372)
	dia_btn.size = Vector2(stat_w / 2.0 - 6, 44)
	dia_btn.pressed.connect(_on_weapon_upgrade.bind("diamond"))
	panel.add_child(dia_btn)
	_weapon_upgrade_diamond_btn = dia_btn

	# 底部装备栏（4 槽，槽 2/3 用钻石买断解锁，花费见 Weapons.SLOT_DIAMOND_COST）
	_build_loadout_bar(panel, vw, vh)

	# 初始隐藏
	overlay.hide()
	_weapon_panel = overlay
	# 刷新显示第一把武器
	_refresh_weapon_display()

# _build_stat_row(...)：复用的数值行构造器。在 (x,y) 处放一个 Panel，
# 左放标签文字 label_text，右放数值 Label（name 设为 "stat_val"+val_suffix 以便后面按名查找）。
# 参数：parent 父控件，x/y/w/h 布局，pbox_style 面板样式，label_text 名称，val_suffix 数值后缀。
func _build_stat_row(parent: Control, x: float, y: float, w: float, h: float,
		pbox_style: StyleBoxFlat, label_text: String, val_suffix: String):
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", pbox_style)
	box.position = Vector2(x, y)
	box.size = Vector2(w, h)
	parent.add_child(box)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	lbl.position = Vector2(x + 20, y + (h - 28) / 2.0)
	lbl.size = Vector2(80, 28)
	parent.add_child(lbl)

	var val := Label.new()
	val.name = "stat_val" + val_suffix
	val.add_theme_font_size_override("font_size", 24)
	val.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.position = Vector2(x + w - 120, y + (h - 32) / 2.0)
	val.size = Vector2(100, 32)
	parent.add_child(val)

# _on_weapon_tab(tab)：点击选项卡回调。tab="pistol"/"machine_gun"，更新两个选项卡样式
# （选中高亮、未选普通），并把当前预览武器切到该类型的第一把，最后刷新显示。
func _on_weapon_tab(tab: String):
	_weapon_cur_tab = tab
	# 更新选项卡样式
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0.30, 0.35, 0.42, 1.0)
	active_style.border_width_top = 2; active_style.border_width_left = 2
	active_style.border_width_right = 2; active_style.border_width_bottom = 0
	active_style.border_color = Color(0.7, 0.75, 0.85, 0.9)
	active_style.corner_radius_top_left = 6; active_style.corner_radius_top_right = 6
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	normal_style.border_width_top = 2; normal_style.border_width_left = 2
	normal_style.border_width_right = 2; normal_style.border_width_bottom = 0
	normal_style.border_color = Color(0.45, 0.45, 0.45, 0.6)
	normal_style.corner_radius_top_left = 6; normal_style.corner_radius_top_right = 6

	_weapon_tab_pistol.add_theme_stylebox_override("normal", active_style if tab == "pistol" else normal_style)
	_weapon_tab_machine.add_theme_stylebox_override("normal", active_style if tab == "machine_gun" else normal_style)

	# 选该类型的第一把武器
	for id in Weapons.ORDER:
		if Weapons.DATA[id]["type"] == tab:
			_weapon_cur_id = id
			break
	_refresh_weapon_display()

# _apply_weapon_tab_style()：只按 _weapon_cur_tab 刷新两个选项卡的样式（选中高亮/普通）。
# 从 _on_weapon_tab 拆出来，供「点装备槽切换预览武器」时复用，避免切枪后选项卡高亮不同步。
func _apply_weapon_tab_style():
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0.30, 0.35, 0.42, 1.0)
	active_style.border_width_top = 2; active_style.border_width_left = 2
	active_style.border_width_right = 2; active_style.border_width_bottom = 0
	active_style.border_color = Color(0.7, 0.75, 0.85, 0.9)
	active_style.corner_radius_top_left = 6; active_style.corner_radius_top_right = 6
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	normal_style.border_width_top = 2; normal_style.border_width_left = 2
	normal_style.border_width_right = 2; normal_style.border_width_bottom = 0
	normal_style.border_color = Color(0.45, 0.45, 0.45, 0.6)
	normal_style.corner_radius_top_left = 6; normal_style.corner_radius_top_right = 6
	_weapon_tab_pistol.add_theme_stylebox_override("normal", active_style if _weapon_cur_tab == "pistol" else normal_style)
	_weapon_tab_machine.add_theme_stylebox_override("normal", active_style if _weapon_cur_tab == "machine_gun" else normal_style)

# _on_weapon_prev()：左箭头，切到当前类型里的上一把武器（循环），刷新显示。
func _on_weapon_prev():
	var ids: Array[String] = []
	for id in Weapons.ORDER:
		if Weapons.DATA[id]["type"] == _weapon_cur_tab:
			ids.append(id)
	if ids.size() == 0:
		return
	var idx := ids.find(_weapon_cur_id)
	idx = (idx - 1 + ids.size()) % ids.size()
	_weapon_cur_id = ids[idx]
	_refresh_weapon_display()

# _on_weapon_next()：右箭头，切到当前类型里的下一把武器（循环），刷新显示。
func _on_weapon_next():
	var ids: Array[String] = []
	for id in Weapons.ORDER:
		if Weapons.DATA[id]["type"] == _weapon_cur_tab:
			ids.append(id)
	if ids.size() == 0:
		return
	var idx := ids.find(_weapon_cur_id)
	idx = (idx + 1) % ids.size()
	_weapon_cur_id = ids[idx]
	_refresh_weapon_display()

# _equip_target_slot()：计算「装备」按钮实际要装入的目标槽，规则见上方注释——
# ① 选中槽空且已解锁→用它；② 否则找第一个已解锁空槽（不挤掉已有枪）；
# ③ 全满→退回选中槽（由 Weapons.equip_to_slot 的去重语义兜底替换）。返回槽序号。
func _equip_target_slot() -> int:
	if Weapons.is_slot_unlocked(_sel_slot) and Weapons.loadout[_sel_slot] == "":
		return _sel_slot
	for i in range(Weapons.LOADOUT_SLOT_COUNT):
		if not Weapons.is_slot_unlocked(i):
			continue
		if Weapons.loadout[i] == "":
			return i
	return clampi(_sel_slot, 0, Weapons.unlocked_slot_count() - 1)

# _on_weapon_action_pressed()：价格框按钮点击。已装备 → 从所在槽卸下；未装备但已拥有 → 装到目标槽；
# 未拥有 → 花金币购买（只解锁不自动装备）。随后刷新装备栏/显示/顶栏。
func _on_weapon_action_pressed():
	var id := _weapon_cur_id
	if Weapons.is_unlocked(id):
		var at := Weapons.loadout.find(id)
		if at >= 0:
			# 已装备 → 卸下
			Weapons.unequip_from_slot(at)
		else:
			Weapons.equip_to_slot(_equip_target_slot(), id)
	else:
		Weapons.buy(id)          # 买了只是「拥有」，不自动装备，装备需再点一次
	_refresh_loadout_bar()
	_refresh_weapon_display()
	_refresh()   # 同步刷新顶部金币 HUD

# _on_weapon_upgrade(kind)：强化按钮点击。kind="gold"/"diamond" 决定花哪种货币升 1 级，
# 仅已购枪可升。成功则刷新武器显示、装备栏、顶部货币 HUD。
func _on_weapon_upgrade(kind: String):
	if not Weapons.is_unlocked(_weapon_cur_id):
		return
	var ok: bool = GameState.upgrade_weapon(_weapon_cur_id, kind)
	if ok:
		_refresh_weapon_display()
		_refresh_loadout_bar()
		_refresh()   # 同步刷新顶部金币/钻石 HUD

# _refresh_weapon_display()：核心刷新——根据 _weapon_cur_id 重绘武器面板当前这一把：
# 枪图(按 panel_scale 缩放居中)、名称、序号 n/m、四项强化后有效数值；并刷新价格框按钮
# （未拥有/已装备/可装备三态）、强化区（等级与金币/钻石升1级花费）。价格不足时置灰。
func _refresh_weapon_display():
	var data: Dictionary = Weapons.DATA.get(_weapon_cur_id, Weapons.DATA["pistol_m1911"])
	# 枪械贴图
	_weapon_sprite.texture = load(data["texture"])
	# 面板内显示缩放：按 panel_scale 在原基准框内等比缩小并居中
	var s: float = float(data.get("panel_scale", 1.0))
	_weapon_sprite.size = _weapon_img_base.size * s
	_weapon_sprite.position = _weapon_img_base.position + _weapon_img_base.size * (1.0 - s) * 0.5
	# 名称
	_weapon_name_label.text = data["name"]
	# 序号 n/m（当前类别内第几把 / 共几把）
	var ids: Array[String] = []
	for id in Weapons.ORDER:
		if Weapons.DATA[id]["type"] == _weapon_cur_tab:
			ids.append(id)
	var idx := ids.find(_weapon_cur_id)
	_weapon_count_label.text = "%d/%d" % [idx + 1, ids.size()]
	# 数值（显示强化后的有效数值）
	_weapon_stat_damage.text = str(Weapons.effective_damage(_weapon_cur_id))
	_weapon_stat_rate.text = "%.1f/s" % Weapons.effective_fire_rate(_weapon_cur_id)
	_weapon_stat_magazine.text = str(Weapons.effective_magazine(_weapon_cur_id))
	_weapon_stat_reload.text = "%.1f s" % Weapons.effective_reload(_weapon_cur_id)
	# 购买 / 装备 / 卸下 按钮
	#   已装备 → 显示实际所在槽，按钮可点=「卸下（槽 N）」（橙色）
	#   未装备 → 目标槽 = 选中槽（若空）或第一个空槽；槽全满时 = 选中槽
	#   金色高亮同步跟随真实目标槽，保证按钮文字和高亮槽一致
	var price: int = data["price"]
	var owned: bool = Weapons.is_unlocked(_weapon_cur_id)
	var equipped_at: int = Weapons.loadout.find(_weapon_cur_id)
	_weapon_price_label.disabled = false
	_weapon_price_label.remove_theme_color_override("font_color")
	_weapon_price_label.remove_theme_color_override("font_disabled_color")
	if not owned:
		_weapon_price_label.text = "购买 · %d 金币" % price
		if GameState.gold >= price:
			_weapon_price_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		else:
			_weapon_price_label.disabled = true
			_weapon_price_label.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.55))
	else:
		var target: int = equipped_at if equipped_at >= 0 else _equip_target_slot()
		if _sel_slot != target:
			_sel_slot = target
			_refresh_loadout_bar()
		if equipped_at >= 0:
			# 已装备 → 按钮变成「卸下」，点了能把枪从该槽取下（仅取消携带，不退款）
			_weapon_price_label.text = "卸下（槽 %d）" % (equipped_at + 1)
			_weapon_price_label.disabled = false
			_weapon_price_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.45))
		else:
			_weapon_price_label.text = "装备（槽 %d）" % (target + 1)
			_weapon_price_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))

	# ---- 强化区（仅已购买的枪显示）----
	var owned_u: bool = Weapons.is_unlocked(_weapon_cur_id)
	var lv_u: int = GameState.weapon_upgrade_levels.get(_weapon_cur_id, 0)
	if not owned_u:
		_weapon_upgrade_label.visible = false
		_weapon_upgrade_gold_btn.visible = false
		_weapon_upgrade_diamond_btn.visible = false
	else:
		_weapon_upgrade_label.visible = true
		_weapon_upgrade_gold_btn.visible = true
		_weapon_upgrade_diamond_btn.visible = true
		_weapon_upgrade_label.text = "强化等级 Lv.%d/%d" % [lv_u, GameState.WEAPON_MAX_UPGRADE]
		if lv_u >= GameState.WEAPON_MAX_UPGRADE:
			_weapon_upgrade_gold_btn.text = "已满级"
			_weapon_upgrade_gold_btn.disabled = true
			_weapon_upgrade_diamond_btn.text = "已满级"
			_weapon_upgrade_diamond_btn.disabled = true
		else:
			var gc_u: int = GameState.weapon_upgrade_gold_cost(_weapon_cur_id, lv_u)
			var dc_u: int = GameState.weapon_upgrade_diamond_cost(_weapon_cur_id, lv_u)
			_weapon_upgrade_gold_btn.text = "升1级 · %d 金币" % gc_u
			_weapon_upgrade_diamond_btn.text = "升1级 · %d 钻石" % dc_u
			_weapon_upgrade_gold_btn.disabled = GameState.gold < gc_u
			_weapon_upgrade_diamond_btn.disabled = GameState.diamonds < dc_u

# _show_weapon_panel()：打开武器面板。重置到手枪标签/首把武器、刷新装备栏，
# 显示面板并把齿轮+侧边小框藏起来（全屏面板盖住主界面时不能浮在上面）。
func _show_weapon_panel():
	_weapon_cur_tab = "pistol"
	_weapon_cur_id = "pistol_m1911"
	_on_weapon_tab("pistol")
	_weapon_panel.show()
	_refresh_loadout_bar()   # 每次打开刷新装备栏，反映最新的槽位解锁进度
	# 全屏武器界面盖住主界面 → 齿轮 + 右侧家园/任务小框一并隐藏
	_set_side_chrome_visible(false)

# _hide_weapon_panel()：关闭武器面板，恢复齿轮+侧边小框可见性。
func _hide_weapon_panel():
	_weapon_panel.hide()
	_set_side_chrome_visible(true)

# ============================================================
#  底部装备栏（loadout）：4 个槽，槽 2/3 用钻石买断解锁，花费见 Weapons.SLOT_DIAMOND_COST
# ============================================================
# _build_loadout_bar(parent, vw, vh)：构建底部 4 槽装备栏（槽 2/3 用钻石买断解锁）。
# 含提示标题、居中排列的 4 个槽（序号/图标/名称/锁）、整槽可点 hit 按钮，最后刷新一次。
# 参数 vw/vh 为视口尺寸，用于定位与尺寸计算。
func _build_loadout_bar(parent: Control, vw: float, vh: float):
	# 清空旧引用（保险）
	_slot_btns = []
	_slot_icons = []
	_slot_names = []
	_slot_locks = []
	_slot_rects = []
	var bar_h: float = 150.0
	var bar_y: float = vh - bar_h
	var slot_h: float = bar_h - 20.0
	# 提示标题
	var hint := Label.new()
	hint.text = "装备栏：短按槽位查看该枪数值；长按已装备的枪拖到另一个已装备的枪可调换位置；点已装备的枪可「卸下」；游戏中按 Q 切换手持武器"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	hint.position = Vector2(40, bar_y - 30)
	hint.size = Vector2(vw - 80, 24)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)
	# 4 个槽居中排列
	var slot_w: float = min(160.0, (vw - 80.0) / float(Weapons.LOADOUT_SLOT_COUNT) - 20.0)
	var gap: float = 24.0
	var total_w: float = Weapons.LOADOUT_SLOT_COUNT * slot_w + (Weapons.LOADOUT_SLOT_COUNT - 1) * gap
	var start_x: float = (vw - total_w) / 2.0
	for i in range(Weapons.LOADOUT_SLOT_COUNT):
		var slot := Panel.new()
		slot.name = "LoadoutSlot%d" % i
		slot.position = Vector2(start_x + i * (slot_w + gap), bar_y)
		slot.size = Vector2(slot_w, slot_h)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.14, 0.95)
		sb.border_width_left = 2; sb.border_width_top = 2; sb.border_width_right = 2; sb.border_width_bottom = 2
		sb.border_color = Color(0.4, 0.4, 0.4, 0.8)
		sb.set_corner_radius_all(10)
		slot.add_theme_stylebox_override("panel", sb)
		parent.add_child(slot)
		# 序号
		var num := Label.new()
		num.text = "槽 %d" % (i + 1)
		num.add_theme_font_size_override("font_size", 14)
		num.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		num.position = Vector2(8, 6)
		slot.add_child(num)
		# 武器图标（固定安全框 + 等比居中：枪完整落在框内，绝不溢出格子）
		var icon_box: float = 60.0
		var icon := TextureRect.new()
		icon.position = Vector2(slot_w / 2.0 - icon_box / 2.0, (slot_h - icon_box) / 2.0)
		icon.size = Vector2(icon_box, icon_box)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		# 武器名（贴槽内底部：槽高 130，标签放 y=slot_h-24 才不会被裁掉）
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", 13)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.position = Vector2(4, slot_h - 24)
		nm.size = Vector2(slot_w - 8, 18)
		slot.add_child(nm)
		# 锁定槽的锁图标（居中，默认隐藏，_refresh_loadout_bar 控制显隐）
		var lock := TextureRect.new()
		lock.texture = _lock_icon_tex()
		lock.position = Vector2(slot_w / 2.0 - 19, slot_h / 2.0 - 21)
		lock.size = Vector2(38, 42)
		lock.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.visible = false
		slot.add_child(lock)
		_slot_locks.append(lock)
		_slot_btns.append(slot)
		_slot_icons.append(icon)
		_slot_names.append(nm)
		# 整槽可点 + 可长按拖拽调换（锁定槽不做任何反应）
		var hit := Control.new()
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.gui_input.connect(_on_slot_input.bind(i))
		slot.add_child(hit)
	_refresh_loadout_bar()
	# 布局完成后再取全局矩形（此时容器已就位，get_global_rect 才准确；拖拽落点判定用视口坐标）
	for i in range(_slot_btns.size()):
		_slot_rects.append(_slot_btns[i].get_global_rect())

# _refresh_loadout_bar()：按 Weapons 数据刷新 4 个槽的外观——锁定槽显示解锁条件+进度+锁图标；
# 已解锁空槽显示「空」；已装枪显示图标+名称；选中槽描金边。最后统一刷新锁/图标/名称/边框。
func _refresh_loadout_bar():
	for i in range(_slot_btns.size()):
		var sb := _slot_btns[i].get_theme_stylebox("panel") as StyleBoxFlat
		var locked: bool = not Weapons.is_slot_unlocked(i)
		if locked:
			_slot_icons[i].texture = null
			# 锁定槽：显示解锁条件 + 当前进度，让玩家知道怎么解锁
			var cond := Weapons.slot_unlock_text(i)
			var prog := Weapons.slot_unlock_progress_text(i)
			if prog != "":
				_slot_names[i].text = "%s（%s）" % [cond, prog]
			else:
				_slot_names[i].text = cond
			_slot_names[i].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			sb.bg_color = Color(0.07, 0.07, 0.09, 0.95)
			sb.border_color = Color(0.5, 0.4, 0.4, 0.85)
			_slot_locks[i].visible = true
		else:
			_slot_locks[i].visible = false
			sb.bg_color = Color(0.12, 0.12, 0.14, 0.95)
			var wid: String = Weapons.loadout[i]
			if wid != "" and Weapons.DATA.has(wid):
				_slot_icons[i].texture = load(Weapons.DATA[wid]["texture"])
				_slot_names[i].text = Weapons.DATA[wid]["name"]
				_slot_names[i].add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			else:
				_slot_icons[i].texture = null
				_slot_names[i].text = "空"
				_slot_names[i].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			# 选中槽高亮（金边）；仅当该槽已解锁时高亮才有效
			if i == _sel_slot and Weapons.is_slot_unlocked(i):
				sb.border_color = Color(1.0, 0.8, 0.2, 1.0)
			else:
				sb.border_color = Color(0.4, 0.4, 0.4, 0.8)

# ============================================================================
#  装备槽「长按拖拽调换」交互
# ----------------------------------------------------------------------------
# 规则：只在「两个槽都装了枪」之间调换；空槽/锁定槽不可作为拖拽起点或落点。
# 判定：鼠标按下后按住 ≥ DRAG_HOLD_SEC 才算拖拽（避免和单击选槽冲突），
#       拖拽中显示半透明幽灵跟随鼠标，并实时高亮落点槽；松手时交换两槽内容。
# ============================================================================
const DRAG_HOLD_SEC := 0.28     # 判定为拖拽所需的最短按住时长（秒）

# _on_slot_input(event, i)：装备槽的输入回调。按下→记录起点、起计时；移动→越过阈值开始拖拽；
# 松手→若已进入拖拽则尝试交换，否则按普通点击处理。锁定槽直接吞掉事件。
func _on_slot_input(event: InputEvent, i: int):
	if not Weapons.is_slot_unlocked(i):
		return                                   # 锁定槽：既不能拖也不能选

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 只有「装了枪」的槽才能当拖拽起点
			if Weapons.loadout[i] == "":
				return
			_drag_from = i
			_drag_to = -1
			_drag_mouse_down = true
			_drag_started = false
			_drag_hold_ms = Time.get_ticks_msec()
		else:
			# 松手
			if _drag_mouse_down and _drag_started and _drag_to >= 0 and _drag_to != _drag_from:
				_swap_slots(_drag_from, _drag_to)
			elif not _drag_started:
				# 短按 = 普通点击选槽
				_on_slot_clicked(i)
			_end_drag()
		return

	if event is InputEventMouseMotion and _drag_mouse_down:
		# 超过时间阈值才算拖拽（用真实时钟，抗帧率波动）
		if not _drag_started and (Time.get_ticks_msec() - _drag_hold_ms) >= int(DRAG_HOLD_SEC * 1000.0):
			_drag_started = true
			_make_ghost(_drag_from)
		if _drag_started:
			_drag_to = _slot_under_mouse()
			_update_ghost(event.global_position)
			_refresh_drag_highlight()

# _slot_under_mouse()：当前鼠标位置落在哪个槽内（-1 = 没落在任何槽上）。只认已解锁且装了枪的槽。
func _slot_under_mouse() -> int:
	var mp := get_viewport().get_mouse_position()
	for i in range(_slot_rects.size()):
		if _slot_rects[i].has_point(mp):
			if Weapons.is_slot_unlocked(i) and Weapons.loadout[i] != "":
				return i
	return -1

# _make_ghost(slot)：创建跟随鼠标的半透明幽灵预览（显示被拖动那把枪的图标）。
func _make_ghost(slot: int):
	_end_ghost()
	var wid: String = Weapons.loadout[slot]
	if wid == "" or not Weapons.DATA.has(wid):
		return
	_drag_ghost = Control.new()
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate = Color(1, 1, 1, 0.75)
	# 幽灵尺寸 = 源槽尺寸
	var r: Rect2 = _slot_rects[slot]
	_drag_ghost.size = r.size
	add_child(_drag_ghost)
	# 幽灵里放一个武器图标（复用贴图）
	var icon := TextureRect.new()
	icon.texture = load(Weapons.DATA[wid]["texture"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(r.size.x * 0.22, r.size.y * 0.12)
	icon.size = Vector2(r.size.x * 0.56, r.size.y * 0.56)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.add_child(icon)
	_update_ghost(get_viewport().get_mouse_position())

# _update_ghost(global_pos)：让幽灵贴到鼠标位置（居中偏移）。
func _update_ghost(global_pos: Vector2):
	if _drag_ghost == null or not is_instance_valid(_drag_ghost):
		return
	_drag_ghost.position = global_pos - _drag_ghost.size * 0.5

# _refresh_drag_highlight()：拖拽中把落点槽描成蓝色边（提示会交换到这里）。
func _refresh_drag_highlight():
	for i in range(_slot_btns.size()):
		var sb: StyleBoxFlat = _slot_btns[i].get_theme_stylebox("panel") as StyleBoxFlat
		if _drag_started and i == _drag_to and i != _drag_from:
			sb.border_color = Color(0.4, 0.75, 1.0, 1.0)   # 蓝色：松手即交换
		elif _drag_started and i == _drag_from:
			sb.border_color = Color(1.0, 0.8, 0.2, 1.0)     # 源槽保持金边
		# 其它槽不动——_refresh_loadout_bar 统一重绘，这里只叠加拖拽高亮

# _swap_slots(a, b)：交换两个装了枪的槽。直接改 Weapons.loadout，再走 equip 流程的持久化。
func _swap_slots(a: int, b: int):
	var wa: String = Weapons.loadout[a]
	var wb: String = Weapons.loadout[b]
	if wa == "" or wb == "":
		return
	Weapons.swap_slots(a, b)
	_refresh_loadout_bar()
	_refresh_weapon_display()
	_toast("已调换槽 %d 与槽 %d" % [a + 1, b + 1])

# _end_drag()：清理拖拽状态（保留换槽结果）。
func _end_drag():
	_drag_from = -1
	_drag_to = -1
	_drag_mouse_down = false
	_drag_started = false
	_drag_hold_ms = 0
	_end_ghost()
	_refresh_loadout_bar()   # 清掉拖拽高亮

# _end_ghost()：销毁幽灵预览。
func _end_ghost():
	if _drag_ghost != null and is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null

# _on_slot_clicked(i)：点击某个装备槽。
#   锁定槽 → 只弹「确认解锁」弹层（不立刻扣钻石），点确定才真正买断；
#   已解锁槽 → 设为当前选中槽，并把上方武器面板切到槽里那把枪（可看它的数值）。
func _on_slot_clicked(i: int):
	if not Weapons.is_slot_unlocked(i):
		_show_slot_confirm(i)   # 锁定槽：先确认，不直接扣钱
		return
	_sel_slot = i
	# 点已装枪的槽位 → 把上方武器面板切到槽里那把枪（切到它所属的选项卡），
	# 这样点槽2/槽3 就能直接看到那把枪的伤害/射速/弹夹/换弹数值。
	# 空槽没有 id 可切，保持当前预览不变。
	var sid: String = Weapons.loadout[i]
	if sid != "" and Weapons.DATA.has(sid):
		_weapon_cur_id = sid
		_weapon_cur_tab = String(Weapons.DATA[sid]["type"])
		_apply_weapon_tab_style()   # 让选项卡高亮跟着切过去
	_refresh_loadout_bar()
	_refresh_weapon_display()

# ---------------------------------------------------------------------------
# 装备槽解锁确认弹层：点锁定槽不直接扣钻石，先弹框让玩家看清「槽几 / 花多少 / 买断不可退」
# ---------------------------------------------------------------------------
# _show_slot_confirm(slot)：弹解锁确认框。显示槽号、解锁花费、当前钻石、买断说明。
# 钻石不够时「确定」置灰，只能取消。已开着的弹层先关掉再重开，避免叠层。
func _show_slot_confirm(slot: int):
	_hide_slot_confirm()
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var cost := Weapons.slot_unlock_cost(slot)
	var afford := GameState.diamonds >= cost

	_slot_confirm = Control.new()
	_slot_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_slot_confirm)

	# 半透明遮罩：点遮罩 = 取消（不扣钱）
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_hide_slot_confirm())
	_slot_confirm.add_child(dim)

	# 居中弹框
	var pw := 460.0
	var ph := 320.0
	var box := Panel.new()
	box.position = Vector2(vw / 2.0 - pw / 2.0, vh / 2.0 - ph / 2.0)
	box.size = Vector2(pw, ph)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.13, 0.13, 0.16, 0.99)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.95, 0.75, 0.15, 0.95)
	bs.set_corner_radius_all(14)
	box.add_theme_stylebox_override("panel", bs)
	_slot_confirm.add_child(box)

	# 标题
	var t := Label.new()
	t.text = "解锁装备槽 %d" % (slot + 1)
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color(0.98, 0.92, 0.72))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(20, 26)
	t.size = Vector2(pw - 40, 36)
	box.add_child(t)

	# 花费 / 现有钻石 两行
	var lines := [
		["需要花费", "%d 钻石" % cost, Color(0.95, 0.72, 0.30)],
		["当前钻石", "%d" % GameState.diamonds, Color(0.80, 0.85, 0.95)],
	]
	for i in range(lines.size()):
		var y := 88.0 + float(i) * 40.0
		var k := Label.new()
		k.text = String(lines[i][0])
		k.add_theme_font_size_override("font_size", 18)
		k.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
		k.position = Vector2(40, y)
		k.size = Vector2(160, 28)
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(k)
		var v := Label.new()
		v.text = String(lines[i][1])
		v.add_theme_font_size_override("font_size", 22)
		v.add_theme_color_override("font_color", lines[i][2])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.position = Vector2(pw - 200, y)
		v.size = Vector2(160, 28)
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(v)

	# 买断不可退提示
	var warn := Label.new()
	warn.text = "钻石买断，一经解锁不可退还"
	warn.add_theme_font_size_override("font_size", 15)
	warn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.position = Vector2(20, 186)
	warn.size = Vector2(pw - 40, 24)
	box.add_child(warn)

	# 确定 / 取消
	var ok := Button.new()
	ok.text = "确定解锁" if afford else "钻石不足"
	ok.add_theme_font_size_override("font_size", 20)
	ok.position = Vector2(40, ph - 84)
	ok.size = Vector2(pw - 200, 52)
	ok.disabled = not afford
	ok.pressed.connect(func(): _do_slot_unlock(slot))
	box.add_child(ok)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.position = Vector2(pw - 148, ph - 84)
	cancel.size = Vector2(108, 52)
	cancel.pressed.connect(_hide_slot_confirm)
	box.add_child(cancel)

# _do_slot_unlock(slot)：确认框点「确定解锁」→ 真正花钻石买断，成功后选中该槽并刷新，
# 失败（钻石不足/存档竞态）飘字提示 + 红框闪烁。
func _do_slot_unlock(slot: int):
	if Weapons.unlock_slot(slot):
		_hide_slot_confirm()
		_sel_slot = slot            # 解锁后顺手选中该槽，方便直接装枪
		_refresh_loadout_bar()
		_refresh_weapon_display()
		_refresh()                  # 同步顶部钻石 HUD
		_toast("已解锁装备槽 %d" % (slot + 1))
	else:
		_hide_slot_confirm()
		_toast("钻石不足，无法解锁装备格")
		_flash_locked_slot(slot)

# _hide_slot_confirm()：销毁解锁确认弹层。
func _hide_slot_confirm():
	if _slot_confirm != null and is_instance_valid(_slot_confirm):
		_slot_confirm.queue_free()
	_slot_confirm = null

# _flash_locked_slot(i)：钻石不足解锁时，把该槽边框设为红色，0.35 秒后由 _refresh_loadout_bar 复原。
func _flash_locked_slot(i: int):
	var sb := _slot_btns[i].get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_color = Color(0.95, 0.35, 0.30, 1.0)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(_refresh_loadout_bar)

# _toast(text)：居中偏下弹出一行飘字（1.2 秒后自动 queue_free），用于钻石不足等轻量反馈。
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

# 锁图标（代码画：锁梁 + 锁体 + 钥匙孔，缓存一次避免重复生成）
var _lock_tex_cache: ImageTexture = null

# _lock_icon_tex()：用 Image 逐像素画一个锁图标（锁梁圆环 + 锁体 + 钥匙孔），返回缓存贴图。
func _lock_icon_tex() -> Texture2D:
	if _lock_tex_cache != null:
		return _lock_tex_cache
	var s := 48
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := s / 2.0
	var body_w := s * 0.60
	var body_h := s * 0.42
	var bx := cx - body_w / 2.0
	var by := s * 0.48
	var col := Color(0.62, 0.64, 0.70, 0.95)
	for y in range(s):
		for x in range(s):
			var py := float(y)
			if py < by:
				var d := Vector2(x + 0.5, py + 0.5).distance_to(Vector2(cx, by))
				if py >= by - s * 0.26 and d <= s * 0.22 and d >= s * 0.22 - 3.5:
					img.set_pixel(x, y, col)
			if float(x) >= bx and float(x) <= bx + body_w and py >= by and py <= by + body_h:
				img.set_pixel(x, y, col)
	# 钥匙孔（圆点 + 竖线）
	var ky := by + body_h * 0.38
	for y in range(s):
		for x in range(s):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, ky)) <= 3.0:
				img.set_pixel(x, y, Color(0.12, 0.12, 0.16))
			elif absf(x + 0.5 - cx) <= 1.5 and y >= int(ky) and y <= int(ky) + s * 0.12:
				img.set_pixel(x, y, Color(0.12, 0.12, 0.16))
	_lock_tex_cache = ImageTexture.create_from_image(img)
	return _lock_tex_cache

# _on_weapon_overlay_input(event)：武器面板的半透明遮罩被点击（鼠标按下）时关闭武器面板。
func _on_weapon_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_hide_weapon_panel()

# _refresh()：顶栏货币 HUD 与左上角等级/经验刷新。金币/钻石直接取 GameState；
# 等级、EXP 文字、经验条进度也同步。被 stats_changed 信号驱动，每次数据变动都重算。
func _refresh():
	_cur_labels["gold"].text = "%d" % GameState.gold
	_cur_labels["diamond"].text = "%d" % GameState.diamonds
	if _level_label != null:
		_level_label.text = "Lv.%d" % GameState.level
	if _exp_label != null:
		if GameState.is_max_level():
			_exp_label.text = "EXP MAX"
		else:
			_exp_label.text = "EXP %d/%d" % [GameState.exp, GameState.exp_per_level(GameState.level)]
	if _exp_bar != null:
		_exp_bar.value = GameState.exp_progress_ratio()
	if _name_label != null:
		_name_label.text = GameState.player_id

# ============================================================
#  升级提示框（只在本界面显示；局内升级由 GameState.pending_levelups 延迟到此弹出）
# ============================================================
# _on_level_up(lv)：GameState 升级信号回调（含局内升级）。把新等级入队，顺序弹出升级提示框。
# 队列机制保证多个升级时一次只弹一个、关掉再弹下一个。
func _on_level_up(lv: int):
	# 主界面已打开时当场升级，直接入队显示
	_levelup_queue.append(lv)
	_process_levelup_queue()

# _process_levelup_queue()：从 _levelup_queue 取队首等级弹窗；若已有弹窗开着或队列空则等待。
# 弹窗关闭的回调里再调本函数，形成「关一个弹下一个」的链条。
func _process_levelup_queue():
	if _levelup_popup_open or _levelup_queue.is_empty():
		return
	_levelup_popup_open = true
	var lv: int = _levelup_queue.pop_front()
	_show_levelup_popup(lv, func():
		_levelup_popup_open = false
		_process_levelup_queue())

# _show_levelup_popup(lv, on_close)：居中弹出升级成功框。注意钻石在此处才真正发放——
# 局内升级延迟到返回主界面、随每个弹窗逐个累加（顶部钻石数随弹窗递增）。参数 lv 等级，
# on_close 为关闭后要执行的回调（用于弹下一个）。
func _show_levelup_popup(lv: int, on_close: Callable):
	# 钻石延迟到此处发放：局内不增加，返回主界面随每个升级弹窗逐个累加
	GameState.diamonds += lv
	GameState.pending_levelups.erase(lv)
	GameState.save_profile()
	GameState.stats_changed.emit()   # 刷新顶部钻石计数，随弹窗递增
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
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
			_close_levelup_popup(pop, on_close))
	pop.add_child(shade)
	var pw := 420.0
	var ph := 300.0
	var box := Panel.new()
	box.position = Vector2(vw / 2.0 - pw / 2.0, vh / 2.0 - ph / 2.0)
	box.size = Vector2(pw, ph)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.14, 0.14, 0.17, 1.0)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.4, 1.0, 0.6, 0.95)
	bs.set_corner_radius_all(16)
	box.add_theme_stylebox_override("panel", bs)
	pop.add_child(box)
	var title := Label.new()
	title.text = "升级成功！"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 36)
	title.size = Vector2(pw, 44)
	box.add_child(title)
	var info := Label.new()
	info.text = "等级提升到 Lv.%d\n获得 %d 钻石" % [lv, lv]
	info.add_theme_font_size_override("font_size", 24)
	info.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.position = Vector2(0, 110)
	info.size = Vector2(pw, 90)
	box.add_child(info)
	var ok := Button.new()
	ok.text = "确定"
	ok.add_theme_font_size_override("font_size", 22)
	ok.position = Vector2(pw / 2.0 - 70, ph - 64)
	ok.size = Vector2(140, 44)
	ok.pressed.connect(func(): _close_levelup_popup(pop, on_close))
	box.add_child(ok)

# _close_levelup_popup(pop, on_close)：销毁升级弹窗并调用 on_close 回调（继续弹队列下一个）。
func _close_levelup_popup(pop: Control, on_close: Callable):
	if is_instance_valid(pop):
		pop.queue_free()
	on_close.call()

# ============================================================
#  设置（右上角齿轮 → 主界面音量 / 游戏界面音量 / 亮度）
# ============================================================
var _gear_btn: TextureButton = null        # 右上角齿轮按钮
var _settings_gear_root: Control = null   # 圈+齿轮打包容器（打开全屏面板时整体隐藏）
var _settings_panel: Control = null        # 设置面板（遮罩根）
var _chest_panel: Control = null           # 已打开的宝箱面板引用（防重复）
var _bag_panel: Control = null             # 已打开的背包面板引用（防重复）
var _task_panel: Control = null            # 已打开的任务面板引用（防重复）
var _codex_panel: Control = null           # 已打开的图鉴面板引用（防重复）
var _endless_panel: Control = null          # 已打开的无尽模式面板引用（防重复）
var _homestead_panel: Control = null       # 已打开的家园面板引用（防重复）
var _shop_gear_root: Control = null        # 商店按钮容器（圈+图标，打开全屏面板时整体隐藏）
var _shop_panel: Control = null            # 已打开的商店面板引用（防重复）

# _build_settings_button()：构建右上角齿轮按钮（外圈灰描边圆 + 齿轮图标），整体打包进
# _settings_gear_root 并锚定右上角。点击打开设置面板。齿轮用代码画，不依赖素材。
func _build_settings_button():
	var sz: float = 40.0          # 齿轮显示尺寸（改小）
	var ring_sz: float = 52.0     # 外圈尺寸（比齿轮大一圈）
	var margin: float = 16.0
	var pad: float = (ring_sz - sz) / 2.0
	# 容器：圈+齿轮打包，整体锚定右上角；打开武器等全屏面板时整体隐藏（不再压在面板上）
	_settings_gear_root = Control.new()
	_settings_gear_root.name = "SettingsGearRoot"
	_settings_gear_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_gear_root.offset_left = -(ring_sz + margin)
	_settings_gear_root.offset_top = margin
	_settings_gear_root.offset_right = -margin
	_settings_gear_root.offset_bottom = margin + ring_sz
	_settings_gear_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_settings_gear_root)
	# 外圈：灰色描边圆（透明底），套在齿轮外面
	var ring := Panel.new()
	ring.name = "SettingsRing"
	ring.position = Vector2.ZERO
	ring.size = Vector2(ring_sz, ring_sz)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(0, 0, 0, 0)
	ring_sb.border_color = Color(0.62, 0.64, 0.68, 0.9)
	ring_sb.set_border_width_all(2)
	ring_sb.set_corner_radius_all(999)
	ring.add_theme_stylebox_override("panel", ring_sb)
	_settings_gear_root.add_child(ring)
	# 齿轮：灰色、居中于圈内，点击打开设置
	_gear_btn = TextureButton.new()
	_gear_btn.name = "SettingsGear"
	_gear_btn.texture_normal = _make_gear_texture(64, Color(0.62, 0.64, 0.68, 1.0))
	_gear_btn.ignore_texture_size = true
	_gear_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_gear_btn.position = Vector2(pad, pad)
	_gear_btn.size = Vector2(sz, sz)
	_gear_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_gear_btn.pressed.connect(_open_settings)
	AudioManager.attach_click(_gear_btn)
	_settings_gear_root.add_child(_gear_btn)

# 用代码画一个齿轮图标（项目里没有齿轮图片，避免依赖素材）。
# 参数 size 像素尺寸，col 齿轮颜色（默认灰色），8 齿，中心留孔。
func _make_gear_texture(size: int, col: Color = Color(0.62, 0.64, 0.68, 1.0)) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	var r_out := size * 0.46
	var r_in := size * 0.30
	var r_hole := size * 0.13
	var teeth := 8
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := p.distance_to(c)
			if d > r_out or d < r_hole:
				continue
			var ang := atan2(p.y - c.y, p.x - c.x)
			if ang < 0.0:
				ang += TAU
			var seg := TAU / float(teeth)
			var in_tooth: bool = fmod(ang, seg) < seg * 0.5
			var limit: float = r_out if in_tooth else r_in
			if d <= limit:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

# _build_shop_button()：构建右上角商店按钮（与设置齿轮同款外圈 + 圆角图标），整体打包进
# _shop_gear_root 并锚定右上角，位置在设置按钮正下方（y ∈ [80, 132]）。点击打开商店面板。
# 图标读 res://art/shop_icon.png；素材缺失时退化为「商店」文字按钮，保证不会出现空白按钮。
func _build_shop_button():
	var sz: float = 40.0          # 图标显示尺寸
	var ring_sz: float = 52.0     # 外圈尺寸
	var pad: float = (ring_sz - sz) / 2.0
	# 容器：圈+图标打包，整体锚定右上角，紧贴设置按钮下方；打开全屏面板时整体隐藏
	_shop_gear_root = Control.new()
	_shop_gear_root.name = "ShopGearRoot"
	_shop_gear_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_shop_gear_root.offset_left = -68.0
	_shop_gear_root.offset_top = 80.0
	_shop_gear_root.offset_right = -16.0
	_shop_gear_root.offset_bottom = 132.0
	_shop_gear_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shop_gear_root)
	# 外圈：灰色描边圆（透明底）
	var ring := Panel.new()
	ring.name = "ShopRing"
	ring.position = Vector2.ZERO
	ring.size = Vector2(ring_sz, ring_sz)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(0, 0, 0, 0)
	ring_sb.border_color = Color(0.62, 0.64, 0.68, 0.9)
	ring_sb.set_border_width_all(2)
	ring_sb.set_corner_radius_all(999)
	ring.add_theme_stylebox_override("panel", ring_sb)
	_shop_gear_root.add_child(ring)
	# 图标：优先用 art/shop_icon.png；缺素材时退化为文字按钮
	var icon_tex: Texture2D = null
	if ResourceLoader.exists("res://art/shop_icon.png"):
		icon_tex = load("res://art/shop_icon.png") as Texture2D
	if icon_tex != null:
		var btn := TextureButton.new()
		btn.name = "ShopIcon"
		btn.texture_normal = icon_tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.position = Vector2(pad, pad)
		btn.size = Vector2(sz, sz)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_open_shop)
		AudioManager.attach_click(btn)
		_shop_gear_root.add_child(btn)
	else:
		var fb := Button.new()
		fb.name = "ShopText"
		fb.text = "商店"
		fb.add_theme_font_size_override("font_size", 14)
		fb.position = Vector2.ZERO
		fb.size = Vector2(ring_sz, ring_sz)
		_apply_side_style(fb)
		fb.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		fb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		fb.pressed.connect(_open_shop)
		AudioManager.attach_click(fb)
		_shop_gear_root.add_child(fb)

# _build_settings_panel()：构建设置面板（半透明遮罩 + 居中面板），含标题、关闭按钮、
# 三行滑块（主界面音量/游戏界面音量/亮度），以及「设置自动保存」提示。初始隐藏。
func _build_settings_panel():
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y

	# 半透明遮罩（点击关闭）
	var overlay := ColorRect.new()
	overlay.name = "SettingsOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(_on_settings_overlay_input)
	add_child(overlay)

	var pw: float = 460.0
	var ph: float = 330.0
	var panel := Panel.new()
	panel.position = Vector2((vw - pw) / 2.0, (vh - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.14, 0.97)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.4, 0.4, 0.4, 0.8)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 28)
	title.position = Vector2(24, 16)
	panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	close_btn.flat = true
	close_btn.position = Vector2(pw - 44, 8)
	close_btn.size = Vector2(36, 36)
	close_btn.pressed.connect(_close_settings)
	panel.add_child(close_btn)

	# 三行滑块：主界面音量 / 游戏界面音量 / 亮度
	_build_slider_row(panel, 70.0, "主界面音量", GameState.ui_volume, _on_ui_volume_changed)
	_build_slider_row(panel, 140.0, "游戏界面音量", GameState.game_volume, _on_game_volume_changed)
	_build_slider_row(panel, 210.0, "亮度", GameState.brightness, _on_brightness_changed)

	var hint := Label.new()
	hint.text = "设置会自动保存"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	hint.position = Vector2(24, ph - 58)
	panel.add_child(hint)

	# 主界面氛围音署名（neolein 授权要求：免费使用但必须署名，仅放商店简介不算合格）
	var amb_credit := Label.new()
	amb_credit.text = "主界面氛围音：Horror 4 Alien by neolein · freesound.org/s/455468"
	amb_credit.add_theme_font_size_override("font_size", 12)
	amb_credit.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.9))
	amb_credit.position = Vector2(24, ph - 34)
	panel.add_child(amb_credit)

	overlay.hide()
	_settings_panel = overlay

# _build_slider_row(parent, y, title_text, value, callback)：构造一行滑块（标题 + HSlider + 百分比）。
# 参数 y 行高偏移，title_text 标签文字，value 初始值(0~100)，callback 值变化回调。
func _build_slider_row(parent: Control, y: float, title_text: String, value: float, callback: Callable):
	var lbl := Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	lbl.position = Vector2(24, y)
	lbl.size = Vector2(160, 26)
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value
	slider.position = Vector2(24, y + 30)
	slider.size = Vector2(parent.size.x - 110.0, 22)
	slider.value_changed.connect(callback)
	parent.add_child(slider)

	var pct := Label.new()
	pct.text = "%d%%" % int(value)
	pct.add_theme_font_size_override("font_size", 16)
	pct.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	pct.position = Vector2(parent.size.x - 78.0, y)
	pct.size = Vector2(60, 26)
	parent.add_child(pct)
	slider.value_changed.connect(func(v: float): pct.text = "%d%%" % int(v))

# _on_ui_volume_changed(value)：主界面音量滑块回调。立即应用并保存设置。
func _on_ui_volume_changed(value: float):
	GameState.ui_volume = value
	GameState.apply_ui_volume()
	GameState.save_settings()

# _on_game_volume_changed(value)：游戏内音量滑块回调。只保存，进入游戏场景时由 Main 应用，
# 避免污染当前主界面已生效的音量。
func _on_game_volume_changed(value: float):
	# 只保存；进入游戏场景时由 Main 应用，避免污染当前主界面音量
	GameState.game_volume = value
	GameState.save_settings()

# _on_brightness_changed(value)：亮度滑块回调。实时套用并保存。
func _on_brightness_changed(value: float):
	GameState.set_brightness(value)
	GameState.save_settings()

# _open_settings()：显示设置面板（遮罩 show）。
func _open_settings():
	_settings_panel.show()

# _close_settings()：隐藏设置面板。
func _close_settings():
	_settings_panel.hide()

# _on_settings_overlay_input(event)：设置遮罩被鼠标按下时关闭设置面板。
func _on_settings_overlay_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_close_settings()

# _open_chest()：打开宝箱界面。已打开则忽略（防重复叠加），否则实例化 chest_panel 并隐藏齿轮/侧边。
func _open_chest():
	if _chest_panel != null and is_instance_valid(_chest_panel):
		return
	_chest_panel = preload("res://chest_panel.gd").new()
	add_child(_chest_panel)
	_hide_gear_while(_chest_panel)

# _open_bag()：打开背包界面。已打开则忽略（防重复叠加），否则实例化 bag_panel 并隐藏齿轮/侧边。
func _open_bag():
	if _bag_panel != null and is_instance_valid(_bag_panel):
		return
	_bag_panel = preload("res://bag_panel.gd").new()
	add_child(_bag_panel)
	_hide_gear_while(_bag_panel)

# _open_shop()：打开商店界面。已打开则忽略（防重复叠加），否则实例化 shop_panel 并隐藏齿轮/侧边。
func _open_shop():
	if _shop_panel != null and is_instance_valid(_shop_panel):
		return
	_shop_panel = preload("res://shop_panel.gd").new()
	add_child(_shop_panel)
	_hide_gear_while(_shop_panel)

# 右侧中部的小「家园」「任务」框（锚定右边缘垂直居中，窗口缩放跟随）。
# 家园在上、任务在下，两个框等大（80×80）。点击分别打开对应面板。
func _build_task_button():
	var w: float = 80.0
	var h: float = 80.0
	var margin: float = 16.0
	var gap: float = 12.0

	# ---- 家园框（上方）----
	var hb := Button.new()
	hb.name = "HomesteadButton"
	hb.text = "家园"
	hb.add_theme_font_size_override("font_size", 18)
	hb.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	hb.offset_left = -(w + margin)
	hb.offset_right = -margin
	hb.offset_top = -h / 2.0 - h - gap
	hb.offset_bottom = -h / 2.0 - gap
	_apply_side_style(hb)
	hb.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	hb.pressed.connect(_open_homestead)
	AudioManager.attach_click(hb)
	add_child(hb)
	_homestead_side_btn = hb

	# ---- 任务框（下方）----
	var btn := Button.new()
	btn.name = "TaskButton"
	btn.text = "任务"
	btn.add_theme_font_size_override("font_size", 18)
	btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	btn.offset_left = -(w + margin)
	btn.offset_right = -margin
	btn.offset_top = -h / 2.0
	btn.offset_bottom = h / 2.0
	_apply_side_style(btn)
	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.pressed.connect(_open_tasks)
	AudioManager.attach_click(btn)
	add_child(btn)
	_task_side_btn = btn

	# 任务按钮右上角红点：有成就可领时显示（实心圆、不吃鼠标，不挡按钮点击）
	var badge := Panel.new()
	badge.name = "TaskBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(w - 16.0, 2.0)
	badge.size = Vector2(14.0, 14.0)
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(0.95, 0.25, 0.22, 1.0)
	badge_sb.set_corner_radius_all(999)
	badge.add_theme_stylebox_override("panel", badge_sb)
	badge.visible = false
	btn.add_child(badge)
	_task_badge = badge
	_refresh_task_badge()

# _refresh_task_badge()：遍历所有成就，只要任意一条当前档位已达成（可领取）就显示任务按钮红点，
# 否则隐藏。面板未构建（_task_badge 为空）时直接返回。
func _refresh_task_badge():
	if _task_badge == null or not is_instance_valid(_task_badge):
		return
	var any_ready := false
	for a in GameState.ACHIEVEMENTS:
		if GameState.ach_reached(a["id"]):
			any_ready = true
			break
	_task_badge.visible = any_ready

# _apply_side_style(btn)：给右侧小框套上统一的灰黑圆角样式（normal/hover/pressed）。
func _apply_side_style(btn: Button):
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	normal.border_color = Color(0.45, 0.45, 0.45, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.25, 0.28, 0.95)
	hover.border_color = Color(0.6, 0.6, 0.6, 0.9)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)

# _open_homestead()：打开家园面板。已打开则忽略（防重复叠加），否则实例化并隐藏齿轮/侧边。
func _open_homestead():
	if _homestead_panel != null and is_instance_valid(_homestead_panel):
		return
	_homestead_panel = preload("res://homestead_panel.gd").new()
	add_child(_homestead_panel)
	_hide_gear_while(_homestead_panel)

# _open_tasks()：打开任务面板。已打开则忽略（防重复叠加），否则实例化并隐藏齿轮/侧边。
func _open_tasks():
	if _task_panel != null and is_instance_valid(_task_panel):
		return
	_task_panel = preload("res://task_panel.gd").new()
	add_child(_task_panel)
	_hide_gear_while(_task_panel)

# _open_codex()：打开丧尸图鉴面板。已打开则忽略（防重复叠加），否则实例化并隐藏齿轮/侧边。
func _open_codex():
	if _codex_panel != null and is_instance_valid(_codex_panel):
		return
	_codex_panel = preload("res://codex_panel.gd").new()
	add_child(_codex_panel)
	_hide_gear_while(_codex_panel)

# _open_endless()：打开无尽模式面板。已打开则忽略，否则实例化并隐藏齿轮/侧边。
func _open_endless():
	if _endless_panel != null and is_instance_valid(_endless_panel):
		return
	_endless_panel = preload("res://endless_panel.gd").new()
	add_child(_endless_panel)
	_hide_gear_while(_endless_panel)
