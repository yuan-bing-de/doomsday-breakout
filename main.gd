extends Node2D

# ============================================================================
# Main.gd —— 游戏主场景脚本（控制关卡、丧尸生成）
# ============================================================================
# 挂在 Main 场景根节点上。
# 背景图(Bg)直接放在 Main.tscn 里。独立路面 GroundSprite 已删除，
# 地面视觉完全由 background.png 自带的地面提供，不再叠加第二层路面。
#
# 这个脚本只负责：① 记录玩家/血条节点；② 按定时器生成丧尸；③ 定义丧尸属性。
#
# 你想改的地方：
#   - 丧尸种类/血量/速度 → 下面的 ZTYPES 字典
#   - 丧尸生成频率     → _on_spawn_timeout()
# ============================================================================

# ---- 场景里已有的节点 ----
@onready var player: Node2D = $Player
@onready var spawn_timer: Timer = $SpawnTimer
@onready var health_bar_fg: ColorRect = $UI/HealthBarFG
@onready var health_label: Label = $UI/HealthLabel
@onready var _bg_sprite: Sprite2D = $ParallaxBackground/CityLayer/Bg

# 金币/钻石 HUD 的标签引用（由 GameState.build_currency_hud 返回）
var _currency_labels: Dictionary = {}

# 武器商店 UI
var _shop_panel: Control = null
var _shop_buttons: Dictionary = {}
var _medkit_btn: Button = null
var _weapon_hud_label: Label = null   # 当前手持武器指示（按 Q 切换）
var _skill_hud_label: Label = null    # 手雷 / 支援导弹 冷却指示（G / H）
var _ammo_hud_label: Label = null     # 弹夹 / 换弹 指示
var _medkit_hud_label: Label = null   # 医疗包 数量 / 冷却 指示
# 医疗包单价（局内 B 商店金币购买，自动进背包）
const MEDKIT_PRICE := 200

# ---- 游戏菜单 ----
var _menu_btn: Button = null
var _popup_menu: PopupMenu = null
var _settings_panel: Control = null
var _opening_settings: bool = false   # 防止设置面板打开时 popup_hide 把游戏恢复

# ---- 关卡通关 / 结算 ----
var _kills := 0                  # 当前关已击杀数
var _goal := 0                   # 当前关通关需要的击杀数
var _chests_earned_this_level: Array = []   # 本关击杀获得的宝箱 [{type, slot}]
var _ended := false              # 胜利/失败后防止重复触发

# ---- 通关结算倒计时（击杀达标后 5 秒才真正结束，让玩家捡地上的东西）----
const VICTORY_COUNTDOWN_SEC := 5.0        # 结算倒计时秒数
var _victory_counting_down := false       # 是否正在倒计时中
var _victory_done := false                # 倒计时是否已真正结算过（防重复）
var _countdown_ui: Control = null         # 倒计时 UI 容器
var _countdown_label: Label = null        # 倒计时秒数 Label

# BOSS 死亡时掉落的精魂数量（掉在地上，玩家走过去捡）
const BOSS_SOUL_DROP := 5

# ---- 无尽模式刷怪分批（避免一波 20+ 只同帧出现糊成一堵墙）----
const ENDLESS_BATCH_MAX := 4       # 每批最多几只
const ENDLESS_BATCH_GAP := 0.7     # 批间隔（秒）

# ----------------------------------------------------------------------------
# 无尽模式（Endless.gd 数据驱动）：无限存活，死了才算结束
#   _endless        : 是否处于无尽模式（false = 走原主线逻辑）
#   _endless_wave   : 当前波次（从 1 开始）
#   _endless_kills  : 本局无尽击杀数（结算用）
#   _endless_diamond: 本局无尽获得的钻石（波次奖励结算用）
#   _endless_boss_wave : 已出过 BOSS 的波次标记，避免同波重复出
# ----------------------------------------------------------------------------
var _endless := false
var _endless_wave := 1
var _endless_kills := 0
var _endless_diamond := 0
var _endless_reward_wave := 0   # 已经结算过奖励的波次（防止重复发奖）
var _endless_boss_wave := 0     # 已出过 BOSS 的波次（0 = 本波还没出）
var _endless_last_clear_ms := 0  # 上次清场时间戳（波次推进 0.8 秒冷却用）
var _endless_spawning := false  # 本波是否正在分批刷出（刷完后才允许推进下一波）
var _victory_panel: Control = null
var _victory_chest_area: Control = null      # 胜利面板里的宝箱展示区
var _victory_chest_cards: Array = []         # 胜利面板宝箱卡片引用
var _kills_label: Label = null

# ---- BOSS 战 ----
# 出场时机：BOSS 关不会开局就放 BOSS，而是先让玩家打完普通丧尸（_kills >= _goal），
# 达标后才由 _maybe_spawn_boss() 破土出场；BOSS 未出场时 _boss_dead 仍为 false，
# 所以「击杀达标」不会误判通关，必须再打死 BOSS 才算过（见 _check_victory）。
var _boss: Node2D = null              # 当前关卡的 BOSS 实例（未出场/已死为 null）
var _boss_dead := false               # BOSS 是否已击杀（BOSS 关的通关前提）
var _boss_spawned := false            # BOSS 是否已出场（防重复出场）
var _boss_pending_type := ""          # 待出场的 BOSS 类型键，空串 = 本关无 BOSS
var _boss_pending_hp_mul := 1.0       # 待出场 BOSS 的血量倍率
var _boss_bar_bg: ColorRect = null    # 顶部大血条底
var _boss_bar_fg: ColorRect = null    # 顶部大血条前景
var _boss_name_label: Label = null

# 预加载丧尸场景
const ZOMBIE_SCENE = preload("res://Zombie.tscn")

# ----------------------------------------------------------------------------
# 丧尸配置来自 zombie_catalog.gd，关卡与界面共用
# ----------------------------------------------------------------------------
const ZOMBIE_CATALOG = preload("res://zombie_catalog.gd")
const ZTYPES = ZOMBIE_CATALOG.DEFINITIONS

# 预加载 BOSS 场景
const BOSS_SCENE = preload("res://Boss.tscn")

# ----------------------------------------------------------------------------
# BOSS 配置（贴图来自 art/boss_prototypes_20260926/）
# 贴图缩放由 boss.gd 按碰撞体高度自适应，换任意尺寸源图都自动底对齐
#   brute  暴食者：血最厚、慢，技能「冲锋」
#   hulk   绿巨人：高伤、中等，技能「震地」范围冲击波
#   reaper 收割者：远程 + 召唤小怪，最终 BOSS
# 实际血量 = max_health × Stages.boss_hp_mul(关卡)，随关卡递增
# 定义已抽到 boss_catalog.gd（与 zombie_catalog.gd 对称，战斗与图鉴共用同一份数据）
# ----------------------------------------------------------------------------
const BOSS_CATALOG = preload("res://boss_catalog.gd")
const BOSSTYPES = BOSS_CATALOG.DEFINITIONS

# 屏幕高度（仅用于参考：路面顶边 = 648 - 130 = 518）
const VIEWPORT_H := 648.0

