extends CharacterBody2D

# ============================================================================
# boss.gd —— BOSS 敌人（独立于 zombie.gd，便于加体型/技能/专属血条）
# ============================================================================
# 与 zombie.gd 的关系：
#   - 移动/追击/受击/死亡流程与丧尸一致（同样的 rising 爬出、直线追击、died 信号）
#   - 差异：体型更大（贴图按碰撞体高度自适应缩放，不依赖源图尺寸）、
#          伤害可配置（丧尸是硬编码 5）、带专属技能、有顶部大血条。
#
# 动作（boss_motion.gd）：程序化动作层——走路起伏/摇摆/前倾、漂浮（收割者）、
#   技能姿态（蓄力下蹲/冲刺前倾/落地压扁回弹/怒吼膨胀/投石弯腰/挥镰横扫），
#   每帧由 _physics_process 调 _motion.advance() 驱动，零新美术资源。
#
# 主技能（skill_type，boss_catalog.gd 配置）：
#   "charge" 冲锋 —— 蓄力后高速冲刺，撞到玩家造成重击（带残影拖尾 + 收尾硬直）
#   "slam"   震地 —— 跃起砸地，落地产生冲击波，范围内玩家受伤（带压扁回弹 + 裂纹尘土）
#   "summon" 召唤 —— 周期性召唤普通丧尸（脚下紫环法阵 + 紫雾，由 main.gd 生成小怪）
#
# 副技能（skill2_type，boss_catalog.gd 配置，独立冷却计时）：
#   "roar"   怒吼 —— 暴食者：膨胀蓄力后声波圈，震退身边小怪 + 范围伤害玩家
#   "rock"   投石 —— 绿巨人：弯腰捡石抛出，石头抛物线飞行，落地爆炸
#   "wave"   死亡斩波 —— 收割者：举镰横扫，甩出紫色月牙弹体，命中玩家重伤
#
# 走位（movement，boss_catalog.gd 配置）：
#   "chase" 追击 —— 一直走向玩家（暴食者/绿巨人）
#   "kite"  风筝 —— 远程 BOSS 用：玩家过近后撤、过远靠近、舒适区悬停（收割者）
#
# 必须 add_to_group("zombies")，否则玩家自动瞄准、手雷/导弹范围伤害都打不到它
# （player.gd 自动瞄准与 Explosion.damage_zombies 都只认这个组）。
# ============================================================================

signal died(pos: Vector2)
signal health_changed(cur: int, max: int)   # 供 main.gd 画顶部大血条
signal summon_requested(count: int)         # 召唤请求，由 main.gd 生成小怪

const GROUND_LINE := 478.0      # 与 ground.gd 保持一致
const BODY_HALF_H := 170.0      # 半高（丧尸是 90）
const STAND_Y := GROUND_LINE - BODY_HALF_H   # 308，脚底踩在路面
const SPRITE_SCALE_MUL := 1.0   # 体型倍率：1.0 = 贴图高度刚好贴合碰撞体（BODY_HALF_H*2）
								# 贴图实际缩放由 _apply_texture() 按源图高度算出，
								# 所以换任意尺寸的贴图都自动底对齐，不需要手改系数
const RISE_FROM := 260.0        # 出生时在落脚线下方的距离（爬出动画）
const RISE_SPEED := 260.0
const GRAVITY := 1200.0

# 技能类型名
const SKILL_CHARGE := "charge"
const SKILL_SLAM := "slam"
const SKILL_SUMMON := "summon"

# 副技能类型名
const SKILL2_ROAR := "roar"
const SKILL2_ROCK := "rock"
const SKILL2_WAVE := "wave"

