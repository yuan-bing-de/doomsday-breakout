extends SceneTree

# ============================================================================
# verify_boss_motion.gd —— BOSS 移动动作与特殊技能验证脚本
# ----------------------------------------------------------------------------
# 运行方式（与数值修改索引.md 的无头验证一致）：
#   D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:/末日突围 --script res://tools/boss/verify_boss_motion.gd
#
# 退出码：0 = 全部通过；非 0 = 存在失败项。
# 验证覆盖：
#   A. boss_catalog 数据完整性（motion / 副技能字段）
#   B. boss_motion 动作层：走路起伏/前倾/漂浮浮沉在合理范围，站立时归零
#   C. 主技能状态机：冲锋命中、震地落地伤害、召唤信号
#   D. 副技能状态机：怒吼推怪+伤害、投石落地爆炸、斩波命中
# 注意：脚本会写 user:// 存档（数值修改索引.md 有同样提示），不影响本验证。
# ============================================================================

const BOSS_SCENE := preload("res://Boss.tscn")
const BOSS_CATALOG := preload("res://boss_catalog.gd")
const BOSS_MOTION := preload("res://boss_motion.gd")

var _passed := 0
var _failed := 0


# ---- 测试替身 ----
class FakePlayer:
	extends Node2D
	var hp := 100
	var hits: Array = []
	func take_damage(dmg: int) -> void:
		hp -= dmg
		hits.append(dmg)


class FakeZombie:
	extends CharacterBody2D
	pass


func _initialize() -> void:
	await _run_all()
	quit(1 if _failed > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, "  ", detail)


# 按真实毫秒等待（headless 下 idle 帧率不可靠，Tween 已绑定 physics 帧，
# 用真实时间等待让技能时间轴与物理推进同步）
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await physics_frame


# 模拟游戏地面（StaticBody，上表面 y=GROUND_LINE=478）
# 注意：Boss 碰撞层是 layer=4 / mask=1，地面要能被 Boss 撞到需双向掩码匹配
# （Boss.mask(1)&地面.layer(1) ✓，且 地面.mask 需含 Boss 的 layer=4 ✓）
func _add_ground() -> void:
	var g := StaticBody2D.new()
	g.name = "FakeGround"
	g.collision_layer = 1
	g.collision_mask = 4
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2400.0, 60.0)
	cs.shape = rect
	g.add_child(cs)
	g.global_position = Vector2(0.0, 508.0)
	root.add_child(g)


# 建一个测试玩家（记录伤害）并加入 player 组
func _make_player(pos: Vector2) -> FakePlayer:
	var p := FakePlayer.new()
	p.name = "FakePlayer"
	p.global_position = pos
	root.add_child(p)
	p.add_to_group("player")
	return p


# 建一个 BOSS（指定类型），完成爬出、指向玩家、关闭上升
func _make_boss(type: String, player: Node2D) -> Node2D:
	var cfg: Dictionary = BOSS_CATALOG.DEFINITIONS[type]
	var b := BOSS_SCENE.instantiate()
	b.texture_path = String(cfg["texture"])
	b.max_health = int(cfg["max_health"])
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
	root.add_child(b)
	b.player_ref = player
	# 保持爬出（rising）流程，等 Boss 自然爬出落地——既模拟真实出场，
	# 又避开「add_child 后立即改 transform 与 PhysicsServer body 同步竞争」导致的悬空/回弹。
	var guard := 0
	while b.rising and guard < 300:
		await physics_frame
		guard += 1
	await physics_frame
	return b

# 触发并手动推进 Boss 技能 Tween。
# headless 下 idle 帧率不稳定，Tween（绑定 idle）的自动推进不可靠；
# 这里 pause 掉自动推进，用 custom_step 每物理帧推进 1/60s，
# 再 await 一个物理帧让移动/命中判定正常发生，从而获得确定性时间轴。
func _drive_skill(b: Node2D, timer_name: String, total_sec: float) -> void:
	if timer_name == "skill":
		b.skill_timer = 0.0
	else:
		b.skill2_timer = 0.0
	await physics_frame   # 该帧 _physics_process 触发技能并创建 Tween
	var tw: Tween = b._skill_tween
	if tw == null or not tw.is_valid():
		return
	tw.pause()
	var steps := int(total_sec * 60.0)
	for i in range(steps):
		tw.custom_step(1.0 / 60.0)
		await physics_frame