# ----------------------------------------------------------------------------
# _ready()：游戏启动时执行一次
# ----------------------------------------------------------------------------
func _ready():
	# 0) 应用「游戏界面音量」（主界面音量由 Hub 应用，两者独立）
	GameState.apply_game_volume()
	# 0.1) 命令行调试参数：--stage=N 可直接进指定关卡（测试地图用）
	for ua in OS.get_cmdline_user_args():
		if ua.begins_with("--stage="):
			GameState.selected_stage = clampi(int(ua.get_slice("=", 1)), 1, GameState.STAGE_COUNT)
	# 进关预热本关丧尸的贴图与骨骼网格，刷怪时不再现场构建/解码。
	preload("res://zombie_motion.gd").warmup(GameState.selected_stage)
	# 0.2) 应用本关地图（背景图 / 氛围色 / 刷怪节奏，配置在 Stages.gd）
	_apply_stage()
	# 1) 把节点加入分组，方便其他脚本查找
	player.add_to_group("player")
	player.died.connect(_on_player_died)
	$UI/HealthBarFG.add_to_group("health_bar_fg")
	$UI/HealthLabel.add_to_group("health_label")
	$UI/GameOverPanel.add_to_group("game_over_panel")

	# 2) 连接丧尸生成定时器
	spawn_timer.timeout.connect(_on_spawn_timeout)

	# 2.5) 构建金币/钻石/腐肉 HUD（正上方，与主界面一致）
	_currency_labels = GameState.build_currency_hud($UI, get_viewport().get_visible_rect().size.x / 2.0 - 145, 16)
	GameState.stats_changed.connect(_refresh_currency)

	# 2.6) 构建武器商店（按 B 打开/关闭）
	_build_weapon_shop()
	GameState.stats_changed.connect(_refresh_shop)

	# 2.6.1) 当前手持武器指示（按 Q 在已装备的两把之间切换）
	_build_weapon_hud()
	Weapons.weapon_changed.connect(_refresh_weapon_hud)

	# 2.6.3) 弹夹 / 换弹 / 医疗包 HUD
	_build_ammo_hud()

	# 2.6.2) 技能 HUD（手雷 G / 支援导弹 H 的冷却）
	_build_skill_hud()

	# 2.7) 构建右上角游戏菜单（暂停时 UI 仍可响应）
	$UI.process_mode = Node.PROCESS_MODE_ALWAYS
	_build_game_menu()

	# 3) 开局放一只男丧尸（主线关逻辑；无尽模式的初始波由 _start_endless 统一刷）
	if not GameState.endless_mode:
		var first_mutant: String = ZOMBIE_CATALOG.new_at(GameState.selected_stage)
		spawn_zombie(first_mutant if not first_mutant.is_empty() else "male")
		if not first_mutant.is_empty():
			var notice := Label.new()
			notice.text = "新变异种 · %s\n%s" % [ZTYPES[first_mutant].name,ZTYPES[first_mutant].tip]
			notice.position = Vector2(260,178)
			notice.size = Vector2(720,66)
			notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			notice.add_theme_font_size_override("font_size",18)
			notice.add_theme_color_override("font_color",Color(1,.85,.5))
			notice.add_theme_color_override("font_outline_color",Color.BLACK)
			notice.add_theme_constant_override("outline_size",5)
			$UI.add_child(notice)
			var reveal := create_tween()
			reveal.tween_interval(8)
			reveal.tween_property(notice,"modulate:a",0.0,1.0)
			reveal.tween_callback(notice.queue_free)

	# 3.0) BOSS 关：这里只登记不生成，等玩家把本关普通丧尸清到目标数后，
	#     再由 _maybe_spawn_boss() 破土出场（BOSS 自带约 1 秒爬出动画，当作出场缓冲）
	if Stages.has_boss(GameState.selected_stage):
		_boss_pending_type = Stages.boss_type(GameState.selected_stage)
		_boss_pending_hp_mul = Stages.boss_hp_mul(GameState.selected_stage)

	# 3.1) 关卡号 + 地图名标签（读取关卡选择界面写入的 selected_stage）
	var stage_label := Label.new()
	stage_label.text = "关卡 %d · %s" % [GameState.selected_stage, Stages.stage_name(GameState.selected_stage)]
	stage_label.position = Vector2(20, 44)
	stage_label.add_theme_font_size_override("font_size", 18)
	stage_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	$UI.add_child(stage_label)

	# 3.2) 通关目标 + 击杀进度 HUD（顶部居中）
	_goal = _stage_goal(GameState.selected_stage)
	var kl := Label.new()
	kl.text = "击杀 %d/%d" % [_kills, _goal]
	kl.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 60, 44)
	kl.add_theme_font_size_override("font_size", 18)
	kl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	$UI.add_child(kl)
	_kills_label = kl

	# 3.3) 无尽模式：若 GameState 标记为无尽局，替换波次/刷怪/结算逻辑并显示「无尽 · 第 N 波」
	if GameState.endless_mode:
		_start_endless()

	# 3.3) 胜利结算面板 + 战败面板加「返回关卡选择」按钮
	_build_victory_panel()
	_add_gameover_levelselect_btn()

	# 3.4) 进局启动 BGM（循环播放；返回菜单/主界面时由对应分支 stop_bgm）
	AudioManager.start_bgm()

# ----------------------------------------------------------------------------
# _exit_tree()：离开本场景时兜底停止 BGM
# 场景切换/重载会先触发本函数。放在这里可覆盖所有离局路径（返回主界面、
# 返回关卡选择、战败按 R 重开、胜利进下一关、退出游戏），避免漏掉某条分支
# 导致 BGM 一直响。start_bgm 本身是幂等的，重新进关时仍能正常播放。
# ----------------------------------------------------------------------------
func _exit_tree():
	AudioManager.stop_bgm()
	AudioManager.stop_ambience()   # 双保险：任何离局路径下都不会让主界面氛围音残留到局内

# ----------------------------------------------------------------------------
# _apply_stage()：按当前关卡应用地图配置（Stages.gd 数据驱动）
# 背景图等比缩放到铺满视口；氛围色同时乘在背景与世界节点上；刷怪间隔按关配置。
# ----------------------------------------------------------------------------
func _apply_stage():
	var s := GameState.selected_stage
	# 背景图：文件缺失时保留场景里默认的 background_city
	var tex := Stages.bg_texture(s)
	if tex != null:
		_bg_sprite.texture = tex
		var vs := get_viewport().get_visible_rect().size
		var ts := tex.get_size()
		var k: float = maxf(vs.x / ts.x, vs.y / ts.y)
		_bg_sprite.scale = Vector2(k, k)
	# 氛围色：CanvasModulate 只影响游戏世界（玩家/丧尸），背景用 modulate 单独上色
	var amb := Stages.ambient(s)
	_bg_sprite.modulate = amb
	var cm := CanvasModulate.new()
	cm.color = amb
	add_child(cm)
	# 刷怪节奏
	spawn_timer.wait_time = Stages.spawn_interval(s)

# ----------------------------------------------------------------------------
# _on_spawn_timeout()：定时器触发 → 按本关配比随机生成一只丧尸
# ----------------------------------------------------------------------------
func _on_spawn_timeout():
	if _ended or player.dead:
		spawn_timer.stop()
		return
	if _endless:
		# 无尽：按当前波次刷怪，血量按波次倍率加厚；变异种随波次逐步开放
		_spawn_endless_wave()
		return
	spawn_zombie(Stages.pick_zombie_type(GameState.selected_stage))

# _spawn_endless_wave()：无尽模式的一次刷怪。
#   数量：Endless.total_per_wave(wave) = 基础数量（随波次递增）+ 奖励波额外只数
#   种类：从已解锁的丧尸里随机（前期只有 male/female/fat，随波次开放变异种）
#   血量：Endless.hp_mul(wave) 线性加厚
#   ★分批涌出（ENDLESS_BATCH_MAX 只/批、间隔 ENDLESS_BATCH_GAP 秒）：
#     早期 3~8 只一次刷完没问题，但后期一波 20+ 只如果同帧全出现在屏幕上会挤成一堵墙
#     （第 20 波实测糊成一片）。分批让它们像"一拨接一拨涌过来"，既有尸潮压迫感又看得清。
func _spawn_endless_wave():
	var n := Endless.total_per_wave(_endless_wave)
	if n <= ENDLESS_BATCH_MAX:
		_endless_spawning = false
		for i in range(n):
			_spawn_endless_zombie(_pick_endless_zombie_type(), i, n)
		return
	# 分批：每批 ENDLESS_BATCH_MAX 只，批间隔 ENDLESS_BATCH_GAP 秒。
	# ★必须 await get_tree().create_timer() 真正等待；create_tween() 不会阻塞循环，
	#   那样写会在同一帧内把所有批次全刷完，等于没分批。
	_endless_spawning = true          # 刷怪期间禁止推进下一波（否则批次间隙会被误判成清场）
	var idx := 0
	while idx < n:
		var cnt: int = mini(ENDLESS_BATCH_MAX, n - idx)
		for i in range(cnt):
			_spawn_endless_zombie(_pick_endless_zombie_type(), idx + i, n)
		idx += cnt
		if idx < n and not _ended and not player.dead:
			await get_tree().create_timer(ENDLESS_BATCH_GAP).timeout
		else:
			break                # 玩家死亡/本局结束：停止后续批次
	_endless_spawning = false         # 本波全部刷完，恢复「可推进下一波」
	# 刷完后场上如果一只不剩（例如玩家在批次间隙全清了），立刻走一次清场判定，避免卡住不涨波
	if not _ended and not player.dead:
		_maybe_endless_next_wave()

# _pick_endless_zombie_type()：按当前波次随机一只丧尸。变异种需满足解锁条件。
func _pick_endless_zombie_type() -> String:
	var pool: Array[String] = ["male", "female", "fat"]
	for id in ZOMBIE_CATALOG.MUTANTS:
		if int(ZTYPES[id]["unlock"]) <= _endless_wave:
			pool.append(String(id))
	return pool[randi() % pool.size()]