# ⚠️ 下面这些是给编辑器看的占位默认值，真实数值在 boss_catalog.gd 的 DEFINITIONS
#    （由 main.gd 生成 BOSS 时赋值覆盖）。想改 BOSS 血量/攻击间隔请去 boss_catalog.gd。
@export var texture_path: String = "res://art/boss_prototypes_20260926/boss_brute.png"  # 立绘贴图路径
@export var max_health: int = 1200        # 【血量】基础值。★真实值在 boss_catalog.gd 的 max_health
@export var speed: float = 45.0           # 【移速】像素/秒
@export var attack_type: String = "melee"      # "melee" 近战 / "ranged" 远程
@export var melee_range: float = 115.0     # 【近战距离】够近才攻击（像素）
@export var ranged_range: float = 600.0   # 【远程距离】超出就不打
@export var attack_interval: float = 2.2  # 【攻击间隔】两次普攻最少隔几秒，越大越慢
@export var contact_damage: int = 18       # 【接触伤害】撞到/贴身时的伤害（普通丧尸是 5）
@export var skill_type: String = SKILL_CHARGE     # 【技能类型】charge冲锋 / slam震地 / summon召唤
@export var skill_interval: float = 6.0    # 【技能冷却】技能之间隔几秒
@export var skill_damage: int = 25             # 技能伤害
@export var display_name: String = "暴食者"
@export var movement: String = "chase"  # 【走位模式】chase追击 / kite风筝（远程 BOSS 保持距离）
@export var kite_min: float = 320.0     # 【风筝内圈】玩家距离小于此则后撤（像素）
@export var kite_max: float = 520.0     # 【风筝外圈】玩家距离大于此则靠近（像素）
# ---- 副技能（独立冷却，与主技能并行）----
@export var skill2_type: String = ""       # 【副技能类型】roar怒吼 / rock投石 / wave斩波（空 = 无）
@export var skill2_interval: float = 12.0  # 【副技能冷却】秒
@export var skill2_damage: int = 12        # 副技能伤害
@export var skill2_range: float = 320.0    # 副技能作用半径（rock=爆炸半径 / roar=声波半径）
var motion_cfg: Dictionary = {}            # 动作层参数表（main.gd 从 boss_catalog 传入）

var health: int = 1
var player_ref: Node2D = null
var rising := true
var dead := false
var stopped := false
var attack_timer := 0.0
var skill_timer := 0.0
var skill2_timer := 0.0
var skill_active := false       # 技能进行中（期间不追击/不普攻）
var _skill_tween: Tween = null
var _charge_dashing := false
var _charge_hit := false
var _hit_flash: Tween = null
var _sprite: Sprite2D = null
var _health_bar: Node2D = null
var _head_top: float = -170.0
var _dmg_seq := 0
var _dmg_labels: Array = []
# ---- 动作层（boss_motion.gd）----
var _motion: Node2D = null
var _motion_cfg: Dictionary = {}
var _action_state := ""           # 当前技能动作姿态名（空 = 走/待机）
var _action_progress := 0.0       # 当前技能动作进度 0~1（Tween 驱动）
var _ghost_timer := 0.0           # 冲刺残影计时器
var _rise_dust_timer := 0.0       # 爬出时尘土计时器
var _projectiles: Array = []      # 弹体表：{node, kind(rock/wave), vel, life, hit}
var _DEFAULT_MOTION := {
	"style": "heavy", "stride": 80.0, "bob": 4.0, "sway": 0.03, "lean": 0.05,
	"step_dust": 2, "dust_color": Color(0.55, 0.45, 0.32, 0.8),
}

func _ready():
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_load_texture()

	# 碰撞体：比丧尸（48x180）大一圈，按 BOSS 体型设定
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, BODY_HALF_H * 2.0)
	cs.shape = shape
	add_child(cs)

	# 与丧尸同层同掩码：layer4=敌人（子弹 mask 含 4 才打得到），mask1=只撞地面
	collision_layer = 4
	collision_mask = 1

	# 关键：加入 zombies 组，玩家自动瞄准 / 手雷导弹 AoE / 胜利时停动都靠它
	add_to_group("zombies")

	_health_bar = Node2D.new()
	_health_bar.z_index = 12
	_health_bar.draw.connect(_draw_health_bar)
	add_child(_health_bar)

	# 动作层：参数化走姿/技能姿态（零新资源）
	_motion = preload("res://boss_motion.gd").new()
	_motion.name = "MotionLayer"
	add_child(_motion)
	_motion.configure(_sprite, BODY_HALF_H)
	_motion_cfg = motion_cfg if not motion_cfg.is_empty() else _DEFAULT_MOTION

	health = max_health
	global_position.y = STAND_Y + RISE_FROM
	skill_timer = skill_interval
	skill2_timer = skill2_interval
	player_ref = get_tree().get_first_node_in_group("player")

func _load_texture():
	var tex: Texture2D = null
	if ResourceLoader.exists(texture_path):
		tex = load(texture_path)
	if tex == null:
		return
	_sprite.texture = tex
	# 高度自适应：把贴图缩放到「碰撞体高度 × 体型倍率」，再叠在节点原点。
	# 这样脚底永远落在 GROUND_LINE 上，换任意尺寸/比例的贴图都不会悬空或陷地。
	var s: float = (BODY_HALF_H * 2.0 / float(tex.get_height())) * SPRITE_SCALE_MUL
	_sprite.scale = Vector2(s, s)
	_sprite.position.y = 0.0
	_head_top = -BODY_HALF_H * SPRITE_SCALE_MUL

