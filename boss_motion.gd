extends Node2D

# ============================================================================
# boss_motion.gd —— BOSS 程序化动作层（移动姿态 + 技能姿态）
# ----------------------------------------------------------------------------
# 为什么不用丧尸那套 GPU 骨骼蒙皮（zombie_motion.gd）：
#   · 暴食者/绿巨人/收割者是 3 张形态差异极大的站姿大立绘，收割者穿长袍持镰刀
#     （腿部不可见），量骨骼锚点性价比低、长袍做腿部 IK 没有意义。
#   · BOSS 每关只有 1 只，要的是「有重量感的走姿 + 技能可读的蓄力/释放」，
#     用 Transform 参数化（起伏/摇摆/前倾/压扁回弹/尘土）即可达成，零新美术资源。
# ----------------------------------------------------------------------------
# 用法（boss.gd）：
#   _motion.configure(_sprite, 脚底y偏移)
#   每帧 _motion.advance(delta, distance, state, progress, motion_cfg)
#     · distance : 本帧实际水平移动距离（走路相位按真实位移推进，站住不空走）
#     · state    : "walk"/"idle" 或技能姿态名
#                  （charge_windup/charge/charge_recover、slam_windup/slam_air/slam_impact、
#                   summon、roar_windup/roar_blast、rock_windup/rock_throw、wave_windup/wave_swing）
#     · progress : 技能进度 0~1（Tween 驱动，供蓄力/回弹曲线使用）
#     · cfg      : boss_catalog.gd 里 DEFINITIONS[id].motion 参数表
# 姿态由 _apply() 写入目标 Sprite 的 transform，朝向翻转时自动镜像对称。
#
# motion 参数表字段：
#   style      走路风格 "heavy"沉重 / "proud"稳健 / "float"漂浮（收割者）
#   stride     一步的像素距离（一个走路周期 = 左右各一步 = stride×2）
#   bob        垂直起伏幅度(px)
#   sway       左右摇摆幅度(rad)
#   lean       前进方向前倾幅度(rad)
#   step_dust  每步脚下尘土粒子数（0 关闭）
#   dust_color 尘土颜色
#   float_amp  漂浮起伏幅度(px，float 风格用)
#   float_speed 漂浮频率(Hz)
# ============================================================================

var target: Sprite2D = null
var _feet_y := 170.0        # 脚底相对 Boss 中心的 y 偏移（尘土喷出位置）
var _cfg: Dictionary = {}
var _phase := 0.0           # 走路循环相位（弧度），按移动距离推进
var _last_step_i := 0       # 上一步跨过的半步计数（检测「跨步」触发尘土）
var _clock := 0.0           # 全局时钟（漂浮/抖动用）
var _walk_blend := 0.0      # 走路权重（0 站立 ~ 1 行走，平滑过渡）
var _bob := 0.0             # 垂直起伏（px，向下为正）
var _sway := 0.0            # 左右摇摆（rad）
var _lean := 0.0            # 前进方向前倾（rad）
var _squash := 0.0          # 压扁系数：>0 压扁（变宽变矮）/ <0 拉长（变窄变高）


func configure(sprite: Sprite2D, feet_y: float) -> void:
	target = sprite
	_feet_y = feet_y


# 每帧由 boss.gd 调用一次
func advance(delta: float, distance: float, state: String, progress: float, cfg: Dictionary) -> void:
	_clock += delta
	_cfg = cfg
	var style := String(cfg.get("style", "heavy"))
	var moving := state == "walk" and distance > 0.001

	# ---- 走路相位：按真实位移推进，一个周期 = 左右各一步 ----
	if moving:
		var step := float(cfg.get("stride", 80.0))
		_phase = fposmod(_phase + distance / maxf(1.0, step * 2.0) * TAU, TAU)
		_walk_blend = move_toward(_walk_blend, 1.0, delta * 8.0)
	else:
		_walk_blend = move_toward(_walk_blend, 0.0, delta * 8.0)

	# ---- 走路基础姿态（heavy/proud 共用，幅度不同）----
	_bob = float(cfg.get("bob", 4.0)) * sin(_phase) * _walk_blend
	_sway = float(cfg.get("sway", 0.025)) * sin(_phase * 0.5) * _walk_blend
	_lean = float(cfg.get("lean", 0.05)) * _walk_blend
	_squash = 0.0

	# ---- 漂浮（收割者）：不走路，改为整体浮沉 + 轻微横摆 ----
	if style == "float":
		var amp := float(cfg.get("float_amp", 9.0))
		var spd := float(cfg.get("float_speed", 2.0))
		_bob = sin(_clock * spd * TAU) * amp
		_sway = sin(_clock * spd * 0.5 * TAU) * float(cfg.get("sway", 0.02))
		_lean = 0.0

	# ---- 技能姿态覆盖（蓄力/释放/硬直）----
	if state != "walk" and state != "idle":
		_apply_skill_pose(state, progress)

	# ---- 跨步尘土（只在正常走路时喷，技能阶段不喷）----
	if moving and int(_cfg.get("step_dust", 0)) > 0:
		var half := int(_phase / (TAU * 0.5))          # 0..3，每半周期=一步
		if half != _last_step_i:
			_last_step_i = half
			_spawn_step_dust()

	_apply()


