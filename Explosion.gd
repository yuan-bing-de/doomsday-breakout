class_name Explosion
extends RefCounted

# ============================================================================
# Explosion.gd —— 爆炸工具（手雷 / 支援导弹 共用）
# ============================================================================
# 不挂节点，全部是静态函数：
#   Explosion.damage_zombies(中心, 半径, 伤害)  → 对范围内的丧尸造成伤害
#   Explosion.blast(self, 中心, 半径, 颜色)      → 播放一次爆炸特效
#
# 伤害衰减：正中心 100%，边缘 50%（线性），避免「擦个边和正中一样疼」。
# 只查 "zombies" 分组，所以永远炸不到玩家自己。
# ============================================================================


# ----------------------------------------------------------------------------
# 范围伤害：返回命中数量
# ----------------------------------------------------------------------------
static func damage_zombies(center: Vector2, radius: float, damage: int) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var hit := 0
	for z in tree.get_nodes_in_group("zombies"):
		if not is_instance_valid(z):
			continue
		var n2 := z as Node2D
		if n2 == null:
			continue
		var d: float = n2.global_position.distance_to(center)
		if d > radius:
			continue
		var k: float = 1.0 - 0.5 * (d / maxf(1.0, radius))   # 中心 1.0 → 边缘 0.5
		if z.has_method("take_damage"):
			z.take_damage(int(round(float(damage) * k)))
			hit += 1
	return hit


# ----------------------------------------------------------------------------
# 爆炸特效：一团由白黄 → 橙红 → 透明扩散的火球
# ----------------------------------------------------------------------------
static func blast(parent: Node, pos: Vector2, radius: float, tint := Color(1.0, 0.55, 0.15)) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var s := Sprite2D.new()
	s.texture = _blast_texture(tint)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.global_position = pos
	s.z_index = 8
	parent.add_child(s)

	var tex_w: float = float(s.texture.get_width())
	var target_scale: float = (radius * 2.0) / maxf(1.0, tex_w)   # 火球贴图原始宽 tex_w；目标直径=半径×2，缩放 = 目标直径 ÷ 原图宽
	s.scale = Vector2(target_scale * 0.35, target_scale * 0.35)   # 起始先缩到目标 0.35 倍，再 tween 放大到 1.0，做出「炸开瞬间膨胀」的视觉效果
	s.modulate.a = 0.95

	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2(target_scale, target_scale), 0.22)
	tw.tween_property(s, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(s.queue_free)


# 生成火球贴图（只做一次，之后复用）
static var _tex: Texture2D = null
static var _tex_tint: Color = Color(0, 0, 0, 0)

static func _blast_texture(tint: Color) -> Texture2D:
	if _tex != null and _tex_tint == tint:
		return _tex
	var sz := 96
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (sz - 1) / 2.0
	var R := sz / 2.0
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x - c, y - c).length() / R      # 0 中心 → 1 边缘
			if d > 1.0:
				continue
			var a: float = pow(1.0 - d, 1.6)                        # 透明度随半径衰减：pow(1-d, 1.6) 中心最实、边缘最虚；指数 1.6 控制过渡的锐利程度
			var col: Color
			if d < 0.28:
				col = Color(1.0, 1.0, 0.88)                          # 白黄核心
			elif d < 0.55:
				col = Color(1.0, 0.85, 0.35).lerp(tint, (d - 0.28) / 0.27)
			else:
				col = tint.lerp(Color(tint.r * 0.4, tint.g * 0.25, tint.b * 0.2), (d - 0.55) / 0.45)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_tex = ImageTexture.create_from_image(img)
	_tex_tint = tint
	return _tex