# _spawn_endless_zombie(type, offset_idx, total)：生成一只无尽丧尸。
#   血量：按波次倍率加厚（线性缓增，不指数爆炸）
#   站位：分散到远处的「Z 字形深空区」——不挤成一堵墙。
#     敌人从右往左走，越靠右越晚接敌；这里把同一波铺在 1050~3500px 的宽区间、
#     每排错开 X 和 Y（深浅纵深），所以是"散兵线"而不是"丧尸墙"。
func _spawn_endless_zombie(type: String, offset_idx: int, total: int):
	var z := ZOMBIE_SCENE.instantiate()
	ZOMBIE_CATALOG.configure(z, type)
	# 入 normal_zombie 组：无尽模式用它判断「场上普通丧尸是否清空」→ 推进下一波
	z.add_to_group("normal_zombie")
	# 血量 = 基础 × 波次倍率
	var mul := Endless.hp_mul(_endless_wave)
	z.max_health = int(round(float(z.max_health) * mul))
	# 站位：横向拉大间距（320px），并用 Y 做纵深错位（±60px 随机），避免排成直线墙
	var spacing := 320.0
	var x := player.global_position.x + 1150.0 + float(offset_idx) * spacing
	var y := 388.0 + randf_range(-60.0, 60.0)
	z.global_position = Vector2(x, y)
	add_child(z)
	z.died.connect(_on_zombie_died)

func _on_player_died():
	_ended = true
	spawn_timer.stop()
	# 倒计时中死亡：立刻撤掉倒计时 UI 并取消待结算，避免残留文字/后续重复结算
	if _victory_counting_down:
		_victory_counting_down = false
		_victory_done = true
		if _countdown_ui != null and is_instance_valid(_countdown_ui):
			_countdown_ui.queue_free()
			_countdown_ui = null
		_countdown_label = null
	# 无尽模式：死亡即本局结束，先记录最高波次/击杀/钻石
	if _endless:
		_endless_game_over()
	for enemy in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("enemy_hazards"):
		if enemy.has_method("stop_moving"):
			enemy.stop_moving()

# ----------------------------------------------------------------------------
# spawn_zombie()：生成一只指定类型的丧尸
# 出生点：X=1180（屏幕右侧外），Y=418（丧尸 120px 高居中 → 脚底在 478=落脚线）
# ----------------------------------------------------------------------------
func spawn_zombie(type := "male"):
	if _ended or player.dead:
		return
	# 所有入口（包含 Boss 召唤）都受关卡解锁约束。
	if not ZOMBIE_CATALOG.unlocked(type,GameState.selected_stage):
		type = "male"
	var z := ZOMBIE_SCENE.instantiate()
	ZOMBIE_CATALOG.configure(z,type)

	# 丧尸中心 Y = 落脚线(478) - 半高(90) = 388 → 脚底踩在路面上
	# 出生点改为玩家前方 1100px，避免相机跟随后刷在身后
	z.global_position = Vector2(player.global_position.x + 1100.0, 388.0)
	add_child(z)
	z.died.connect(_on_zombie_died)   # 丧尸死亡 → 给经验+掉金币

# ----------------------------------------------------------------------------
# BOSS：生成 / 死亡 / 顶部血条 / 召唤
# ----------------------------------------------------------------------------
# 达标后放行 BOSS：本关普通丧尸清到目标数才出场，且只出场一次。
# 非 BOSS 关（_boss_pending_type 为空）直接跳过；已结束/已出场也跳过。
func _maybe_spawn_boss():
	if _ended or _boss_spawned:
		return
	if _boss_pending_type.is_empty():
		return
	if _kills < _goal:
		return
	_boss_spawned = true
	spawn_boss(_boss_pending_type, _boss_pending_hp_mul)
	_show_boss_warning()


# BOSS 出场警告：屏幕上方飘一行「XXX 来袭」，停留 1.2 秒后淡出移除
func _show_boss_warning():
	var cfg: Dictionary = BOSSTYPES.get(_boss_pending_type, {})
	var lb := Label.new()
	lb.text = "警告：%s 来袭" % String(cfg.get("name", "BOSS"))
	lb.add_theme_font_size_override("font_size", 38)
	lb.add_theme_color_override("font_color", Color(1.0, 0.28, 0.22, 1.0))
	lb.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 190.0, 150.0)
	lb.z_index = 20
	$UI.add_child(lb)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(lb, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lb.queue_free)


# 生成 BOSS 实例并接入信号（死亡/血量变化/召唤），创建顶部血条。
# 由 _maybe_spawn_boss 在击杀达标后调用，不再于关卡开局直接生成。
#   type: BOSS 类型键（brute/hulk/reaper）；hp_mul: 本关血量倍率（来自 Stages.boss_hp_mul）
func spawn_boss(type: String, hp_mul: float):
	var cfg: Dictionary = BOSSTYPES.get(type, BOSSTYPES["brute"])
	var b := BOSS_SCENE.instantiate()
	b.texture_path = String(cfg["texture"])
	b.max_health = int(round(float(cfg["max_health"]) * hp_mul))
	b.speed = float(cfg["speed"])
	b.attack_type = String(cfg["attack_type"])
	b.melee_range = float(cfg["melee_range"])
	b.ranged_range = float(cfg["ranged_range"])
	b.attack_interval = float(cfg["attack_interval"])
	b.contact_damage = int(cfg["contact_damage"])
	b.skill_type = String(cfg["skill_type"])
	b.skill_interval = float(cfg["skill_interval"])
	b.skill_damage = int(cfg["skill_damage"])
	b.skill2_type = String(cfg.get("skill2_type", ""))
	b.skill2_interval = float(cfg.get("skill2_interval", 12.0))
	b.skill2_damage = int(cfg.get("skill2_damage", 0))
	b.skill2_range = float(cfg.get("skill2_range", 0.0))
	b.motion_cfg = cfg.get("motion", {})
	b.display_name = String(cfg["name"])
	# BOSS 半高 170 → 中心 Y = 478 - 170 = 308，脚底踩在路面上
	b.global_position = Vector2(player.global_position.x + 1250.0, 308.0)
	add_child(b)
	b.died.connect(_on_boss_died)
	b.health_changed.connect(_on_boss_health_changed)
	b.summon_requested.connect(_on_boss_summon)
	_boss = b
	_boss_dead = false
	_build_boss_bar(String(cfg["name"]))

# BOSS 死亡回调（pos 为死亡位置）：标记已死、隐藏血条、给 200 经验+500 金币、
# 掉 5 个精魂在地上让玩家去捡，并判定通关。
# ★通关后有5 秒结算倒计时（见 _start_victory_countdown），所以地上的东西来得及捡。
func _on_boss_died(pos: Vector2):
	if _ended or player.dead or _boss_dead:
		return
	_boss_dead = true
	_boss = null
	_hide_boss_bar()
	# BOSS 计入击杀进度
	_kills += 1
	GameState.record_kill()
	# 无尽模式的 BOSS 波（每 10 波）也会走到这里：标签要显示波次而不是「击杀 X/0」
	if _endless:
		_endless_kills += 1
		_refresh_endless_hud()
	else:
		_refresh_kills_label()
	# 击杀 BOSS 的额外奖励（远高于普通丧尸的 10 经验 + 掉币）
	GameState.add_exp(200)
	GameState.add_gold(500)
	# 精魂：BOSS 专属掉落，**掉在地上让玩家走过去捡**（与金币/腐肉一致）。
	# 现在通关有 5 秒倒计时，来得及捡完。
	for _i in range(BOSS_SOUL_DROP):
		_spawn_drop_item(pos, "soul")
	_check_victory()

# _notify_soul_gain(n)：BOSS 掉落精魂的飘字提示。n > 0 显示获得数量，n == 0 提示背包已满。
# 挂在 $UI 下（z_index 抬高，避免被随后弹出的胜利面板盖住）。
func _notify_soul_gain(n: int):
	var vw := get_viewport().get_visible_rect().size.x
	var lbl := Label.new()
	lbl.text = "获得精魂 ×%d" % n if n > 0 else "背包已满，精魂未获得"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(400, 40)
	lbl.position = Vector2(vw / 2.0 - 200.0, 150.0)
	lbl.z_index = 20
	$UI.add_child(lbl)
	var tw := lbl.create_tween()
	# BOSS 一死 _check_victory() 可能立刻 get_tree().paused = true，而 Main.tscn 没有覆盖
	# $UI 的 process_mode（默认 inherit）。Tween 默认是 TWEEN_PAUSE_BOUND，显式设为 PROCESS
	# 才能保证暂停期间飘字照常淡出、不会永久残留在屏幕上。
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)

# BOSS「召唤」技能回调：按 count 刷出若干普通丧尸（类型由本关配比 Stages.pick_zombie_type 决定）
func _on_boss_summon(count: int):
	for _i in range(count):
		spawn_zombie(Stages.pick_zombie_type(GameState.selected_stage))

# BOSS 血量变化回调：按 cur/mx 比例刷新顶部血条前景宽度；并按血量百分比切换颜色（<25% 红、<50% 黄、否则暗红）
func _on_boss_health_changed(cur: int, mx: int):
	if _boss_bar_fg == null or _boss_bar_bg == null or mx <= 0:
		return
	var ratio: float = clampf(float(cur) / float(mx), 0.0, 1.0)
	_boss_bar_fg.size.x = (_boss_bar_bg.size.x - 4.0) * ratio
	if ratio < 0.25:
		_boss_bar_fg.color = Color(0.95, 0.20, 0.20)
	elif ratio < 0.5:
		_boss_bar_fg.color = Color(0.95, 0.75, 0.20)
	else:
		_boss_bar_fg.color = Color(0.85, 0.25, 0.25)

