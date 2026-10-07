extends SceneTree

# 最小物理实验：确认 headless --script 模式下 CharacterBody2D.move_and_slide 是否有效
func _initialize() -> void:
	var body := CharacterBody2D.new()
	body.name = "TestBody"
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 80)
	cs.shape = shape
	body.add_child(cs)
	body.global_position = Vector2(0, 300)
	root.add_child(body)
	# 地面
	var g := StaticBody2D.new()
	g.name = "TestGround"
	var gcs := CollisionShape2D.new()
	var gshape := RectangleShape2D.new()
	gshape.size = Vector2(2000, 40)
	gcs.shape = gshape
	g.add_child(gcs)
	g.global_position = Vector2(0, 500)
	root.add_child(g)
	# 跑 30 帧：设水平速度，看位置是否变化、是否落地
	body.velocity = Vector2(100, 0)
	for i in range(30):
		await physics_frame
		body.velocity.y += 1200.0 * (1.0 / 60.0)
		body.move_and_slide()
		if i % 5 == 0 or i == 29:
			print("f", i, " pos=", body.global_position, " on_floor=", body.is_on_floor(), " vel=", body.velocity)
	quit(0)
