extends Node2D

# ============================================================================
# missile.gd —— 支援导弹（玩家按 H 呼叫）
# ============================================================================
# 生命周期：从屏幕上方（y = -160）垂直落下 → 在地面落点炸开
#          → 对半径 BLAST_RADIUS 内所有丧尸造成大范围伤害 + 爆炸特效
# 落点下方会先出现一个红色预警圈（提前告诉玩家导弹会砸在哪）。
#
# 伤害/冷却来自人物数值表（Characters.gd），由 player.gd 通过 setup() 传入。
# ============================================================================

const FALL_SPEED := 1400.0     # 下落速度（像素/秒）
const START_Y := -160.0        # 出生高度（屏幕上方）
const GROUND_Y := 478.0        # 落脚线
const BLAST_RADIUS := 250.0    # 爆炸范围半径（比手雷大）
const TRAIL_INTERVAL := 0.025  # 尾焰小点生成间隔

var damage := 150
var _exploded := false
var _trail_t := 0.0
var _target_x := 0.0           # 落点 X（setup 传入，进树后再落位）
var _marker: Sprite2D = null   # 地面预警圈（加在父节点上，不跟导弹走）
var _sprite: Sprite2D = null


func setup(dmg: int, target_x: float):
	damage = dmg
	_target_x = target_x


# ----------------------------------------------------------------------------
# _ready()：导弹生成时定位到目标 X 的上方，并在落点放置红色预警圈
#   作用：① 把导弹放到 (落点X, 屏幕上方 START_Y=-160) ② 在落点画一个会闪烁的红色预警圈
#         （预警圈加在父节点上、不随导弹下落，提前告诉玩家导弹会砸在哪）
# ----------------------------------------------------------------------------
func _ready():
	global_position = Vector2(_target_x, START_Y)

	_sprite = Sprite2D.new()
	_sprite.texture = _missile_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	z_index = 7

	# 地面预警圈（加在父节点，位置固定在落点）
	var parent := get_parent()
	if parent != null:
		_marker = Sprite2D.new()
		_marker.texture = _ring_texture()
		_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_marker.global_position = Vector2(global_position.x, GROUND_Y - 8.0)
		var r: float = BLAST_RADIUS * 2.0   # 预警圈贴图直径 = 爆炸直径（半径×2），圈的大小即实际杀伤范围
		var s: float = r / maxf(1.0, float(_marker.texture.get_width()))
		_marker.scale = Vector2(s, s)
		_marker.modulate = Color(1.0, 0.25, 0.2, 0.75)
		_marker.z_index = 2
		parent.add_child(_marker)
		# 预警圈闪烁：set_loops(3) 表示闪烁动画重复 3 次（约 0.72s，在导弹下落前给玩家提示落点）
		var tw := _marker.create_tween()
		tw.set_loops(3)
		tw.tween_property(_marker, "modulate:a", 0.25, 0.12)
		tw.tween_property(_marker, "modulate:a", 0.8, 0.12)


# ----------------------------------------------------------------------------
# _process()：每帧让导弹垂直下落，并周期性生成尾焰
#   参数：delta 帧间隔（秒）
#   作用：y 以 FALL_SPEED(1400) 下落；每 TRAIL_INTERVAL(0.025s) 生成一个尾焰小点；
#         到达地面(GROUND_Y-10) 即引爆
# ----------------------------------------------------------------------------
func _process(delta: float):
	if _exploded:
		return

	global_position.y += FALL_SPEED * delta

	# 尾焰小点
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = TRAIL_INTERVAL
		_spawn_trail()

	if global_position.y >= GROUND_Y - 10.0:
		_explode()


# ----------------------------------------------------------------------------
# _explode()：导弹落地引爆
#   作用：① 爆炸中心固定在地面(GROUND_Y-10) ② 对半径内丧尸造成大伤害
#         ③ 播两层火球特效（外层橙红 + 内层亮黄，内层半径为外层的 0.55 倍）
#         ④ 删除预警圈与自身。_exploded 标志保证只炸一次
# ----------------------------------------------------------------------------
func _explode():
	if _exploded:
		return
	_exploded = true
	var center := Vector2(global_position.x, GROUND_Y - 10.0)

	var parent := get_parent()
	Explosion.damage_zombies(center, BLAST_RADIUS, damage)
	if parent != null:
		Explosion.blast(parent, center, BLAST_RADIUS, Color(1.0, 0.42, 0.12))
		Explosion.blast(parent, center, BLAST_RADIUS * 0.55, Color(1.0, 0.85, 0.4))   # 内层亮黄火球，半径取外层的 0.55 倍，做出由内到外的层次感
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("explosion")   # 有 res://audio/explosion.ogg 才会响，没有则静默
	queue_free()


# 尾焰：一小团橙色点，向下飘散后淡出
func _spawn_trail():
	var parent := get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var d := Sprite2D.new()
	d.texture = _trail_texture()
	d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	d.global_position = global_position + Vector2(randf_range(-3.0, 3.0), -14.0)
	d.z_index = 6
	d.scale = Vector2(0.7, 0.7)
	parent.add_child(d)
	var tw := d.create_tween()
	tw.set_parallel(true)
	tw.tween_property(d, "position:y", d.position.y - 18.0, 0.35)
	tw.tween_property(d, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(d.queue_free)


# ----------------------------------------------------------------------------
# 贴图（全部代码生成，不依赖美术资源）
# ----------------------------------------------------------------------------
func _missile_texture() -> Texture2D:
	var w := 14
	var h := 34
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.68, 0.70, 0.74)
	var body_hi := Color(0.85, 0.87, 0.90)
	var dark := Color(0.30, 0.31, 0.34)
	var red := Color(0.85, 0.22, 0.18)
	for y in range(0, h - 10):
		var half := 3
		if y < 5:
			half = maxi(1, y - 1)          # 尖头
		for x in range(w):
			var dx: int = absi(x - 6)
			if dx <= half:
				if y < 5:
					img.set_pixel(x, y, red)
				elif x < 6:
					img.set_pixel(x, y, body_hi)
				elif x > 6:
					img.set_pixel(x, y, dark)
				else:
					img.set_pixel(x, y, body)
	# 尾翼
	for y in range(h - 12, h - 6):
		for x in range(w):
			if x <= 1 or x >= w - 2:
				img.set_pixel(x, y, dark)
	# 尾焰
	for y in range(h - 8, h):
		var t := float(y - (h - 8)) / 8.0
		var half := maxi(1, int(3.0 * (1.0 - t)))
		for x in range(w):
			if absi(x - 6) <= half:
				img.set_pixel(x, y, Color(1.0, 0.72 - t * 0.3, 0.15, 1.0 - t * 0.75))
	return ImageTexture.create_from_image(img)


func _trail_texture() -> Texture2D:
	var sz := 8
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (sz - 1) / 2.0
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x - c, y - c).length()
			if d <= 2.6:
				img.set_pixel(x, y, Color(0.65, 0.65, 0.68, 0.55 * (1.0 - d / 2.6)))
	return ImageTexture.create_from_image(img)


func _ring_texture() -> Texture2D:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (sz - 1) / 2.0
	var r_out := c
	var r_in := c - 3.0
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x - c, y - c).length()
			if d <= r_out and d >= r_in:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