# 构建顶部居中的 BOSS 血条（底/前景/名字），仅首次生成 BOSS 时创建一次（重复调用直接返回）
func _build_boss_bar(boss_name: String):
	if _boss_bar_bg != null:
		return
	var vw := get_viewport().get_visible_rect().size.x
	var w := 520.0
	var x := (vw - w) / 2.0
	var y := 86.0
	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color = Color(0.10, 0.05, 0.05, 0.92)
	_boss_bar_bg.position = Vector2(x, y)
	_boss_bar_bg.size = Vector2(w, 22)
	$UI.add_child(_boss_bar_bg)
	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color = Color(0.85, 0.25, 0.25)
	_boss_bar_fg.position = Vector2(x + 2, y + 2)
	_boss_bar_fg.size = Vector2(w - 4, 18)
	$UI.add_child(_boss_bar_fg)
	_boss_name_label = Label.new()
	_boss_name_label.text = "BOSS · %s" % boss_name
	_boss_name_label.position = Vector2(x, y - 24)
	_boss_name_label.size = Vector2(w, 22)
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 17)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	$UI.add_child(_boss_name_label)

# 移除 BOSS 血条相关节点并置空引用（queue_free 延迟到帧末释放）
func _hide_boss_bar():
	if _boss_bar_bg != null:
		_boss_bar_bg.queue_free()
		_boss_bar_bg = null
	if _boss_bar_fg != null:
		_boss_bar_fg.queue_free()
		_boss_bar_fg = null
	if _boss_name_label != null:
		_boss_name_label.queue_free()
		_boss_name_label = null

# 通关判定（BOSS 关流程：先清普通丧尸达标 → BOSS 破土出场 → 打死 BOSS → 胜利）：
#   非 BOSS 关：击杀达标即胜利
#   BOSS 关：击杀达标 且 BOSS 已死 才胜利（BOSS 未出场/未死时 _boss_dead=false，不会误判）
# 已结束(_ended)、无尽模式、或已在结算倒计时中则忽略
# （倒计时里玩家补杀丧尸不应重复触发通关；无尽模式永不「通关」）
func _check_victory():
	if _ended or _endless or _victory_counting_down or player.dead:
		return
	if _kills < _goal:
		return
	if Stages.has_boss(GameState.selected_stage) and not _boss_dead:
		return
	_on_victory()

# 刷新顶部「击杀 X/Y」进度文字
func _refresh_kills_label():
	if _kills_label != null:
		_kills_label.text = "击杀 %d/%d" % [_kills, _goal]

# ----------------------------------------------------------------------------
# _on_zombie_died()：丧尸被打死 → 加经验 + 掉落金币，并飘一枚金币做反馈
# ----------------------------------------------------------------------------
func _on_zombie_died(pos: Vector2):
	if _ended or player.dead:
		return
	GameState.add_exp(10)                 # 击杀 +10 经验
	GameState.record_kill()               # 任务/成就统计：累计击杀 + 每日「击杀20」进度
	# 掉落金币：掉在路面上，需要玩家走过去捡（不是击杀即入账）
	var value: int = GameState.roll_coin_value()
	_spawn_drop_coin(pos, value)
	# 掉落腐肉（背包物品）：10% 概率掉在地上，走过去自动捡入背包，
	# 攒够后用于家园解锁/升级农田（见 drop_item.gd / GameState.remove_item）
	if randf() < GameState.ROTTEN_MEAT_DROP_CHANCE:
		_spawn_drop_item(pos, "rotten_meat")

	# 通关进度：击杀数达标 → 胜利并解锁下一关
	_kills += 1
	# 无尽模式：计本局击杀，标签显示波次；场上清空则推进下一波
	if _endless:
		_endless_kills += 1
		_refresh_endless_hud()
		_maybe_endless_next_wave()
		return
	if _kills_label != null:
		_kills_label.text = "击杀 %d/%d" % [_kills, _goal]
	# 宝箱：每累计击杀 CHEST_KILL_INTERVAL 个丧尸，随机得一个宝箱放入空槽
	GameState.chest_kill_count += 1
	if GameState.chest_kill_count >= GameState.CHEST_KILL_INTERVAL:
		GameState.chest_kill_count = 0
		var slot: int = GameState.add_chest()
		if slot >= 0:
			_chests_earned_this_level.append({"type": GameState.chests[slot]["type"], "slot": slot})
		else:
			_chests_earned_this_level.append({"type": GameState.roll_chest_type(), "slot": -1})
	GameState.save_profile()             # 保存更新后的宝箱累计击杀数
	# 击杀达标后先让 BOSS 出场，再判通关（BOSS 关必须打死 BOSS 才算过）
	_maybe_spawn_boss()
	_check_victory()

# 全局按键监听：按 B 键开/关武器商店（忽略系统重复按键 event.echo）
func _input(event):
	# 通关倒计时中：按任意键立即结算（玩家捡够东西了就不必干等）
	if _victory_counting_down and not _victory_done:
		if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
			_finish_victory()
			return
	# B 键打开/关闭武器商店
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_toggle_weapon_shop()

# 金币/钻石 HUD 刷新（监听 GameState.stats_changed）
func _refresh_currency():
	_currency_labels["gold"].text = "%d" % GameState.gold
	_currency_labels["diamond"].text = "%d" % GameState.diamonds

# ----------------------------------------------------------------------------
# 武器商店 UI
# ----------------------------------------------------------------------------
func _build_weapon_shop():
	_shop_panel = Control.new()
	_shop_panel.name = "WeaponShop"
	_shop_panel.visible = false
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	$UI.add_child(_shop_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.92)
	bg.set_anchors_preset(Control.PRESET_CENTER)
	bg.size = Vector2(760, 480)
	bg.position = -bg.size / 2
	_shop_panel.add_child(bg)

	var title := Label.new()
	title.text = "武器商店（B 关闭）"
	title.add_theme_font_size_override("font_size", 32)
	title.position = Vector2(-bg.size.x / 2 + 24, -bg.size.y / 2 + 16)
	_shop_panel.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(-bg.size.x / 2 + 24, -bg.size.y / 2 + 70)
	grid.size = Vector2(bg.size.x - 48, bg.size.y - 90)
	_shop_panel.add_child(grid)

	for id in Weapons.ORDER:
		var wp: Dictionary = Weapons.DATA[id]
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = wp.name
		name_label.add_theme_font_size_override("font_size", 20)
		box.add_child(name_label)

		var stat_label := Label.new()
		stat_label.text = "伤害:%d  射速:%.1f/s" % [wp.damage, wp.fire_rate]
		stat_label.add_theme_font_size_override("font_size", 14)
		box.add_child(stat_label)

		var desc_label := Label.new()
		desc_label.text = wp.desc
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc_label)

		var btn := Button.new()
		btn.text = "装备"
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_on_buy_weapon.bind(id))
		box.add_child(btn)
		_shop_buttons[id] = {"btn": btn, "stat": stat_label}
		grid.add_child(box)

	# ---- 医疗包购买区（局内用金币买，自动进背包，按 F 使用）----
	var row_y: float = 184.0
	var med_panel := Panel.new()
	med_panel.position = Vector2(grid.position.x, row_y)
	med_panel.size = Vector2(bg.size.x - 48, 48)
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.10, 0.13, 0.10, 0.95)
	msb.set_border_width_all(1)
	msb.border_color = Color(0.3, 0.7, 0.4, 0.7)
	msb.set_corner_radius_all(6)
	med_panel.add_theme_stylebox_override("panel", msb)
	_shop_panel.add_child(med_panel)
	var med_lbl := Label.new()
	med_lbl.text = "医疗包：局内按 F 使用，恢复 50 生命（冷却 1.5 秒）"
	med_lbl.add_theme_font_size_override("font_size", 14)
	med_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75, 1))
	med_lbl.position = Vector2(grid.position.x + 12, row_y + 4)
	med_lbl.size = Vector2(bg.size.x - 48 - 176, 40)
	_shop_panel.add_child(med_lbl)
	var med_btn := Button.new()
	med_btn.add_theme_font_size_override("font_size", 16)
	med_btn.position = Vector2(grid.position.x + bg.size.x - 48 - 164, row_y + 5)
	med_btn.size = Vector2(152, 38)
	med_btn.pressed.connect(_on_buy_medkit)
	_shop_panel.add_child(med_btn)
	_medkit_btn = med_btn

	_refresh_shop()

