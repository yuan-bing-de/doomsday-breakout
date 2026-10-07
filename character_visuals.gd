extends RefCounted

# ============================================================================
# character_visuals.gd —— 6 个角色的身体骨骼锚点数据（纯数据表，不含任何玩法数值）
# ----------------------------------------------------------------------------
# 原英文注释机翻：「已确认的无持枪侧身姿势的源图像素锚点。这里不含任何玩法数值。」
#
# 【它是什么】
# 纯数据表（RefCounted，不能进场景树的容器类），只存**源图上的像素坐标**，
# 供 character_locomotion.gd 做网格变形时定位身体各关节。
#
# 【为什么要手动标这些坐标】
# 骨骼动画要知道「髋在哪、膝在哪、脚底在哪、头多大、衣服下摆到哪」，
# 这些只能从原始立绘图上量出来。改立绘图 → 这里也要跟着更新。
#
# 【字段含义】（以 driver 为例）
#   hip/knee/ankle —— 髋、膝、脚踝的锚点（腿部弯曲的三个支点）
#   sole          —— 脚底在源图上的 y 坐标（贴地基准）
#   head          —— 头部半径（用于头部摆动/缩放）
#   cut           —— 身体「裁切线」y 坐标，以下是前景、以上是躯干
#   left/right    —— 左右边界（防止变形时超出原图范围）
#   boot          —— 鞋子的多边形轮廓（脚掌形变用）
#   pistol_grip / rear_grip / support —— 双手持枪时的握持点（副武器/主手）
#   *_hand        —— 手掌贴图区域（Rect2），让手能正确握住枪
#
# 【想改的地方】
#   换立绘图/改动作 → 重新量这些坐标；加角色 → 在 IDS 和 BODIES 里各加一项
# ============================================================================

## Source-pixel anchors for the approved unarmed side poses. No gameplay stats here.
const IDS = ["driver", "doctor", "police", "soldier", "mechanic", "programmer"]
static var BODIES = {
	"driver": {"hip": Vector2(414,735), "knee": Vector2(408,1003), "ankle": Vector2(365,1277), "head":74.0, "sole":1462.0, "cut":684.0,
		"left":285.0, "right":605.0, "boot":PackedVector2Array([Vector2(1260,436),Vector2(1320,443),Vector2(1355,480),Vector2(1392,564),Vector2(1536,605)]),
		"pistol_grip":Vector2(850,375), "rear_grip":Vector2(638,393), "support":Vector2(869,363),
		"pistol_hand":Rect2(793,318,96,104), "rear_hand":Rect2(590,346,93,94), "front_hand":Rect2(806,317,119,84)},
	"doctor": {"hip":Vector2(437,701), "knee":Vector2(439,1006), "ankle":Vector2(412,1280), "head":38.0, "sole":1481.0, "cut":940.0, "deform_cut":650.0, "leg_start":680.0, "leg_texture_top":947.0,
		"left":358.0, "right":627.0, "boot":PackedVector2Array([Vector2(1280,474),Vector2(1333,481),Vector2(1367,511),Vector2(1410,597),Vector2(1536,627)]),
		"pistol_grip":Vector2(855,370), "rear_grip":Vector2(611,394), "support":Vector2(861,361),
		"pistol_hand":Rect2(798,319,98,100), "rear_hand":Rect2(563,346,91,95), "front_hand":Rect2(809,310,112,90)},
	"police": {"hip":Vector2(424,684), "knee":Vector2(413,977), "ankle":Vector2(396,1250), "head":80.0, "sole":1453.0, "cut":646.0,
		"left":320.0, "right":610.0, "boot":PackedVector2Array([Vector2(1248,459),Vector2(1305,469),Vector2(1340,504),Vector2(1380,581),Vector2(1536,610)]),
		"pistol_grip":Vector2(848,379), "rear_grip":Vector2(574,396), "support":Vector2(865,367),
		"pistol_hand":Rect2(794,330,95,91), "rear_hand":Rect2(525,350,96,97), "front_hand":Rect2(810,321,115,90)},
	"soldier": {"hip":Vector2(411,700), "knee":Vector2(409,977), "ankle":Vector2(388,1268), "head":66.0, "sole":1454.0, "cut":637.0,
		"left":290.0, "right":617.0, "boot":PackedVector2Array([Vector2(1245,440),Vector2(1310,451),Vector2(1342,495),Vector2(1380,582),Vector2(1536,617)]),
		"pistol_grip":Vector2(849,372), "rear_grip":Vector2(620,401), "support":Vector2(892,365),
		"pistol_hand":Rect2(795,315,94,105), "rear_hand":Rect2(565,352,99,100), "front_hand":Rect2(836,317,122,91)},
	"mechanic": {"hip":Vector2(411,752), "knee":Vector2(411,1006), "ankle":Vector2(380,1285), "head":33.0, "sole":1478.0, "cut":727.0,
		"left":300.0, "right":610.0, "boot":PackedVector2Array([Vector2(1270,445),Vector2(1325,453),Vector2(1365,500),Vector2(1400,582),Vector2(1536,610)]),
		"pistol_grip":Vector2(846,341), "rear_grip":Vector2(562,388), "support":Vector2(847,347),
		"pistol_hand":Rect2(791,283,100,105), "rear_hand":Rect2(517,339,88,94), "front_hand":Rect2(797,306,111,85)},
	"programmer": {"hip":Vector2(417,766), "knee":Vector2(410,1002), "ankle":Vector2(378,1335), "head":50.0, "sole":1481.0, "cut":710.0,
		"left":300.0, "right":625.0, "boot":PackedVector2Array([Vector2(1300,441),Vector2(1348,449),Vector2(1378,485),Vector2(1412,592),Vector2(1536,625)]),
		"pistol_grip":Vector2(847,378), "rear_grip":Vector2(623,401), "support":Vector2(879,369),
		"pistol_hand":Rect2(792,322,94,101), "rear_hand":Rect2(581,349,90,103), "front_hand":Rect2(820,320,120,90)},
}

static func body(character_id: String, pose: String) -> Dictionary:
	if not BODIES.has(character_id): return {}
	var data: Dictionary = BODIES[character_id].duplicate(true)
	data["path"] = "res://art/characters_v3/side_poses_20261004/%s_%s_pose.png" % [character_id,pose]
	data["deform_cut"] = data.get("deform_cut", data.cut)
	if character_id == "soldier" and pose == "machine_gun":
		data.head = 50.0
		data.sole = 1456.0
	return data