# ---------------------------------------------------------------------------
func _physics_process(delta: float):
	if dead or stopped:
		velocity = Vector2.ZERO
		return

	if rising:
		global_position.y = move_toward(global_position.y, STAND_Y, RISE_SPEED * delta)
		# 爬出时脚下喷尘，制造「破土而出」的尘土感
		_rise_dust_timer -= delta
		if _rise_dust_timer <= 0.0:
			_rise_dust_timer = 0.22
			_spawn_burst(Vector2(0.0, BODY_HALF_H), Color(0.55, 0.45, 0.34, 0.7), 3, 60.0)
		if global_position.y <= STAND_Y + 0.5:
			global_position.y = STAND_Y
			rising = false
			_spawn_burst(Vector2(0.0, BODY_HALF_H), Color(0.55, 0.45, 0.34, 0.8), 6, 100.0)
		return

	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		player_ref = get_tree().get_first_node_in_group("player")
		velocity.x = 0
		move_and_slide()
		return

	# 弹体（投石/斩波）更新：独立于 Boss 自身状态，死亡/停战时由 _cancel_skill 清空
	_update_projectiles(delta)

	# 动作层推进：默认走路/待机；技能期间由 _action_state 覆盖姿态
	var state := "walk" if not skill_active and absf(velocity.x) > 0.5 else "idle"
	if skill_active and not _action_state.is_empty():
		state = _action_state
	_motion.advance(delta, absf(velocity.x) * delta, state, _action_progress, _motion_cfg)

	# 技能优先级最高（主技能 + 副技能各自独立冷却）
	skill_timer -= delta
	skill2_timer -= delta
	if skill_active:
		if _charge_dashing:
			var previous_position := global_position
			if not is_on_floor():
				velocity.y += GRAVITY * delta
			move_and_slide()
			# 检查整个移动线段，避免高速冲刺越过玩家而漏判。
			var closest := Geometry2D.get_closest_point_to_segment(player_ref.global_position, previous_position, global_position)
			if not _charge_hit and closest.distance_squared_to(player_ref.global_position) <= melee_range * melee_range:
				_charge_hit = true
				_hit_player(skill_damage)
			# 冲刺残影拖尾
			_ghost_timer -= delta
			if _ghost_timer <= 0.0:
				_ghost_timer = 0.06
				_spawn_ghost()
		return
	if skill_timer <= 0.0 and not rising:
		_start_skill()
		return
	if skill2_timer <= 0.0 and not rising:
		_start_skill2()
		return

	var dx: float = player_ref.global_position.x - global_position.x
	var dir: float = sign(dx)
	if dir != 0.0:
		_sprite.flip_h = dir < 0
	# 走位模式：chase 一直追；kite 风筝走位（远程 BOSS）：太近后撤、太远靠近、舒适区悬停
	if movement == "kite":
		var dist := absf(dx)
		if dist < kite_min:
			velocity.x = -dir * speed
		elif dist > kite_max:
			velocity.x = dir * speed
		else:
			velocity.x = 0.0
	else:
		velocity.x = dir * speed

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	attack_timer -= delta
	if attack_timer <= 0.0:
		if attack_type == "melee" and _in_range(melee_range):
			_do_melee()
		elif attack_type == "ranged" and _in_range(ranged_range):
			_do_ranged()

	move_and_slide()

# ---------------------------------------------------------------------------
# 普通攻击
# ---------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# _in_range()：判断玩家是否进入给定半径（用平方距离比较，省一次开方）
#   参数：r 判定半径（像素）
#   返回值：玩家节点中心到 BOSS 中心的距离 ≤ r 时返回 true
# ----------------------------------------------------------------------------
func _in_range(r: float) -> bool:
	if r <= 0.0 or not is_instance_valid(player_ref):
		return false
	return global_position.distance_squared_to(player_ref.global_position) <= r * r

# ----------------------------------------------------------------------------
# _do_melee()：BOSS 近战普攻（直接结算，无蓄力动画）
#   先刷新攻击冷却；玩家在 melee_range 内则对玩家造成 contact_damage 伤害
# ----------------------------------------------------------------------------
func _do_melee():
	attack_timer = attack_interval
	if not _in_range(melee_range):
		return
	_hit_player(contact_damage)

# ----------------------------------------------------------------------------
# _do_ranged()：BOSS 远程普攻（本作也是直接结算伤害，无弹道）
#   玩家在 ranged_range 内则对玩家造成 contact_damage 伤害
# ----------------------------------------------------------------------------
func _do_ranged():
	attack_timer = attack_interval
	if not _in_range(ranged_range):
		return
	_hit_player(contact_damage)

# ----------------------------------------------------------------------------
# _hit_player()：统一对玩家造成伤害的入口（带死亡/停止/爬出/无效引用保护）
#   参数：dmg 本次伤害值（普攻用 contact_damage，技能用 skill_damage）
# ----------------------------------------------------------------------------
func _hit_player(dmg: int):
	if dead or stopped or rising:
		return
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		return
	if player_ref.has_method("take_damage"):
		player_ref.take_damage(dmg)