# 刷新商店按钮：已解锁→显示「装备/已装备」；未解锁→显示价格且金币不足时禁用；同步医疗包持有数量与可购状态
func _refresh_shop():
	for id in Weapons.ORDER:
		var wp: Dictionary = Weapons.DATA[id]
		var btn: Button = _shop_buttons[id]["btn"]
		if Weapons.is_unlocked(id):
			var in_loadout: bool = id in Weapons.loadout
			btn.text = "装备" if not in_loadout else "已装备"
			btn.disabled = in_loadout
		else:
			btn.text = "购买 (%d 金币)" % wp.price
			btn.disabled = GameState.gold < wp.price
	if _medkit_btn != null:
		var cnt: int = GameState.item_count("medkit")
		_medkit_btn.text = "购买 ×1 (%d金) 持有%d" % [MEDKIT_PRICE, cnt]
		_medkit_btn.disabled = GameState.gold < MEDKIT_PRICE

# 创建「当前手持武器」HUD 标签（含按 Q 切换提示），并立即刷新一次
func _build_weapon_hud():
	_weapon_hud_label = Label.new()
	_weapon_hud_label.position = Vector2(20, 72)
	_weapon_hud_label.add_theme_font_size_override("font_size", 16)
	_weapon_hud_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	$UI.add_child(_weapon_hud_label)
	_refresh_weapon_hud("")

# 刷新手持武器 HUD：显示武器名+所在槽位；仅当另一槽有装备时才提示「按 Q 切换」（_id 为触发切换的武器 id，此处未使用）
func _refresh_weapon_hud(_id: String):
	if _weapon_hud_label == null:
		return
	var wid: String = Weapons.get_active_id()
	var name: String = Weapons.DATA.get(wid, {}).get("name", wid)
	var slot: int = Weapons.active_slot + 1
	var can_swap := false
	for other in range(Weapons.LOADOUT_SLOT_COUNT):
		if other != Weapons.active_slot and Weapons.is_slot_unlocked(other) and Weapons.loadout[other] != "":
			can_swap = true
			break
	_weapon_hud_label.text = "手持武器：%s（槽 %d）  %s" % [name, slot, "按 Q 切换" if can_swap else ""]

# ----------------------------------------------------------------------------
# 弹夹 / 换弹 / 医疗包 HUD（左下角，逐帧刷新）
# ----------------------------------------------------------------------------
func _build_ammo_hud():
	_ammo_hud_label = Label.new()
	_ammo_hud_label.position = Vector2(20, 120)
	_ammo_hud_label.add_theme_font_size_override("font_size", 16)
	_ammo_hud_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	$UI.add_child(_ammo_hud_label)
	_medkit_hud_label = Label.new()
	_medkit_hud_label.position = Vector2(20, 144)
	_medkit_hud_label.add_theme_font_size_override("font_size", 16)
	_medkit_hud_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 0.95))
	$UI.add_child(_medkit_hud_label)
	_refresh_combat_hud()

# 每帧刷新弹药/换弹与医疗包 HUD：换弹中显示剩余秒数，否则显示弹夹余量；医疗包显示数量与冷却
func _refresh_combat_hud():
	if player == null or not is_instance_valid(player):
		return
	# 弹药 / 换弹
	var slot: int = Weapons.active_slot
	var wid: String = Weapons.get_active_id()
	var cur: int = int(player.ammo_by_slot.get(slot, 0))
	var mag: int = Weapons.effective_magazine(wid)
	if player.reloading:
		_ammo_hud_label.text = "换弹中… (%.1fs)" % player.reload_timer
	else:
		_ammo_hud_label.text = "弹夹 %d/%d" % [cur, mag]
	# 医疗包（数量 + 冷却）
	var mc: int = GameState.item_count("medkit")
	var mcd: String = "就绪" if player.medkit_cd <= 0.0 else ("%.1fs" % player.medkit_cd)
	_medkit_hud_label.text = "医疗包[F] ×%d  %s" % [mc, mcd]

# ----------------------------------------------------------------------------
# 技能 HUD：手雷（G）/ 支援导弹（H）的伤害与冷却
# 每帧刷新，因为冷却剩余时间是连续变化的
# ----------------------------------------------------------------------------
func _build_skill_hud():
	_skill_hud_label = Label.new()
	_skill_hud_label.position = Vector2(20, 96)
	_skill_hud_label.add_theme_font_size_override("font_size", 16)
	_skill_hud_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42, 1))
	$UI.add_child(_skill_hud_label)
	_refresh_skill_hud()

# 每帧刷新技能 HUD（手雷/导弹冷却）与战斗 HUD（弹药/医疗包）
func _process(_delta: float):
	_refresh_skill_hud()
	_refresh_combat_hud()

# 刷新技能 HUD：显示手雷/支援导弹的伤害数值与冷却状态（就绪或剩余秒数）
func _refresh_skill_hud():
	if _skill_hud_label == null or player == null or not is_instance_valid(player):
		return
	var gdmg: int = int(player.char_stats.get("grenade_damage", 0))
	var mdmg: int = int(player.char_stats.get("missile_damage", 0))
	# 弹药为 0 时追加「(无弹药)」，让玩家一眼看出技能因缺弹药而无法使用
	var ga: int = GameState.grenade_ammo
	var ma: int = GameState.missile_ammo
	var gtxt: String = "手雷[G] ×%d %d伤 %s" % [ga, gdmg, _cd_text(player.grenade_cd)]
	if ga <= 0:
		gtxt += " (无弹药)"
	var mtxt: String = "支援导弹[H] ×%d %d伤 %s" % [ma, mdmg, _cd_text(player.missile_cd)]
	if ma <= 0:
		mtxt += " (无弹药)"
	_skill_hud_label.text = "%s   ｜   %s" % [gtxt, mtxt]

# 将冷却秒数格式化为 HUD 文本：≤0 显示「就绪」，否则显示一位小数秒
func _cd_text(cd: float) -> String:
	if cd <= 0.0:
		return "就绪"
	return "%.1fs" % cd

# 商店点「装备/购买」按钮：已解锁→装备到当前槽；未解锁→扣金币购买。id 为武器 id
func _on_buy_weapon(id: String):
	if Weapons.is_unlocked(id):
		Weapons.equip_to_slot(Weapons.active_slot, id)
	else:
		Weapons.buy(id)
	_refresh_shop()

# 在局内商店用金币买医疗包（自动进背包）
func _on_buy_medkit():
	if GameState.gold < MEDKIT_PRICE:
		return
	if not GameState.add_item("medkit", 1):
		return
	GameState.gold -= MEDKIT_PRICE
	GameState.save_profile()        # 金币变化需要写入进度存档
	GameState.stats_changed.emit()   # 刷新顶部金币 HUD
	_refresh_shop()

# 切换武器商店面板的显示/隐藏；打开时刷新一次状态
func _toggle_weapon_shop():
	if _shop_panel == null:
		return
	_shop_panel.visible = not _shop_panel.visible
	if _shop_panel.visible:
		_refresh_shop()

# 在丧尸死亡处掉一枚金币：先弹起、再落到路面，需玩家走过去捡（见 coin.gd）
func _spawn_drop_coin(pos: Vector2, value: int):
	var coin = preload("res://coin.gd").new()
	coin.setup(value, pos)
	add_child(coin)

# 在丧尸死亡处掉一个物品（腐肉等）：掉落/超时机制与金币一致（见 drop_item.gd）
func _spawn_drop_item(pos: Vector2, item_id: String):
	var item = preload("res://drop_item.gd").new()
	item.setup(item_id, pos)
	add_child(item)

# ============================================================================
# 游戏菜单系统（右上角按钮 → 弹出菜单 → 继续游戏 / 返回主界面 / 设置）
# ============================================================================
func _build_game_menu():
	# ---- 右上角菜单按钮（灰黑色背景）----
	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = "≡  菜单"
	_menu_btn.add_theme_font_size_override("font_size", 16)

	# 灰黑色圆角按钮样式
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.45, 0.45, 0.45, 0.8)
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_left = 14
	normal_style.content_margin_right = 14
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6
	_menu_btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.28, 0.95)
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.6, 0.6, 0.6, 0.9)
	hover_style.corner_radius_top_left = 6
	hover_style.corner_radius_top_right = 6
	hover_style.corner_radius_bottom_left = 6
	hover_style.corner_radius_bottom_right = 6
	hover_style.content_margin_left = 14
	hover_style.content_margin_right = 14
	hover_style.content_margin_top = 6
	hover_style.content_margin_bottom = 6
	_menu_btn.add_theme_stylebox_override("hover", hover_style)
	_menu_btn.add_theme_stylebox_override("pressed", normal_style)

	# 右上角定位
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_menu_btn.position = Vector2(vp_w - 120, 12)
	_menu_btn.size = Vector2(100, 36)
	$UI.add_child(_menu_btn)

	# ---- 弹出菜单 ----
	_popup_menu = PopupMenu.new()
	_popup_menu.name = "GameMenuPopup"
	_popup_menu.add_item("继续游戏", 0)
	_popup_menu.add_item("返回主界面", 1)
	_popup_menu.add_item("设置", 2)
	_popup_menu.add_theme_font_size_override("font_size", 18)

	# 弹出菜单灰黑色背景
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.12, 0.12, 0.14, 0.97)
	popup_style.border_width_left = 2
	popup_style.border_width_top = 2
	popup_style.border_width_right = 2
	popup_style.border_width_bottom = 2
	popup_style.border_color = Color(0.4, 0.4, 0.4, 0.8)
	popup_style.corner_radius_top_left = 4
	popup_style.corner_radius_top_right = 4
	popup_style.corner_radius_bottom_left = 4
	popup_style.corner_radius_bottom_right = 4
	popup_style.content_margin_left = 12
	popup_style.content_margin_right = 12
	popup_style.content_margin_top = 8
	popup_style.content_margin_bottom = 8
	_popup_menu.add_theme_stylebox_override("panel", popup_style)

	$UI.add_child(_popup_menu)
	_popup_menu.id_pressed.connect(_on_menu_item_selected)
	_popup_menu.popup_hide.connect(_on_popup_closed)
	_menu_btn.pressed.connect(_on_menu_btn_pressed)

	# ---- 设置面板 ----
	_build_settings_panel()