# ----------------------------------------------------------------------------
# 技能姿态：按 state 覆盖基础姿态。progress 0~1 由 boss.gd 的 Tween 驱动。
#   约定：数值很小（rad/px 级），避免幅度过大把立绘甩出碰撞体。
# ----------------------------------------------------------------------------
func _apply_skill_pose(state: String, progress: float) -> void:
	match state:
		"charge_windup":
			# 冲锋蓄力：后缩下蹲 + 抖动，越接近释放抖得越狠
			var t := clampf(progress, 0.0, 1.0)
			_bob += 14.0 * t
			_lean += -0.07 * t
			_squash += 0.07 * t
			_bob += absf(sin(_clock * 22.0)) * 2.0 * t
		"charge":
			# 冲刺：大幅前倾压低身体，贴地感
			_lean += 0.16
			_bob += 6.0
			_squash += 0.05
		"charge_recover":
			# 撞墙/收尾硬直：摇头晃脑回正
			var t := 1.0 - clampf(progress, 0.0, 1.0)
			_lean += 0.10 * t
			_bob += absf(sin(_clock * 30.0)) * 5.0 * t
		"slam_windup":
			# 震地起跳前：深蹲蓄力
			var t := clampf(progress, 0.0, 1.0)
			_bob += 14.0 * t
			_squash += 0.09 * t
		"slam_air":
			# 空中：身体拉长（反压扁）+ 蜷缩微收
			_squash += -0.10
			_lean += 0.02
		"slam_impact":
			# 落地：压扁 → 回弹（0→1 曲线）
			var t := clampf(progress, 0.0, 1.0)
			_squash += lerpf(0.20, -0.06, smoothstep(0.0, 1.0, t))
		"summon":
			# 召唤：身体膨胀起伏 + 轻摆（配合脚下紫环）
			var t := clampf(progress, 0.0, 1.0)
			_squash += 0.06 * sin(t * PI)
			_bob += 8.0 * sin(t * PI)
			_sway += 0.03 * sin(t * PI)
		"roar_windup":
			# 怒吼蓄力：膨胀 + 高频抖动
			var t := clampf(progress, 0.0, 1.0)
			_squash += 0.10 * t
			_bob += absf(sin(_clock * 20.0)) * 3.0 * t
		"roar_blast":
			# 怒吼释放：前倾发力
			var t := clampf(progress, 0.0, 1.0)
			_lean += lerpf(0.0, 0.10, t)
			_bob += 4.0 * (1.0 - t)
		"rock_windup":
			# 投石蓄力：弯腰捡石
			var t := clampf(progress, 0.0, 1.0)
			_lean += -0.18 * t
			_bob += 10.0 * t
		"rock_throw":
			# 投石出手：弯腰 → 挺身甩臂
			var t := clampf(progress, 0.0, 1.0)
			_lean += lerpf(-0.18, 0.14, smoothstep(0.0, 1.0, t))
		"wave_windup":
			# 斩波蓄力：后仰举镰
			var t := clampf(progress, 0.0, 1.0)
			_lean += -0.10 * t
			_bob += 6.0 * t
		"wave_swing":
			# 斩波挥出：前倾横扫
			var t := clampf(progress, 0.0, 1.0)
			_lean += lerpf(-0.10, 0.15, smoothstep(0.0, 1.0, t))
			_sway += 0.06 * sin(t * PI)


# ----------------------------------------------------------------------------
# _apply()：把姿态写入目标 Sprite 的 transform。
#   朝向（flip_h）镜像时旋转符号取反，保证「面朝方向前倾」恒成立。
# ----------------------------------------------------------------------------
func _apply() -> void:
	if target == null:
		return
	var dir := 1.0 if not target.flip_h else -1.0
	target.position.y = _bob
	target.rotation = (_sway + _lean) * dir
	# 压扁/拉长：只改 scale 幅度。Boss 朝向由 flip_h 标志控制（scale 恒正），
	# 这里保留幅度、不改符号，避免与 flip 双重镜像。
	var sx := absf(target.scale.x)
	var sy := absf(target.scale.y)
	var s := clampf(_squash, -0.25, 0.25)
	target.scale = Vector2(sx * (1.0 + s), sy * (1.0 - s))


# ----------------------------------------------------------------------------
# _spawn_step_dust()：脚下喷 1~3 个土块小方块，上飘 + 散开 + 淡出（纯程序化）
# ----------------------------------------------------------------------------
func _spawn_step_dust() -> void:
	var count := int(_cfg.get("step_dust", 0))
	if count <= 0 or target == null or not target.is_inside_tree():
		return
	var parent := target.get_parent()
	var base_col: Color = _cfg.get("dust_color", Color(0.58, 0.48, 0.34, 0.8))
	for i in range(count):
		var p := Node2D.new()
		p.z_index = 6
		var spread := randf_range(-16.0, 16.0)
		var rise := randf_range(-24.0, -9.0)
		var sz := randf_range(2.5, 6.0)
		var dur := randf_range(0.35, 0.6)
		var col: Color = Color(base_col.r, base_col.g, base_col.b, randf_range(0.35, 0.7))
		p.position = Vector2(spread * 0.35, _feet_y + randf_range(0.0, 6.0))
		p.draw.connect(func():
			var r := float(p.get_meta("r", 4.0))
			var c: Color = p.get_meta("c", Color(0.6, 0.5, 0.4, 0.6))
			p.draw_rect(Rect2(-r * 0.5, -r * 0.5, r, r), c)
		)
		p.set_meta("r", sz)
		p.set_meta("c", col)
		parent.add_child(p)
		var tw: Tween = p.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", p.position + Vector2(spread, rise), dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(p.queue_free)