# ---------------------------------------------------------------------------
# 技能
# ---------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# _start_skill()：根据 skill_type 分派到对应技能实现
#   命中不到已知类型时（_ 分支）重置技能冷却，避免卡死无法再次释放
# ----------------------------------------------------------------------------
func _start_skill():
	_action_state = ""
	_action_progress = 0.0
	match skill_type:
		SKILL_CHARGE:
			_skill_charge()
		SKILL_SLAM:
			_skill_slam()
		SKILL_SUMMON:
			_skill_summon()
		_:
			skill_timer = skill_interval

# 冲锋：蓄力 → 高速冲刺 → 硬直收尾
# ----------------------------------------------------------------------------
# _skill_charge()：冲锋技能
#   流程（Tween 串接）：后缩下蹲蓄力(0.7s，动作层 charge_windup) → 保持(0.2s)
#         → 触发冲刺(_charge_dash 设 5 倍速 + 残影拖尾) → 冲刺 1.1s（charge 姿态）
#         → 硬直回正 0.35s（charge_recover）→ 结束。
#   冲刺阶段由物理更新负责移动，每次冲锋最多命中玩家一次。
# ----------------------------------------------------------------------------
func _skill_charge():
	skill_active = true
	skill_timer = skill_interval
	_charge_dashing = false
	_charge_hit = false
	# 没有玩家（例如刚生成 / 玩家已死亡）时放弃冲锋，避免空引用崩溃
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		skill_active = false
		return
	var dir: float = sign(player_ref.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	velocity.x = 0.0
	_skill_tween = create_tween()
	var tw := _skill_tween
	# 蓄力：后缩下蹲（动作层姿态）+ 变红，蓄力结束时脚下扬尘
	_action_state = "charge_windup"
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.7)
	tw.tween_property(_sprite, "modulate", Color(1.4, 0.5, 0.5), 0.2)
	tw.tween_interval(0.2)
	tw.tween_callback(func():
		_sprite.modulate = Color(1, 1, 1)
		_spawn_burst(Vector2(0.0, BODY_HALF_H), Color(0.55, 0.45, 0.34, 0.8), 5, 90.0)
		_charge_dash(dir)
	)
	# 冲刺（动作层前倾姿态 + 残影拖尾由物理帧处理）
	tw.tween_callback(func(): _action_state = "charge")
	tw.tween_interval(1.1)
	# 硬直回正
	tw.tween_callback(func():
		_action_state = "charge_recover"
		_action_progress = 1.0
		velocity.x = 0.0
		_charge_dashing = false
	)
	tw.tween_method(func(v: float): _action_progress = v, 1.0, 0.0, 0.35)
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _charge_dash()：进入冲刺阶段时把水平速度设为 5 倍速
#   参数：dir 朝向（1 右 / -1 左）
#   物理更新在冲刺期间执行移动与命中判定。
# ----------------------------------------------------------------------------
func _charge_dash(dir: float):
	if dead or stopped:
		skill_active = false
		return
	_charge_dashing = true
	velocity.x = dir * speed * 5.0

func _cancel_skill():
	if _skill_tween != null and _skill_tween.is_valid():
		_skill_tween.kill()
	skill_active = false
	_charge_dashing = false
	velocity = Vector2.ZERO
	if is_instance_valid(_sprite):
		_sprite.position.x = 0.0
	_action_state = ""
	_action_progress = 0.0
	# 清掉飞行中的弹体（投石/斩波），避免停止/死亡后残留
	for prj in _projectiles:
		var n := prj.get("node") as Node2D
		if n != null and is_instance_valid(n):
			n.queue_free()
	_projectiles.clear()