# 菜单按钮点击：菜单已打开→关闭（触发恢复游戏）；否则暂停游戏并弹出菜单（定位在按钮下方，右对齐）
func _on_menu_btn_pressed():
	# 菜单已打开 → 点击按钮关闭
	if get_tree().paused and _popup_menu.visible:
		_popup_menu.hide()   # 会触发 _on_popup_closed → 恢复游戏
		return
	# 暂停游戏，弹出菜单
	get_tree().paused = true
	_popup_menu.popup()
	# 定位：按钮下方，右边缘对齐按钮右边缘
	var px: float = _menu_btn.global_position.x + _menu_btn.size.x - _popup_menu.size.x
	var py: float = _menu_btn.global_position.y + _menu_btn.size.y
	_popup_menu.position = Vector2(maxf(0, px), py)

# 弹出菜单项处理：id=0 继续游戏 / id=1 返回主界面(Hub) / id=2 打开设置面板（保持暂停）
func _on_menu_item_selected(id: int):
	match id:
		0:   # 继续游戏 → 关闭菜单（popup_hide 会恢复游戏）
			_popup_menu.hide()
		1:   # 返回主界面 → 终止当前游戏，回到 Hub
			AudioManager.stop_bgm()
			get_tree().paused = false
			get_tree().change_scene_to_file("res://Hub.tscn")
		2:   # 设置 → 打开设置面板（游戏保持暂停）
			_opening_settings = true
			_popup_menu.hide()
			_show_settings()

# 菜单关闭回调：若本次只是跳去设置面板(_opening_settings)则不恢复游戏，否则解除暂停
func _on_popup_closed():
	# 如果是跳转到设置面板，不要恢复游戏
	if _opening_settings:
		_opening_settings = false
		return
	get_tree().paused = false

# ----------------------------------------------------------------------------
# 设置面板（灰黑色背景，含主音量滑块 + 关闭按钮）
# ----------------------------------------------------------------------------
func _build_settings_panel():
	_settings_panel = Control.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(_settings_panel)

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(overlay)

	# 面板（灰黑色背景 + 边框）
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 300)
	panel.position = Vector2(-210, -150)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.14, 0.97)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.4, 0.8)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	_settings_panel.add_child(panel)

	# 标题
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 28)
	title.position = Vector2(24, 16)
	panel.add_child(title)

	# 游戏音量标签
	var vol_label := Label.new()
	vol_label.text = "游戏音量"
	vol_label.add_theme_font_size_override("font_size", 18)
	vol_label.position = Vector2(24, 70)
	panel.add_child(vol_label)

	# 游戏音量滑块（读写 GameState.game_volume，与主界面设置面板共用一份数据）
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.value = GameState.game_volume
	vol_slider.position = Vector2(24, 100)
	vol_slider.size = Vector2(372, 24)
	vol_slider.value_changed.connect(_on_volume_changed)
	panel.add_child(vol_slider)

	# 音量百分比显示
	var vol_pct := Label.new()
	vol_pct.name = "VolPct"
	vol_pct.text = "%d%%" % int(vol_slider.value)
	vol_pct.add_theme_font_size_override("font_size", 16)
	vol_pct.position = Vector2(330, 72)
	panel.add_child(vol_pct)
	vol_slider.value_changed.connect(func(v: float): vol_pct.text = "%d%%" % int(v))

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.position = Vector2(300, 220)
	close_btn.size = Vector2(100, 40)
	close_btn.pressed.connect(_close_settings)
	panel.add_child(close_btn)

	# 背景音乐署名（Eric Matyas 授权要求：必须在游戏内署名，仅放商店简介不算合格）
	var credit := Label.new()
	credit.text = "背景音乐：Music by Eric Matyas · www.soundimage.org"
	credit.add_theme_font_size_override("font_size", 13)
	credit.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.9))
	credit.position = Vector2(24, 262)
	panel.add_child(credit)

func _on_volume_changed(value: float):
	# 写入全局「游戏界面音量」，与主界面齿轮设置面板共用一份数据并存档
	GameState.game_volume = value
	GameState.apply_game_volume()
	GameState.save_settings()

# 显示设置面板（从菜单选「设置」时调用）；游戏此前已暂停，保持暂停状态
func _show_settings():
	if _settings_panel != null:
		_settings_panel.visible = true

# 关闭设置面板并解除游戏暂停
func _close_settings():
	if _settings_panel != null:
		_settings_panel.visible = false
	get_tree().paused = false

# ============================================================================
# 关卡通关 / 结算（胜利 → 解锁下一关）
# ============================================================================

# 每关通关需要的击杀数：第1关 8 只，之后每关 +4 → 第10关 44 只（公式在 Stages.goal）
func _stage_goal(s: int) -> int:
	return Stages.goal(s)

# ============================================================================
#  无尽模式（Endless.gd 数据驱动）
# ----------------------------------------------------------------------------
#  规则：无限存活，死了才算结束。难度线性缓增（刷怪越来越密、敌人越来越厚）。
#  波次推进：本波场上敌人清空 → 波次 +1 → 刷怪间隔按新波次缩短、敌血按新波次加厚。
#  奖励波：每 ENDless.REWARD_WAVE 波结算一次（波次奖励，不看击杀数）。
#  BOSS 波：每 ENDless.BOSS_EVERY 波出一只 BOSS，血量随波次线性叠加。
# ============================================================================
# _start_endless()：进入无尽模式。替换关卡标签为「无尽 · 第 N 波」，并按第 1 波设定刷怪节奏。
func _start_endless():
	_endless = true
	_endless_wave = 1
	_endless_kills = 0
	_endless_diamond = 0
	_endless_reward_wave = 0
	_endless_boss_wave = 0
	_kills = 0
	_goal = 0                                   # 无尽没有通关目标，击杀进度显示波次
	# 关卡标签改成无尽样式
	for c in $UI.get_children():
		if c is Label and String((c as Label).text).begins_with("关卡 "):
			(c as Label).text = "无 尽 模 式"
			(c as Label).add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	# 击杀标签改显示波次
	if _kills_label != null:
		_kills_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_refresh_endless_hud()
	_apply_endless_wave()
	# 第 1 波不出 BOSS（BOssEVERY=10，第 10 波才出）
	spawn_timer.wait_time = Endless.spawn_interval(1)
	# 立刻刷出第 1 波的丧尸（否则开局场上是空的，_maybe_endless_next_wave 会误判为"已清空"）
	_spawn_endless_wave()

# _maybe_endless_next_wave()：无尽波次推进判定。
#   条件：玩家还活着 + 场上普通丧尸全清（BOSS 不算）+ **本波已全部刷完**→ 进入下一波。
#   两道防误触：
#     ① _endless_spawning（分批刷怪中）—— 否则第 1 批 4 只打完、距下一批 0.7 秒的空窗里
#        会被误判成"已清空"，波次连跳。
#     ② 0.8 秒冷却 —— 避免最后一波瞬间清完导致连跳。
func _maybe_endless_next_wave():
	if _ended or player.dead:
		return
	# 本波还在分批刷出（批次间隔中）→ 场上暂时空是正常的，不算清场
	if _endless_spawning:
		return
	# 还有普通丧尸在场就不推进（BOSS 不算，清完 BOSS 也算清场）
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z):
			continue
		if not z.is_in_group("normal_zombie"):
			return
	if Time.get_ticks_msec() - _endless_last_clear_ms < 800:
		return
	_endless_last_clear_ms = Time.get_ticks_msec()
	_endless_next_wave()

# _apply_endless_wave()：把当前波次的难度写进刷怪节奏（血量倍率在生成时读）。
func _apply_endless_wave():
	spawn_timer.wait_time = Endless.spawn_interval(_endless_wave)

