extends Node2D

# ============================================================================
# zombie_acid.gd —— 腐蚀者的酸液攻击（抛物线 + 落地残留）
# ----------------------------------------------------------------------------
# 英文注释机翻：「先亮落点，再飞行，最后生成短时地面酸液；发射后落点不追踪玩家。」
#
# 【⚠️ 这个文件里没有血量、也没有攻击间隔】
#   血量在 zombie_catalog.gd 的 max_health；
#   攻击间隔在 zombie_catalog.gd 的 attack_interval；
#   这里的常量是「酸液自身的参数」，两者不是一回事，别混淆。
#
# 【生命周期的三个阶段】
#   1) 预警（0 ~ FLIGHT 秒）：地上画出绿色预警圈，告诉玩家酸液要落在这
#   2) 飞行（0 ~ FLIGHT 秒）：酸液从发射点沿抛物线飞向落点
#   3) 残留（FLIGHT ~ FLIGHT+PUDDLE_LIFE 秒）：落地成一滩酸，
#      站在里面会持续掉血，酸液本身有 0.8 秒掉血冷却（damage_timer）
#   总时长 = FLIGHT + PUDDLE_LIFE，到时自动销毁。
#   ⚠️ 落点在发射那一刻就**锁定**，不追踪玩家——所以可以走开躲掉。
#
# 【想改的地方】
#   酸液飞得更快/更慢     → FLIGHT
#   地上的酸渍留多久       → PUDDLE_LIFE
#   酸渍范围多大           → RADIUS
#   一次掉多少血           → _physics_process 里的 take_damage(8) 那个 8
#   多久能掉一次血         → damage_timer=.8 那个 0.8（秒）
# ============================================================================

const FLIGHT := .9         # 酸液从发射到落地的飞行时间（秒），也是预警圈显示时长
const PUDDLE_LIFE := 3.5   # 落地后酸渍残留多久（秒）
const RADIUS := 44.0       # 酸渍半径（像素），玩家脚部落在此范围内就会掉血
var player: Node2D         # 被瞄准的玩家（死亡或消失则本酸液销毁）
var origin := Vector2.ZERO  # 发射起点（丧尸嘴部位置）
var target := Vector2.ZERO  # 落点（发射时锁定，不追踪）
var elapsed := 0.0          # 已经过时间（秒），用它判断处于哪个阶段
var damage_timer := 0.0     # 掉血冷却计时（归零后才能再次造成伤害）

func setup(from: Vector2, landing: Vector2, victim: Node2D):
	origin=from
	target=landing
	player=victim
	z_index=4
	add_to_group("enemy_hazards")

func stop_moving():
	set_physics_process(false)
	queue_free()

func _physics_process(delta: float):
	if not is_instance_valid(player) or player.is_queued_for_deletion() or player.get("dead")==true:
		queue_free()
		return
	elapsed+=delta
	if elapsed>=FLIGHT+PUDDLE_LIFE:
		queue_free()
		return
	if elapsed>=FLIGHT:
		damage_timer-=delta
		# 判断脚底高度。空中越过酸液不会受伤，落进酸液才会扣血。
		var feet: Vector2=player.global_position+Vector2(0,90)
		if damage_timer<=0 and absf(feet.x-target.x)<=RADIUS and absf(feet.y-target.y)<=18:
			player.take_damage(8)
			damage_timer=.8
	queue_redraw()

func _draw():
	var landing := to_local(target)
	var active := elapsed>=FLIGHT
	var alpha := clampf((FLIGHT+PUDDLE_LIFE-elapsed)/.6,0,1)
	draw_set_transform(landing,0,Vector2(1,.23))
	draw_circle(Vector2.ZERO,RADIUS,Color(.28,.62,.06,(.72 if active else .12)*alpha))
	draw_arc(Vector2.ZERO,RADIUS,0,TAU,48,Color(.7,1,.3,.85*alpha),3,true)
	if active:
		for i in range(6):
			var a := float(i)*2.4+elapsed*.7
			draw_circle(Vector2(cos(a)*25,sin(a*1.3)*19),3+sin(elapsed*4+i),Color(.7,.95,.2,.6*alpha))
	draw_set_transform(Vector2.ZERO)
	if not active:
		var t := clampf(elapsed/FLIGHT,0,1)
		var point := to_local(origin.lerp(target,t)+Vector2(0,-90*sin(PI*t)))
		draw_circle(point,8,Color(.27,.5,.04))
		draw_circle(point,5,Color(.7,1,.25))