# ----------------------------------------------------------------------------
# _skill_slam()：震地技能
#   流程：Tween 让 BOSS 整体跃起 220px(0.45s 缓出) → 砸落回原位(0.22s 缓入)
#        → _slam_impact 生成冲击波视觉并对范围内玩家造成伤害 → 0.35s 后解除 skill_active
# ----------------------------------------------------------------------------
func _skill_slam():
	skill_active = true
	skill_timer = skill_interval
	var base_y := global_position.y
	_skill_tween = create_tween()
	var tw := _skill_tween
	# 起跳前深蹲蓄力（动作层 slam_windup）
	_action_state = "slam_windup"
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.2)
	# 跃起（slam_air：身体拉长）
	tw.tween_callback(func(): _action_state = "slam_air")
	tw.tween_property(self, "global_position:y", base_y - 220.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 砸落（slam_impact：落地压扁回弹）
	tw.tween_callback(func(): _action_state = "slam_impact")
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.22)
	tw.tween_property(self, "global_position:y", base_y, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_slam_impact)
	tw.tween_interval(0.35)
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _slam_impact()：震地落地瞬间结算
#   作用：以 radius(230px) 为半径，玩家在范围内则扣 skill_damage。
#   注意：这里只对玩家结算（不用 Explosion.damage_zombies，否则会误伤 zombies 组里的 BOSS 自己）
# ----------------------------------------------------------------------------
func _slam_impact():
	if dead or stopped:
		return
	var radius := 230.0
	# 冲击波视觉：程序化扩散圆（与 Explosion.blast 同思路，但这里只做表现）
	_spawn_shockwave(radius)
	# 落地：尘土迸发 + 地面裂纹
	_spawn_burst(Vector2(0.0, BODY_HALF_H), Color(0.55, 0.5, 0.42, 0.8), 10, 190.0)
	_spawn_ground_cracks()
	# 伤害判定只针对玩家，不用 Explosion.damage_zombies（那会打到 zombies 组里的自己）
	if is_instance_valid(player_ref) and not player_ref.is_queued_for_deletion():
		if global_position.distance_to(player_ref.global_position) <= radius and player_ref.has_method("take_damage"):
			player_ref.take_damage(skill_damage)

# ----------------------------------------------------------------------------
# _spawn_shockwave()：画一圈向外扩散并淡出的冲击波圆环（纯视觉表现，无伤害）
#   参数：radius 最终扩散半径；col 圆环颜色（震地橙黄 / 怒吼紫）
#   实现：用 tween_method 把 meta "r" 从 10 渐变到 radius，draw 回调据此重画圆弧
# ----------------------------------------------------------------------------
func _spawn_shockwave(radius: float, col := Color(1.0, 0.7, 0.3, 0.85)):
	var ring := Node2D.new()
	ring.z_index = 8
	ring.position = Vector2(0, BODY_HALF_H)
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, ring.get_meta("r", 10.0), 0, TAU, 40, col, 6.0)
	)
	add_child(ring)
	ring.set_meta("r", 10.0)
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float):
		ring.set_meta("r", v)
		ring.queue_redraw()
	, 10.0, radius, 0.35)
	tw.tween_property(ring, "modulate:a", 0.0, 0.15)
	tw.tween_callback(ring.queue_free)

# ----------------------------------------------------------------------------
# _skill_summon()：召唤技能
#   向 main.gd 发 summon_requested(3) 信号请求生成 3 只小怪；
#   自身播放一段紫色闪烁动画，期间 skill_active=true 不普攻/不追击
# ----------------------------------------------------------------------------
func _skill_summon():
	skill_active = true
	skill_timer = skill_interval
	# 动作姿态：召唤膨胀起伏
	_action_state = "summon"
	_action_progress = 0.0
	summon_requested.emit(3)
	# 脚下紫环法阵 + 紫雾上飘
	_spawn_summon_ring()
	_skill_tween = create_tween()
	var tw := _skill_tween
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.6)
	tw.tween_property(_sprite, "modulate", Color(0.8, 0.6, 1.3), 0.3)
	tw.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.3)
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _spawn_summon_ring()：召唤法阵——脚下两圈旋转的紫色弧线 + 上飘紫雾
# ----------------------------------------------------------------------------
func _spawn_summon_ring():
	var ring := Node2D.new()
	ring.z_index = 7
	ring.position = Vector2(0, BODY_HALF_H - 8.0)
	ring.draw.connect(func():
		var t := float(ring.get_meta("t", 0.0))
		ring.draw_arc(Vector2.ZERO, 62.0, t * 3.0, t * 3.0 + 4.6, 26, Color(0.75, 0.5, 1.0, 0.85), 4.0)
		ring.draw_arc(Vector2.ZERO, 42.0, -t * 2.4, -t * 2.4 + 3.4, 20, Color(0.65, 0.4, 0.95, 0.6), 3.0)
	)
	add_child(ring)
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float):
		ring.set_meta("t", v)
		ring.queue_redraw()
	, 0.0, TAU, 0.6)
	tw.tween_property(ring, "modulate:a", 0.0, 0.2)
	tw.tween_callback(ring.queue_free)
	# 紫雾上飘
	_spawn_burst(Vector2(0.0, BODY_HALF_H), Color(0.7, 0.45, 1.0, 0.5), 6, 100.0, -1.0)

# ---------------------------------------------------------------------------
# 副技能（skill2_type，独立冷却计时，与主技能并行）
# ---------------------------------------------------------------------------
func _start_skill2():
	_action_state = ""
	_action_progress = 0.0
	match skill2_type:
		SKILL2_ROAR:
			_skill_roar()
		SKILL2_ROCK:
			_skill_rock()
		SKILL2_WAVE:
			_skill_wave()
		_:
			skill2_timer = skill2_interval