# _refresh_endless_hud()：刷新顶部「无尽 · 第 N 波」文字。
func _refresh_endless_hud():
	if _kills_label != null:
		_kills_label.text = "第 %d 波" % _endless_wave

# _endless_next_wave()：本波清空 → 进入下一波（加难度、结算奖励波、出 BOSS 波）。
func _endless_next_wave():
	_endless_wave += 1
	_apply_endless_wave()
	_refresh_endless_hud()
	# BOSS 波：每 BOSS_EVERY 波出一只
	if Endless.is_boss_wave(_endless_wave) and _endless_boss_wave != _endless_wave:
		_endless_boss_wave = _endless_wave
		_spawn_endless_boss()
	# 奖励波：每 REWARD_WAVE 波结算一次（同一波只发一次）
	if Endless.is_reward_wave(_endless_wave) and _endless_reward_wave != _endless_wave:
		_endless_reward_wave = _endless_wave
		_grant_endless_reward()

# _spawn_endless_boss()：无尽模式的 BOSS 出场（血量按波次线性叠加，绕开主线 BOSS 关的出场条件）。
func _spawn_endless_boss():
	var type := Endless.boss_type_for(_endless_wave)
	_boss_spawned = true
	_boss_pending_type = type
	_boss_pending_hp_mul = Endless.boss_hp_mul(_endless_wave)
	spawn_boss(type, _boss_pending_hp_mul)
	_show_boss_warning()

# _grant_endless_reward()：波次奖励结算（Endless.reward_for 返回本波奖励）。
func _grant_endless_reward():
	var r := Endless.reward_for(_endless_wave)
	if r.is_empty():
		return
	var g := int(r["gold"])
	var s := int(r["soul"])
	var d := int(r["diamond"])
	GameState.gold += g
	for _i in range(s):
		GameState.add_item("soul", 1)
	GameState.diamonds += d
	_endless_diamond += d
	GameState.save_profile()
	GameState.stats_changed.emit()
	_toast_center("第 %d 波奖励：+%d 金币  +%d 精魂  +%d 钻石" % [_endless_wave, g, s, d])

# _on_player_died 已在上面定义；无尽模式死亡时也要记结算（在 _on_player_died 里加分支）。

# _endless_game_over()：无尽模式死亡结算——记录最高波次/击杀/钻石，然后走原死亡面板。
# ★必须在这里把 endless_mode 复位为 false：本局结束、玩家会退回主界面/关卡选择，
#   不复位的话之后玩主线关也会误进无尽模式。
func _endless_game_over():
	GameState.record_endless(_endless_wave, _endless_kills, _endless_diamond)
	GameState.endless_mode = false

# _toast_center(text)：屏幕居中飘字（波次奖励提示）。
func _toast_center(text: String):
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 320, vh * 0.30)
	lbl.size = Vector2(640, 40)
	$UI.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

# _on_victory()：击杀达标 → 解锁下一关并弹出胜利面板
# ★无尽模式没有「通关」概念：死亡才算结束，绝不能弹胜利面板、也不能解锁主线关卡
#   （无尽里 _goal 恒为 0，击杀一开始就满足达标条件，不拦住会立刻误判通关）。
func _on_victory():
	if _ended or _endless:
		return
	# ★ 不立刻结束：先进入 5 秒结算倒计时，让玩家把地上的金币/腐肉/掉落物捡完。
	#   玩家可以按任意键提前结束倒计时。
	if _victory_counting_down:
		return
	_start_victory_countdown()


# ============================================================================
#  通关结算倒计时（击杀达标后 5 秒才真正结束）
# ----------------------------------------------------------------------------
#  为什么要延迟：原先 _check_victory 一达标就 get_tree().paused = true，
#  玩家来不及捡掉在地上的金币/腐肉/战利品。现在给 5 秒自由时间捡东西。
# ============================================================================
func _start_victory_countdown():
	# 双保险：无尽模式绝不走通关结算（万一别处误调也不会锁死游戏）
	if _endless:
		return
	_victory_counting_down = true
	# ★不要设_ended = true：那会让玩家在倒计时期间死亡无法触发战败面板。
	#   通关判定靠 _victory_counting_down 本身拦（_check_victory 里已判 _victory_done），
	#   这里只需要停掉刷怪，_on_zombie_died 的早退由 _ended 之外的判断保证。
	spawn_timer.stop()
	# 停掉仍在移动的敌人，但**不暂停游戏**，玩家还能走位捡东西
	for z in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("enemy_hazards"):
		if z.has_method("stop_moving"):
			z.stop_moving()
	_build_countdown_label()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(VICTORY_COUNTDOWN_SEC)
	tw.tween_callback(_finish_victory)


# _build_countdown_label()：屏幕中央只显示一个倒计时数字（5→ 4 → 3 …），简洁干净。
# 玩家看数字就知道在倒计时；按任意键可提前结算（见 _input）。
func _build_countdown_label():
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 挂在 $UI 下（UI 层），确保盖在游戏画面之上；$UI 是 PROCESS_MODE_ALWAYS，暂停时也能显示
	$UI.add_child(box)
	_countdown_ui = box

	# 单行倒计时：黄色大字 + 黑描边，屏幕正中央
	var cd := Label.new()
	cd.add_theme_font_size_override("font_size", 64)
	cd.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	cd.add_theme_color_override("font_outline_color", Color.BLACK)
	cd.add_theme_constant_override("outline_size", 10)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.size = Vector2(vw, 80)
	cd.position = Vector2(0, vh * 0.42)
	cd.name = "Countdown"
	box.add_child(cd)
	_countdown_label = cd

	# 每 0.5 秒刷新一次秒数
	var tick := create_tween()
	tick.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var left := VICTORY_COUNTDOWN_SEC
	while left > 0:
		if _countdown_label != null and is_instance_valid(_countdown_label):
			_countdown_label.text = str(int(ceil(left)))
		tick.tween_interval(0.25)
		left -= 0.25


# _finish_victory()：倒计时结束（或玩家提前按键）→ 解锁下一关 + 弹胜利面板。
func _finish_victory():
	if _victory_done:
		return
	_victory_done = true
	if _countdown_ui != null and is_instance_valid(_countdown_ui):
		_countdown_ui.queue_free()
		_countdown_ui = null
	# 解锁下一关（unlock_stage 内部有保护，重复解锁不会把进度改小）
	GameState.unlock_stage(GameState.selected_stage + 1)
	GameState.record_level_clear()        # 任务/成就统计：通关次数 + 每日「通关1」进度
	get_tree().paused = true
	_show_victory()

# 重进 Main（用于「下一关」「重玩本关」，关卡号由 GameState.selected_stage 决定）
func _goto_main():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main.tscn")

# 显示胜利面板：依据是否最后一关切换标题/副标题文案，控制「下一关」按钮可见性，并刷新本关获得的宝箱卡片
func _show_victory():
	# 无尽模式没有通关概念：万一被误调也不弹主线胜利面板（而是走死亡结算）
	if _endless:
		_endless_game_over()
		return
	if _victory_panel == null:
		return
	var last: bool = GameState.selected_stage >= GameState.STAGE_COUNT
	var title: Label = _victory_panel.get_node_or_null("Title")
	if title != null:
		if last:
			title.text = "全 部 通 关 !"
		else:
			title.text = "关 卡 胜 利 !"
	var sub: Label = _victory_panel.get_node_or_null("Sub")
	if sub != null:
		if last:
			sub.text = "你已打穿全部 %d 关！" % GameState.STAGE_COUNT
		else:
			sub.text = "已解锁第 %d 关" % (GameState.selected_stage + 1)
	var next_btn: Control = _victory_panel.get_node_or_null("NextBtn")
	if next_btn != null:
		next_btn.visible = not last
	_victory_panel.visible = true
	_build_victory_chest_cards()

