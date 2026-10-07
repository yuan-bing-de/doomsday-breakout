extends Node2D
# 由丧尸的物理帧驱动，全部技能随暂停/死亡/结算停止，没有独立计时协程。
const ACID = preload("res://zombie_acid.gd")
var z
var state := "idle"
var remaining := 0.0
var cooldown := 1.0
var facing := 1.0
var charge_hit := false
var target_point := Vector2.ZERO
var warning: Label
var pulse := 0.0
var armor_flash := 0.0

func _ready():
	z = get_parent()
	z_index = 10
	warning = Label.new()
	warning.position = Vector2(-110,z._head_top-56)
	warning.size = Vector2(220,24)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_font_size_override("font_size",14)
	warning.add_theme_color_override("font_outline_color",Color.BLACK)
	warning.add_theme_constant_override("outline_size",5)
	add_child(warning)

func _start(next: String, duration: float, text: String, color: Color):
	state = next
	remaining = duration
	z.is_attacking = true
	facing = -1.0 if z.player_ref.global_position.x < z.global_position.x else 1.0
	z.sprite.flip_h = facing < 0
	warning.text = text
	warning.modulate = color

func _finish(delay: float):
	state = "idle"
	cooldown = delay
	z.is_attacking = false
	z.sprite.position = Vector2(0,z.sprite_ground_offset)
	z.sprite.scale = z.sprite_base_scale
	warning.text = ""
	queue_redraw()

func cancel():
	_finish(1.0)
	hide()

func tick(delta: float) -> bool:
	pulse += delta
	armor_flash = maxf(0,armor_flash-delta)
	cooldown = maxf(0,cooldown-delta)
	queue_redraw()
	if not is_instance_valid(z.player_ref) or z.player_ref.is_queued_for_deletion() or z.player_ref.get("dead") == true:
		if state != "idle": _finish(1.0)
		return false
	var gap: Vector2 = z.player_ref.global_position-z.global_position
	if state == "idle":
		if cooldown > 0 or z.is_attacking:
			return false
		# 屏幕外不提前蓄力；玩家必须能看到预警。
		var screen: Vector2 = z.get_global_transform_with_canvas().origin
		if not get_viewport_rect().grow(-24).has_point(screen):
			return false
		match z.zombie_type:
			"runner":
				if absf(gap.x) >= 110 and absf(gap.x) <= 290 and absf(gap.y)<100:
					_start("charge_windup",.65,"突进 · 准备跳跃",Color(1,.45,.35))
			"spitter":
				if absf(gap.x) <= z.ranged_range and absf(gap.y)<190:
					target_point = Vector2(z.player_ref.global_position.x,z.STAND_Y+z.SOLE_OFFSET)
					_start("spit_windup",.7,"酸液 · 离开绿圈",Color(.65,1,.3))
			"volatile":
				if gap.length() <= 125:
					_start("fuse",1.2,"蓄爆！远离 / 击杀",Color(1,.65,.2))
			"howler":
				if gap.length()<=480 and not _allies().is_empty():
					_start("howl_windup",.9,"嚎叫 · 优先击杀",Color(.85,.6,1))
		if state == "idle":
			return false
		# 开始蓄力这一帧不扣时长，确保完整的躲避时间。
		z.velocity.x = 0
		return true

	remaining -= delta
	z.velocity.x = 0
	match state:
		"charge_windup":
			if remaining <= 0:
				state = "charge"
				remaining = .68
				charge_hit = false
				warning.text = "突进！"
		"charge":
			z.velocity.x = facing*360.0
			# 扫过本帧路径，低帧率也不会穿过玩家却漏判；跳跃可躲。
			var start_x: float = z.global_position.x
			var end_x: float = start_x+z.velocity.x*delta
			var px: float = z.player_ref.global_position.x
			if not charge_hit and px>=minf(start_x,end_x)-42 and px<=maxf(start_x,end_x)+42 and absf(gap.y)<65:
				z.player_ref.take_damage(12)
				charge_hit = true
			if remaining<=0:
				z.velocity.x=0
				state="recovery"
				remaining=.6
				warning.text="喘息"
		"recovery":
			if remaining<=0: _finish(4.5)
		"spit_windup":
			if remaining<=0:
				var acid = ACID.new()
				z.get_parent().add_child(acid)
				z.start_spit_release()
				acid.setup(z.get_tongue_origin(),target_point,z.player_ref)
				_finish(4.5)
		"fuse":
			if remaining<=0:
				state="spent" # 先改变状态，死亡信号重入也不能二次爆炸。
				if gap.length()<=150:
					z.player_ref.take_damage(22)
				Explosion.blast(z.get_parent(),z.global_position,150,Color(1,.45,.1))
				z.take_damage(z.health)
		"howl_windup":
			if remaining<=0:
				for ally in _allies():
					ally.apply_rally(4.0)
				state="howl_wave"
				remaining=.55
				warning.text="尸群狂热"
		"howl_wave":
			if remaining<=0: _finish(8.0)
	return true

func _allies() -> Array:
	var result := []
	for ally in get_tree().get_nodes_in_group("zombies"):
		if ally==z or not is_instance_valid(ally) or ally.is_queued_for_deletion() or not ally.has_method("apply_rally"):
			continue
		if not ally.dead and not ally.stopped and not ally.rising and z.global_position.distance_to(ally.global_position)<=300:
			result.append(ally)
	return result

func _draw():
	if not is_instance_valid(z) or z.dead or z.stopped: return
	var ground := Vector2(0,90)
	match state:
		"charge_windup":
			var end := ground+Vector2(facing*245,0)
			draw_line(ground,end,Color(1,.25,.12,.8),3,true)
			draw_line(end,end+Vector2(-facing*15,-8),Color(1,.6,.3),3,true)
		"charge":
			draw_line(Vector2(-facing*45,45),Vector2(-facing*80,45),Color(1,.65,.4,.65),3,true)
		"spit_windup":
			var local := to_local(target_point)
			draw_set_transform(local,0,Vector2(1,.22))
			draw_circle(Vector2.ZERO,44,Color(.5,1,.1,.12))
			draw_arc(Vector2.ZERO,44,0,TAU,48,Color(.7,1,.3,.9),5,true)
		"fuse":
			draw_set_transform(ground,0,Vector2(1,.25))
			draw_circle(Vector2.ZERO,150,Color(1,.32,.08,.13+.08*sin(pulse*22)))
			draw_arc(Vector2.ZERO,150,0,TAU,64,Color(1,.65,.2,.9),4,true)
			draw_arc(Vector2.ZERO,150,-PI/2,-PI/2+TAU*clampf(1-remaining/1.2,0,1),64,Color(1,.94,.65),8,true)
		"howl_windup","howl_wave":
			var radius := 42.0 if state=="howl_windup" else lerpf(42,300,clampf(1-remaining/.55,0,1))
			draw_arc(Vector2(0,-50),radius,0,TAU,64,Color(.8,.5,1,.65),2,true)
	draw_set_transform(Vector2.ZERO)
	if z.zombie_type=="armored" and armor_flash>0:
		var side := -1.0 if z.sprite.flip_h else 1.0
		draw_line(Vector2(side*32,-44),Vector2(side*32,32),Color(.6,.85,1),5,true)