# ----------------------------------------------------------------------------
# _skill_roar()：怒吼（暴食者）——膨胀蓄力 0.8s → 声波圈震退小怪 + 范围伤害玩家
# ----------------------------------------------------------------------------
func _skill_roar():
	skill_active = true
	skill2_timer = skill2_interval
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		skill_active = false
		return
	_action_state = "roar_windup"
	_skill_tween = create_tween()
	var tw := _skill_tween
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.8)
	tw.tween_callback(_roar_blast)
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _roar_blast()：怒吼释放瞬间——紫声声波圈 + 推开小怪 + 玩家范围伤害
# ----------------------------------------------------------------------------
func _roar_blast():
	if dead or stopped:
		return
	_action_state = "roar_blast"
	_action_progress = 0.0
	var radius := maxf(1.0, skill2_range)
	_spawn_shockwave(radius, Color(0.75, 0.55, 1.0, 0.85))
	if is_instance_valid(player_ref) and not player_ref.is_queued_for_deletion():
		if global_position.distance_to(player_ref.global_position) <= radius and player_ref.has_method("take_damage"):
			player_ref.take_damage(skill2_damage)
	# 推开身边小怪（不含自己，BOSS 也在 zombies 组里）
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z == self:
			continue
		var n2 := z as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_to(global_position) > radius:
			continue
		var push_dir: float = sign(n2.global_position.x - global_position.x)
		if push_dir == 0.0:
			push_dir = 1.0
		if n2 is CharacterBody2D:
			n2.velocity.x += push_dir * 240.0

# ----------------------------------------------------------------------------
# _skill_rock()：投石（绿巨人）——弯腰捡石 0.6s → 挺身甩臂 0.25s → 抛出抛物线巨石
# ----------------------------------------------------------------------------
func _skill_rock():
	skill_active = true
	skill2_timer = skill2_interval
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		skill_active = false
		return
	var dir: float = sign(player_ref.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	_action_state = "rock_windup"
	_skill_tween = create_tween()
	var tw := _skill_tween
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.6)
	tw.tween_callback(func():
		_action_state = "rock_throw"
		_action_progress = 0.0
	)
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.25)
	tw.tween_callback(func(): _throw_rock(dir))
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _throw_rock()：从 BOSS 手部附近抛出石头（程序化圆石，抛物线由 _update_projectiles 驱动）
# ----------------------------------------------------------------------------
func _throw_rock(dir: float):
	if dead or stopped:
		return
	var r := Node2D.new()
	r.z_index = 9
	r.draw.connect(func():
		var rad := float(r.get_meta("rad", 11.0))
		r.draw_circle(Vector2.ZERO, rad, Color(0.42, 0.4, 0.38, 1))
		r.draw_arc(Vector2.ZERO, rad, 0, TAU, 22, Color(0.66, 0.63, 0.58, 1), 2.5)
	)
	r.set_meta("rad", 11.0)
	r.global_position = global_position + Vector2(dir * 70.0, -150.0)
	get_parent().add_child(r)
	_projectiles.append({
		"node": r, "kind": "rock",
		"vel": Vector2(dir * 430.0, -320.0), "life": 5.0, "hit": false,
	})

# ----------------------------------------------------------------------------
# _rock_impact()：石头落地——土块迸发 + 小范围冲击波 + 范围内玩家伤害
# ----------------------------------------------------------------------------
func _rock_impact(rock: Node2D):
	if dead or stopped:
		return
	var center := rock.global_position
	var radius := maxf(1.0, skill2_range)
	_spawn_shockwave(radius, Color(0.75, 0.6, 0.35, 0.8))
	_spawn_burst(center, Color(0.55, 0.48, 0.4, 0.85), 9, 150.0)
	# 命中判定用水平距离：石头砸在脚底地面（y=GROUND_LINE），玩家身体中心高 170px，
	# 全距离判定会因垂直差永远打不到，按横版直觉改为「水平爆炸半径」。
	if is_instance_valid(player_ref) and not player_ref.is_queued_for_deletion():
		if absf(center.x - player_ref.global_position.x) <= radius and player_ref.has_method("take_damage"):
			player_ref.take_damage(skill2_damage)

# ----------------------------------------------------------------------------
# _skill_wave()：死亡斩波（收割者）——后仰举镰 0.5s → 横扫 0.25s → 甩出紫色月牙弹体
# ----------------------------------------------------------------------------
func _skill_wave():
	skill_active = true
	skill2_timer = skill2_interval
	if not is_instance_valid(player_ref) or player_ref.is_queued_for_deletion():
		skill_active = false
		return
	var dir: float = sign(player_ref.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	_action_state = "wave_windup"
	_skill_tween = create_tween()
	var tw := _skill_tween
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.5)
	tw.tween_callback(func():
		_action_state = "wave_swing"
		_action_progress = 0.0
	)
	tw.tween_method(func(v: float): _action_progress = v, 0.0, 1.0, 0.25)
	tw.tween_callback(func(): _swing_wave(dir))
	tw.tween_callback(func():
		_action_state = ""
		_action_progress = 0.0
		skill_active = false
	)