func _build_victory_panel():
	_victory_panel = Control.new()
	_victory_panel.name = "VictoryPanel"
	_victory_panel.visible = false
	_victory_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(_victory_panel)

	var cx: float = get_viewport().get_visible_rect().size.x / 2.0
	var cy: float = get_viewport().get_visible_rect().size.y / 2.0

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_panel.add_child(overlay)

	var title := Label.new()
	title.name = "Title"
	title.text = "关 卡 胜 利 !"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1))
	title.position = Vector2(cx - 200, cy - 130)
	title.size = Vector2(400, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_panel.add_child(title)

	var sub := Label.new()
	sub.name = "Sub"
	sub.text = "已解锁下一关"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	sub.position = Vector2(cx - 160, cy - 50)
	sub.size = Vector2(320, 34)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_panel.add_child(sub)

	var next_btn := Button.new()
	next_btn.name = "NextBtn"
	next_btn.text = "下一关"
	next_btn.add_theme_font_size_override("font_size", 24)
	next_btn.custom_minimum_size = Vector2(220, 56)
	next_btn.position = Vector2(cx - 110, cy + 10)
	next_btn.pressed.connect(_on_next_pressed)
	_victory_panel.add_child(next_btn)

	var replay_btn := Button.new()
	replay_btn.text = "重玩本关"
	replay_btn.add_theme_font_size_override("font_size", 20)
	replay_btn.custom_minimum_size = Vector2(220, 48)
	replay_btn.position = Vector2(cx - 110, cy + 80)
	replay_btn.pressed.connect(_on_replay_pressed)
	_victory_panel.add_child(replay_btn)

	var ls_btn := Button.new()
	ls_btn.text = "返回关卡选择"
	ls_btn.add_theme_font_size_override("font_size", 20)
	ls_btn.custom_minimum_size = Vector2(220, 48)
	ls_btn.position = Vector2(cx - 110, cy + 140)
	ls_btn.pressed.connect(_on_victory_levelselect_pressed)
	_victory_panel.add_child(ls_btn)

	# 宝箱展示区（关卡结束显示本关获得的宝箱 + 解锁）；位于按钮下方
	var ca := Control.new()
	ca.name = "ChestArea"
	ca.position = Vector2(cx - 360, cy + 195)
	ca.size = Vector2(720, 124)
	_victory_panel.add_child(ca)
	_victory_chest_area = ca

	# 解锁进度刷新计时器（process_mode=ALWAYS，胜利面板暂停时也照常走）
	var ct := Timer.new()
	ct.name = "ChestTick"
	ct.wait_time = 1.0
	ct.process_mode = Node.PROCESS_MODE_ALWAYS
	ct.timeout.connect(_tick_victory_chests)
	_victory_panel.add_child(ct)
	ct.start()

# 构建胜利面板里的「本关获得宝箱」展示（每次胜利时按本关获得列表刷新）
func _build_victory_chest_cards():
	if _victory_chest_area == null:
		return
	for c in _victory_chest_area.get_children():
		_victory_chest_area.remove_child(c)
		c.free()
	_victory_chest_cards = []

	# 没获得宝箱就不显示任何提示
	var earned: Array = _chests_earned_this_level
	if earned.is_empty():
		return

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.position = Vector2(0, 0)
	head.size = Vector2(720, 26)
	head.text = "本关获得宝箱"
	_victory_chest_area.add_child(head)

	var n: int = earned.size()
	var card_w := 160.0
	var gap := 16.0
	var total := float(n) * card_w + float(n - 1) * gap
	var x0 := (720.0 - total) / 2.0
	for i in range(n):
		_build_victory_chest_card(earned[i], x0 + float(i) * (card_w + gap), card_w)

# 在胜利面板宝箱区构建一张宝箱卡片（图标/名称/解锁或领取按钮/进度条）。
#   earned: {"type": 宝箱类型, "slot": 槽位(>=0 有空槽, <0 宝箱已满)}
#   x, w: 卡片左上角 X 与卡片宽度（像素）
func _build_victory_chest_card(earned: Dictionary, x: float, w: float):
	var slot: int = earned["slot"]
	var type: String = earned["type"]
	var def = GameState.CHEST_DEFS[type]
	var root := Panel.new()
	root.position = Vector2(x, 4.0)
	root.size = Vector2(w, 118.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.12, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(def["color"].r, def["color"].g, def["color"].b, 0.9)
	sb.set_corner_radius_all(8)
	root.add_theme_stylebox_override("panel", sb)
	_victory_chest_area.add_child(root)

	# 宝箱已满（无空槽）：只显示说明，不可交互
	if slot < 0:
		var note := Label.new()
		note.text = def["name"] + "\n(宝箱已满)"
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.position = Vector2(0, 44.0)
		note.size = Vector2(w, 40)
		root.add_child(note)
		return

	# 宝箱图标（精绘贴图，无则不显示）
	var tex := GameState._tex_from_png("res://art/chest_%s.png" % type)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.position = Vector2(8, 6)
		icon.size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = def["name"]
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(40, 8.0)
	name_lbl.size = Vector2(w - 48, 36)
	root.add_child(name_lbl)

	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 16)
	btn.position = Vector2(w / 2.0 - 55.0, 40.0)
	btn.size = Vector2(110.0, 34.0)
	btn.pressed.connect(_on_victory_chest_btn_pressed.bind(slot))
	root.add_child(btn)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.position = Vector2(12.0, 80.0)
	bar.size = Vector2(w - 24.0, 18.0)
	bar.visible = false
	root.add_child(bar)

	var remain := Label.new()
	remain.add_theme_font_size_override("font_size", 13)
	remain.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	remain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remain.position = Vector2(0, 98.0)
	remain.size = Vector2(w, 18)
	root.add_child(remain)

	_victory_chest_cards.append({"slot": slot, "btn": btn, "bar": bar, "remain": remain, "collected": false})
	_tick_victory_chests()

# 宝箱卡片按钮：状态1(未解锁待开始)→调用 start_unlock；状态3(已解锁可领)→领取奖励并标记已领；slot<0（宝箱已满）忽略
func _on_victory_chest_btn_pressed(slot: int):
	if slot < 0:
		return
	var st := GameState.chest_state(slot)
	if st == 1:
		# 互斥：同一时间只允许 1 个宝箱在解锁。
		# start_unlock 底层已强制拦截（返回 false），这里只需刷新面板让按钮正确置灰。
		GameState.start_unlock(slot)
	elif st == 3:
		GameState.collect_chest(slot)
		for card in _victory_chest_cards:
			if card["slot"] == slot:
				card["collected"] = true
	_tick_victory_chests()

# 每秒刷新胜利面板宝箱卡片的解锁进度（暂停时仍走，因计时器 process_mode=ALWAYS）
func _tick_victory_chests():
	if _victory_panel == null or not _victory_panel.visible:
		return
	for card in _victory_chest_cards:
		var slot: int = card["slot"]
		if slot < 0:
			continue
		if card["collected"]:
			card["btn"].visible = false
			card["bar"].visible = false
			card["remain"].text = "已领取 ✓"
			continue
		var st := GameState.chest_state(slot)
		if st == 1:
			card["btn"].visible = true
			card["btn"].text = "解锁"
			# 互斥：同一时间只允许 1 个宝箱在解锁，有别的宝箱在解则本按钮置灰
			card["btn"].disabled = GameState.any_chest_unlocking()
			card["bar"].visible = false
			card["remain"].text = ""
		elif st == 2:
			card["btn"].visible = false
			card["btn"].disabled = false
			card["bar"].visible = true
			var total := float(GameState.CHEST_DEFS[GameState.chests[slot]["type"]]["unlock_sec"]) * 1000.0
			var rem := GameState.remaining_ms(slot)
			card["bar"].value = 1.0 - (rem / total)
			card["remain"].text = "剩余 " + _fmt_time(rem)
		elif st == 3:
			card["btn"].visible = true
			card["btn"].disabled = false
			card["btn"].text = "领取"
			card["bar"].visible = true
			card["bar"].value = 1.0
			card["remain"].text = "可领取"

# 将毫秒格式化为 H:MM:SS（≥1 小时）或 MM:SS 文本，用于宝箱解锁剩余时间显示
func _fmt_time(ms: float) -> String:
	var s := int(ms / 1000.0)
	var h := s / 3600
	s %= 3600
	var m := s / 60
	s %= 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]

# 「下一关」按钮：若未到最后一关则 selected_stage+1，然后重进 Main 场景
func _on_next_pressed():
	if GameState.selected_stage < GameState.STAGE_COUNT:
		# 直接进下一关也算「用户当前选中」，立即落盘：
		# 这样通关后即使直接点下一关连打，返回选关界面/重进游戏仍停在最后打的那一关。
		GameState.set_selected_stage(GameState.selected_stage + 1)
	_goto_main()

# 「重玩本关」按钮：用当前 selected_stage 重进 Main 场景
func _on_replay_pressed():
	_goto_main()

# 胜利面板「返回关卡选择」：解除暂停并切到 LevelSelect 场景
func _on_victory_levelselect_pressed():
	AudioManager.stop_bgm()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://LevelSelect.tscn")

# 战败面板加一个「返回关卡选择」按钮（原面板只支持按 R 重开）
func _add_gameover_levelselect_btn():
	var go_panel: Control = $UI/GameOverPanel
	if go_panel == null:
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y
	var ls_btn := Button.new()
	ls_btn.name = "LevelSelectBtn"
	ls_btn.text = "返回关卡选择"
	ls_btn.add_theme_font_size_override("font_size", 20)
	ls_btn.custom_minimum_size = Vector2(220, 48)
	ls_btn.position = Vector2(vw / 2.0 - 110, vh / 2.0 + 90)
	ls_btn.pressed.connect(_on_defeat_levelselect_pressed)
	go_panel.add_child(ls_btn)

# 战败面板「返回关卡选择」按钮：解除暂停并切到 LevelSelect 场景
func _on_defeat_levelselect_pressed():
	AudioManager.stop_bgm()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://LevelSelect.tscn")