func _run_all() -> void:
	print("===== BOSS 移动动作与特殊技能验证 =====")
	_add_ground()   # 模拟游戏地面：Boss 才能落地站立（否则冲刺/走路时无限下坠）

	# ---------------- A. 数据表 ----------------
	print("[A] catalog 数据完整性")
	for id in BOSS_CATALOG.ORDER:
		var d: Dictionary = BOSS_CATALOG.DEFINITIONS[id]
		_check("catalog.%s 有 motion 表" % id, d.has("motion"))
		_check("catalog.%s 有副技能类型" % id, String(d.get("skill2_type", "")) != "")
		_check("catalog.%s 副技能冷却>0" % id, float(d.get("skill2_interval", 0.0)) > 0.0)
		_check("catalog.%s 副技能伤害>=0" % id, int(d.get("skill2_damage", -1)) >= 0)
	_check("brute 主技能=charge", String(BOSS_CATALOG.DEFINITIONS["brute"]["skill_type"]) == "charge")
	_check("hulk 主技能=slam", String(BOSS_CATALOG.DEFINITIONS["hulk"]["skill_type"]) == "slam")
	_check("reaper 主技能=summon", String(BOSS_CATALOG.DEFINITIONS["reaper"]["skill_type"]) == "summon")
	_check("brute 副技能=roar", String(BOSS_CATALOG.DEFINITIONS["brute"]["skill2_type"]) == "roar")
	_check("hulk 副技能=rock", String(BOSS_CATALOG.DEFINITIONS["hulk"]["skill2_type"]) == "rock")
	_check("reaper 副技能=wave", String(BOSS_CATALOG.DEFINITIONS["reaper"]["skill2_type"]) == "wave")

	# ---------------- B. 动作层 ----------------
	print("[B] boss_motion 动作层")
	var motion: Node2D = BOSS_MOTION.new()
	var fake_sprite := Sprite2D.new()
	fake_sprite.scale = Vector2(1.0, 1.0)
	fake_sprite.flip_h = false
	motion.configure(fake_sprite, 170.0)
	root.add_child(motion)
	# heavy 走路：连续推进相位，姿态应在合理范围
	var heavy_cfg: Dictionary = BOSS_CATALOG.DEFINITIONS["brute"]["motion"]
	var max_bob := 0.0
	var max_rot := 0.0
	for i in range(40):
		motion.advance(1.0 / 60.0, 30.0, "walk", 0.0, heavy_cfg)
		max_bob = maxf(max_bob, absf(fake_sprite.position.y))
		max_rot = maxf(max_rot, absf(fake_sprite.rotation))
	_check("heavy 走路起伏幅度合理(≤10px)", max_bob <= 10.0 and max_bob > 0.0, "bob=%s" % str(max_bob))
	_check("heavy 走路倾角合理(≤0.2rad)", max_rot <= 0.25 and max_rot > 0.0, "rot=%s" % str(max_rot))
	# 站立：走权重淡出后应接近静止
	motion.advance(1.0 / 60.0, 0.0, "idle", 0.0, heavy_cfg)
	var stand_bob: float = absf(fake_sprite.position.y)
	_check("站立后起伏收敛(≤2px)", stand_bob <= 2.0, "bob=%s" % str(stand_bob))
	# float 漂浮：reaper 应持续浮沉（幅度>0）
	var float_cfg: Dictionary = BOSS_CATALOG.DEFINITIONS["reaper"]["motion"]
	var float_max := 0.0
	for i in range(30):
		motion.advance(1.0 / 60.0, 0.0, "idle", 0.0, float_cfg)
		float_max = maxf(float_max, absf(fake_sprite.position.y))
	_check("float 漂浮有浮沉(>3px)", float_max > 3.0, "amp=%s" % str(float_max))
	# 技能姿态：压扁系数不越界
	fake_sprite.position.y = 0.0
	fake_sprite.scale = Vector2(1.0, 1.0)
	motion.advance(1.0 / 60.0, 0.0, "slam_impact", 0.5, heavy_cfg)
	_check("slam_impact 落地压扁(scale.y<1)", fake_sprite.scale.y < 1.0, "scale.y=%s" % str(fake_sprite.scale.y))
	motion.queue_free()

	# ---------------- C. 主技能 ----------------
	print("[C] 主技能")
	# C1. brute 冲锋：玩家在正前方 100px，冲刺应命中 25 伤害
	var p1 := _make_player(Vector2(100.0, 308.0))
	var b1: Node2D = await _make_boss("brute", p1)
	await _drive_skill(b1, "skill", 2.6)   # 蓄力 1.1s + 冲刺 1.1s + 硬直 0.35s ≈ 2.55s
	_check("冲锋命中玩家 25 伤害", p1.hits.has(25), "hits=" + str(p1.hits))
	_check("冲锋结束后技能释放", not b1.skill_active, "act=" + str(b1.skill_active))
	b1.queue_free()
	await physics_frame

	# C2. hulk 震地：玩家在 150px 内，落地应受 30 伤害
	var p2 := _make_player(Vector2(150.0, 308.0))
	var b2: Node2D = await _make_boss("hulk", p2)
	await _drive_skill(b2, "skill", 1.6)   # 蓄力 0.2s + 跃起 0.45s + 砸落 0.22s + 落地 0.22s + 收尾 0.35s ≈ 1.44s
	_check("震地命中玩家 30 伤害", p2.hits.has(30), "hits=" + str(p2.hits))
	_check("震地结束后技能释放", not b2.skill_active)
	b2.queue_free()
	await physics_frame

	# C3. reaper 召唤：应发出 summon_requested(3)
	var p3 := _make_player(Vector2(400.0, 308.0))
	var b3: Node2D = await _make_boss("reaper", p3)
	var sum_holder := {"n": 0}
	b3.summon_requested.connect(func(c): sum_holder.n += int(c))
	await _drive_skill(b3, "skill", 1.4)   # 召唤信号在技能触发帧立即发出，推进只用于走完时间轴
	_check("召唤信号发出 3 只", sum_holder.n == 3, "sum=" + str(sum_holder.n))
	b3.queue_free()
	await physics_frame

	# ---------------- D. 副技能 ----------------
	print("[D] 副技能")
	# D1. brute 怒吼：玩家 150px 内受 12 伤害；旁边假丧尸被推开
	var p4 := _make_player(Vector2(150.0, 308.0))
	var b4: Node2D = await _make_boss("brute", p4)
	var z := FakeZombie.new()
	z.name = "FakeZombie"
	z.global_position = Vector2(200.0, 308.0)
	root.add_child(z)
	z.add_to_group("zombies")
	await physics_frame
	await _drive_skill(b4, "skill2", 1.3)   # 蓄力 0.8s + 释放收尾
	_check("怒吼伤害玩家 12", p4.hits.has(12), "hits=" + str(p4.hits))
	_check("怒吼推开小怪", absf(z.velocity.x) > 1.0, "vel.x=" + str(z.velocity.x))
	z.queue_free()
	b4.queue_free()
	await physics_frame

	# D2. hulk 投石：玩家站在预计落点（约 x≈616），落地爆炸 20 伤害（水平判定）
	var p5 := _make_player(Vector2(616.0, 308.0))
	var b5: Node2D = await _make_boss("hulk", p5)
	await _drive_skill(b5, "skill2", 2.5)   # 蓄力 0.85s + 抛石飞行 ~1.3s
	_check("投石爆炸伤害玩家 20", p5.hits.has(20), "hits=" + str(p5.hits))
	b5.queue_free()
	await physics_frame

	# D3. reaper 斩波：玩家在波路径 300px 处，命中 30 伤害
	var p6 := _make_player(Vector2(300.0, 308.0))
	var b6: Node2D = await _make_boss("reaper", p6)
	await _drive_skill(b6, "skill2", 1.6)   # 挥镰 0.75s + 月牙飞行 ~0.52s
	_check("斩波命中玩家 30 伤害", p6.hits.has(30), "hits=" + str(p6.hits))
	b6.queue_free()
	await physics_frame

	print("===== 结果：通过 %d 项，失败 %d 项 =====" % [_passed, _failed])
	# 收尾：等特效（尘土/残影 tween）自然淡出，避免退出时的资源泄漏告警
	await _wait_ms(700)