# ----------------------------------------------------------------------------
# _swing_wave()：甩出紫色月牙弹体（双弧线，命中玩家一次后消失）
# ----------------------------------------------------------------------------
func _swing_wave(dir: float):
	if dead or stopped:
		return
	var w := Node2D.new()
	w.z_index = 9
	w.draw.connect(func():
		var rad := float(w.get_meta("rad", 46.0))
		w.draw_arc(Vector2.ZERO, rad, -0.9, 0.9, 20, Color(0.72, 0.45, 1.0, 0.9), 7.0)
		w.draw_arc(Vector2.ZERO, rad * 0.62, -0.9, 0.9, 16, Color(0.78, 0.58, 1.0, 0.9), 5.0)
	)
	w.set_meta("rad", 46.0)
	w.global_position = global_position + Vector2(dir * 40.0, -60.0)
	get_parent().add_child(w)
	_projectiles.append({
		"node": w, "kind": "wave",
		"vel": Vector2(dir * 500.0, 0.0), "life": 2.0, "hit": false,
	})

# ----------------------------------------------------------------------------
# _update_projectiles()：每帧驱动弹体（投石受重力、斩波直线飞行 + 命中判定）
#   弹体生命周期结束或命中/落地后自动释放。
# ----------------------------------------------------------------------------
func _update_projectiles(delta: float):
	if _projectiles.is_empty():
		return
	var alive: Array = []
	for prj in _projectiles:
		var n := prj.get("node") as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var kind := String(prj.get("kind", ""))
		var vel: Vector2 = prj.get("vel", Vector2.ZERO)
		var life := float(prj.get("life", 0.0)) - delta
		var remove := false
		if kind == "rock":
			vel.y += 900.0 * delta
			n.global_position += vel * delta
			if n.global_position.y >= GROUND_LINE:
				_rock_impact(n)
				remove = true
		elif kind == "wave":
			n.global_position += vel * delta
			if not bool(prj.get("hit", false)) \
				and is_instance_valid(player_ref) and not player_ref.is_queued_for_deletion():
				# 命中判定用水平距离：月牙飞行高度在玩家身体范围内，垂直差不参与判定
				if absf(n.global_position.x - player_ref.global_position.x) <= 60.0:
					prj["hit"] = true
					_hit_player(skill2_damage)
					remove = true
		prj["vel"] = vel
		prj["life"] = life
		if remove or life <= 0.0:
			n.queue_free()
		else:
			alive.append(prj)
	_projectiles = alive

# ---------------------------------------------------------------------------
# 特效（纯程序化，无新美术资源）：残影 / 尘土迸发 / 地面裂纹
# ---------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# _spawn_ghost()：冲刺残影——复制当前 sprite 的半透明快照，0.25s 淡出
# ----------------------------------------------------------------------------
func _spawn_ghost():
	if _sprite == null or not is_instance_valid(_sprite) or _sprite.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = _sprite.texture
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	g.flip_h = _sprite.flip_h
	g.scale = _sprite.scale
	g.position = _sprite.position
	g.rotation = _sprite.rotation
	g.modulate = Color(1, 1, 1, 0.32)
	g.z_index = 5
	_sprite.get_parent().add_child(g)
	var tw: Tween = g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.25)
	tw.tween_callback(g.queue_free)

# ----------------------------------------------------------------------------
# _spawn_burst()：程序化小块迸发（尘土/碎石/紫雾通用）
#   参数：pos 局部坐标（相对 BOSS）；col 颜色；count 数量；speed 速度；
#         dir_y 垂直方向系数（1 向下/向四周，-1 上飘）
# ----------------------------------------------------------------------------
func _spawn_burst(pos: Vector2, col: Color, count: int, speed: float, dir_y := 1.0):
	for i in range(count):
		var p := Node2D.new()
		p.z_index = 6
		var ang := randf_range(0.0, TAU)
		var spd := randf_range(speed * 0.4, speed)
		var vel := Vector2(cos(ang) * (1.0 if dir_y > 0.0 else 0.55), sin(ang) * dir_y) * spd
		var sz := randf_range(3.0, 7.0)
		var dur := randf_range(0.35, 0.6)
		p.position = pos
		p.draw.connect(func():
			var r := float(p.get_meta("r", 4.0))
			var c: Color = p.get_meta("c", Color(0.6, 0.5, 0.4, 0.6))
			p.draw_rect(Rect2(-r * 0.5, -r * 0.5, r, r), c)
		)
		p.set_meta("r", sz)
		p.set_meta("c", Color(col.r, col.g, col.b, randf_range(0.4, 0.8)))
		add_child(p)
		var tw: Tween = p.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", p.position + vel * dur, dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(p.queue_free)

