extends StaticBody2D

# ============================================================
#  路面（地面）脚本  ground.gd  —— 无限跟随版
# ------------------------------------------------------------
#  管两件事：
#    1) 看得见的路面（Sprite2D 铺 ground.png 纹理）
#    2) 看不见的碰撞体（人物踩在上面不掉下去）
#
#  ★ 为什么改成"无限跟随"：
#    以前是一次性铺死固定宽度（左边到 -2240、右边到 10000+）。
#    玩家一路向右推进，迟早走到路的尽头 → 路面戛然而止、露出背景
#    （2026-09-18 两次 bug：先是左侧露底，后来右侧走到尽头，同一个病）。
#    现在只保留少量几段路面，每帧把整块 Ground 吸附到玩家附近的
#    "段网格"上，路永远铺在玩家脚下和前方 = 无限长。
#
#  ★ 改路面只动下面几个常量，其余自动算。
# ============================================================

# ---- 核心参数 ----

# 屏幕尺寸（与 project.godot 一致）
const SCREEN_W := 1152
const SCREEN_H := 648

# 路面底边：钉死在屏幕最底部
const ROAD_BOTTOM := SCREEN_H          # = 648

# 路面厚度（像素）
const ROAD_HEIGHT := 140


# 路面顶边 = 底边 − 厚度
const ROAD_TOP := ROAD_BOTTOM - ROAD_HEIGHT   # = 478

# 碰撞体厚度
const COLLISION_THICKNESS := 60

# 路面贴图：用 ground.png 中间裂纹水泥段
const ROAD_TEXTURE := "res://art/ground.png"
const ROAD_REGION := Rect2(0, 200, 1408, 170)
const SEGMENT_W := int(ROAD_REGION.size.x)    # = 1408

# ---- 无限跟随参数 ----
const SEG_COUNT := 4            # 同时存在的段数（4 × 1408 = 5632px 的移动窗口）
# 即需求文档所说的 LEFT_EXTEND：向左铺路防露背景的保证宽度（玩家左侧永远留够这段路）
const LEFT_MARGIN := 1500.0     # 玩家左方至少保证的路（相机半屏 576 + 余量，往左走不露底）
const RIGHT_MARGIN := 1800.0    # 玩家右方（相机半屏 576 + 丧尸出生在 +1100）

# ---- 自动派生 ----
# 落脚线 = 人物脚踩的位置（路面顶边）。zombie.gd 的 STAND_Y 依赖它，别单独改。
const GROUND_LINE := ROAD_TOP
const TOTAL_WIDTH := SEG_COUNT * SEGMENT_W   # = 5632（≥ LEFT_MARGIN + RIGHT_MARGIN 即安全）


# ============================================================
#  _ready()：创建路面贴图 + 碰撞体（全部相对 Ground 节点摆放）
# ============================================================
func _ready():
	position = Vector2.ZERO

	# ---------- 1) 看得见的路面（Sprite2D 纹理，平铺 SEG_COUNT 段） ----------
	for i in SEG_COUNT:
		var road := Sprite2D.new()
		road.texture = load(ROAD_TEXTURE)
		road.centered = false
		road.region_enabled = true
		road.region_rect = ROAD_REGION
		road.position = Vector2(i * SEGMENT_W, ROAD_TOP)
		road.z_index = -1                   # 在背景之上、人物之下
		add_child(road)

	# 顶部路缘线（深色，让路面和背景有分界）
	var edge := Polygon2D.new()
	edge.polygon = PackedVector2Array([
		Vector2(0, ROAD_TOP),
		Vector2(TOTAL_WIDTH, ROAD_TOP),
		Vector2(TOTAL_WIDTH, ROAD_TOP + 4),
		Vector2(0, ROAD_TOP + 4)
	])
	edge.color = Color(0.25, 0.25, 0.25)
	edge.z_index = 0
	add_child(edge)

	# ---------- 2) 看不见的碰撞体 ----------
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TOTAL_WIDTH, COLLISION_THICKNESS)

	var collider := CollisionShape2D.new()
	collider.shape = shape
	# 碰撞体顶边贴齐路面顶边（落脚线），中心对齐铺好的路面
	collider.position = Vector2(TOTAL_WIDTH / 2.0, GROUND_LINE + COLLISION_THICKNESS / 2)
	add_child(collider)


# ============================================================
#  无限跟随：每帧把整块 Ground 吸附到玩家附近的段网格上。
#  吸附量是 SEGMENT_W 的整数倍 → 贴图接缝永远对齐，肉眼无感。
# ============================================================
func _physics_process(_delta):
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var px: float = players[0].global_position.x
	# 起点 = 玩家左侧 LEFT_MARGIN 处所在的段网格 →
	# 保证覆盖约 [玩家-1500, 玩家+4100]，左边不露底、右边够丧尸出生
	var origin := floorf((px - LEFT_MARGIN) / SEGMENT_W) * SEGMENT_W
	position.x = origin