# ----------------------------------------------------------------------------
# _spawn_ground_cracks()：震地落地后地面裂纹——脚下向两侧各 3 条锯齿短线，短留后淡出
# ----------------------------------------------------------------------------
func _spawn_ground_cracks():
	var cracks := Node2D.new()
	cracks.z_index = 6
	var lines: Array = []
	for side in [-1.0, 1.0]:
		for i in range(3):
			var p := Vector2(side * (12.0 + i * 22.0), BODY_HALF_H + 2.0)
			var line: Array = [p]
			for j in range(4):
				p += Vector2(side * randf_range(8.0, 16.0), randf_range(-2.0, 4.0))
				line.append(p)
			lines.append(line)
	cracks.draw.connect(func():
		for line in lines:
			cracks.draw_polyline(PackedVector2Array(line), Color(0.3, 0.28, 0.24, 0.7), 2.0)
	)
	add_child(cracks)
	var tw: Tween = cracks.create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(cracks, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cracks.queue_free)

# ---------------------------------------------------------------------------
# 受击 / 死亡
# ---------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# take_damage()：BOSS 受伤/死亡结算（与普通丧尸同思路，但额外广播 health_changed 信号）
#   参数：amount 受到的伤害
#   作用：扣血 → 弹伤害数字 → 刷新头顶血条并广播 health_changed（供顶部大血条）
#         血量 ≤ 0 时置 dead/stopped、移出 zombies 组、发 died 信号并释放节点
# ----------------------------------------------------------------------------
func take_damage(amount):
	if dead or is_queued_for_deletion() or amount <= 0:
		return
	health -= amount
	_spawn_damage_number(int(amount))
	if is_instance_valid(_health_bar):
		_health_bar.queue_redraw()
	health_changed.emit(maxi(health, 0), max_health)
	if health <= 0:
		dead = true
		stopped = true
		_cancel_skill()
		velocity = Vector2.ZERO
		set_physics_process(false)
		remove_from_group("zombies")
		if _hit_flash != null and _hit_flash.is_valid():
			_hit_flash.kill()
		died.emit(global_position)
		queue_free()
		return
	if _hit_flash != null and _hit_flash.is_valid():
		_hit_flash.kill()
	_sprite.modulate = Color(1, 0.3, 0.3)
	_hit_flash = create_tween()
	_hit_flash.tween_interval(0.08)
	_hit_flash.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.0)

# ----------------------------------------------------------------------------
# stop_moving()：游戏结束时让 BOSS 停下（player.gd 的 _show_game_over 会遍历 zombies 组调用）
# ----------------------------------------------------------------------------
func stop_moving():
	stopped = true
	_cancel_skill()
	velocity = Vector2.ZERO

# ---------------------------------------------------------------------------
# 表现：头顶血条 + 伤害数字（与 zombie.gd 同风格，尺寸更大）
# ---------------------------------------------------------------------------
func _draw_health_bar():
	if _health_bar == null or max_health <= 0:
		return
	var w := 96.0
	var h := 10.0
	var ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var p := Vector2(-w / 2.0, _head_top - 20.0)
	_health_bar.draw_rect(Rect2(p, Vector2(w, h)), Color(0.25, 0.05, 0.05, 0.9))
	var col: Color = Color(0.3, 0.9, 0.4)
	if ratio < 0.25:
		col = Color(0.95, 0.25, 0.25)
	elif ratio < 0.5:
		col = Color(0.95, 0.8, 0.2)
	_health_bar.draw_rect(Rect2(p, Vector2(w * ratio, h)), col)
	_health_bar.draw_rect(Rect2(p, Vector2(w, h)), Color(0, 0, 0, 1), false, 1.0)

func _spawn_damage_number(amount: int):
	var lbl := Label.new()
	lbl.text = str(amount)
	var st := LabelSettings.new()
	st.font_size = 26
	st.font_color = Color(1, 0.95, 0.4)
	st.outline_size = 4
	st.outline_color = Color(0, 0, 0, 1)
	lbl.label_settings = st
	lbl.z_index = 24
	lbl.position = Vector2(_dmg_seq % 3 * 12.0 - 12.0, _head_top - 40.0)
	_dmg_seq += 1
	add_child(lbl)
	_dmg_labels.append(lbl)
	var tw: Tween = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 40.0, 0.6)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
		_dmg_labels.erase(lbl)
	)
