extends RefCounted
class_name Stages

# ============================================================================
# Stages.gd —— 关卡地图配置（数据驱动，唯一数据源）
# ============================================================================
# 每一关的「地图」由这一份配置决定，Main.tscn 按 GameState.selected_stage 读取：
#   name           : 关卡名（战斗界面左上角「关卡 N · 名字」显示用）
#   bg             : 背景图路径（res://art/ 下，1280x720，与 background_city 同规格）
#   weights        : 丧尸生成权重（male 近战 / female 远程 / fat 肉盾）
#   spawn_interval : 刷怪间隔（秒），越小刷得越快
#   ambient        : 氛围色（乘在背景与世界上的色调，白色 = 不着色）
#
# 通关目标（击杀数）用公式：8 + (关卡-1) * 4，见 goal()。
# 配置表里没写的关自动回落到 DEFAULT 配置（城市废墟基线）。
#
# 想加/改一关：只需改下面的 STAGES 字典，不用动任何场景文件。
# 目前已把 1~20 关全部显式配置，难度按「远程女丧尸↑ + 肉盾胖丧尸↑ + 刷怪间隔↓」递进。
# 世界划分：世界1 = 1-5（城市/公路/军事/工厂/地铁），世界2 = 6-10（实验室/港口/荒野/巢穴/要塞），
#          世界3 = 11-15（沙漠废都，背景 bg_world3），世界4 = 16-20（熔岩末日，背景 bg_world4），
#          世界5 = 21-25（极寒废土，背景复用 bg_world4 — 没有 bg_world5，氛围色靠 ambient 拉开）。
# ============================================================================

# 基线配置（兜底用，第 1 关同款）
const DEFAULT := {
	"name": "城市废墟",
	"bg": "res://art/background_city.png",
	"weights": {"male": 55, "female": 30, "fat": 15},
	"spawn_interval": 2.0,
	"ambient": Color(1, 1, 1),
	"accent": Color(0.4, 1.0, 0.6),
}

# 复用三张已生成的背景图（city / stage2 / stage3）+ 两张通用背景（original / background）
const STAGES := {
	1: {
		"name": "城市废墟",
		"bg": "res://art/background_city.png",
		"weights": {"male": 55, "female": 30, "fat": 15},
		"spawn_interval": 2.0,
		"ambient": Color(1, 1, 1),
		"accent": Color(0.4, 1.0, 0.6),
	},
	2: {
		"name": "血色公路",
		"bg": "res://art/bg_stage2.png",
		"weights": {"male": 45, "female": 40, "fat": 15},   # 远程女丧尸明显变多
		"spawn_interval": 1.6,                              # 刷得比第 1 关快
		"ambient": Color(1.0, 0.93, 0.86),                  # 血色黄昏暖色调
		"accent": Color(1.0, 0.55, 0.3),                    # 橙红（选关界面主题色）
	},
	3: {
		"name": "军事禁区",
		"bg": "res://art/bg_stage3.png",
		"weights": {"male": 40, "female": 20, "fat": 40},   # 肉盾胖丧尸大幅变多
		"spawn_interval": 1.8,
		"ambient": Color(0.84, 0.93, 1.0),                  # 夜战冷色调
		"accent": Color(0.45, 0.85, 1.0),                   # 冰青（选关界面主题色）
	},
	4: {
		"name": "废弃工厂",
		"bg": "res://art/bg_stage2.png",
		"weights": {"male": 35, "female": 35, "fat": 30},   # 远程+肉盾同时上升
		"spawn_interval": 1.5,
		"ambient": Color(0.95, 1.0, 0.92),                  # 微绿工业冷光
		"accent": Color(0.75, 0.95, 0.35),                  # 黄绿
	},
	5: {
		"name": "地铁废站",
		"bg": "res://art/background_city.png",
		"weights": {"male": 30, "female": 40, "fat": 30},   # 女丧尸成为主力
		"spawn_interval": 1.4,
		"ambient": Color(0.90, 0.88, 1.0),                  # 地铁幽紫
		"accent": Color(0.72, 0.45, 1.0),                   # 紫
		"boss": {"type": "brute", "hp_mul": 1.0},           # 世界1 末关 BOSS
	},
	6: {
		"name": "生化实验室",
		"bg": "res://art/bg_stage3.png",
		"weights": {"male": 30, "female": 30, "fat": 40},   # 肉盾占主导
		"spawn_interval": 1.3,
		"ambient": Color(0.86, 1.0, 0.88),                  # 毒绿
		"accent": Color(0.55, 1.0, 0.45),                   # 荧光绿
	},
	7: {
		"name": "末日港口",
		"bg": "res://art/bg_stage2.png",
		"weights": {"male": 25, "female": 45, "fat": 30},   # 远程压制极强
		"spawn_interval": 1.2,
		"ambient": Color(0.85, 0.92, 1.0),                  # 海雾蓝
		"accent": Color(0.35, 0.7, 1.0),                    # 蓝
	},
	8: {
		"name": "辐射荒野",
		"bg": "res://art/background_original.png",
		"weights": {"male": 25, "female": 40, "fat": 35},
		"spawn_interval": 1.1,
		"ambient": Color(1.0, 0.82, 0.66),                  # 辐射橙
		"accent": Color(1.0, 0.45, 0.2),                    # 橙红
	},
	9: {
		"name": "丧尸巢穴",
		"bg": "res://art/bg_stage3.png",
		"weights": {"male": 20, "female": 35, "fat": 45},   # 胖丧尸海 + 远程骚扰
		"spawn_interval": 1.0,
		"ambient": Color(1.0, 0.80, 0.80),                  # 血色
		"accent": Color(1.0, 0.30, 0.30),                   # 红
	},
	10: {
		"name": "终焉要塞",
		"bg": "res://art/background.png",
		"weights": {"male": 15, "female": 45, "fat": 40},   # 终局：远程+肉盾双压制
		"spawn_interval": 0.9,
		"ambient": Color(1.0, 0.92, 0.75),                  # 末日金光
		"accent": Color(1.0, 0.8, 0.2),                     # 金
		"boss": {"type": "hulk", "hp_mul": 1.4},            # 世界2 末关 BOSS
	},
	# ============================ 世界3：沙漠废都（11–15） ============================
	11: {
		"name": "黄沙集市",
		"bg": "res://art/bg_world3.png",
		"weights": {"male": 20, "female": 45, "fat": 35},
		"spawn_interval": 0.85,
		"ambient": Color(1.0, 0.90, 0.75),                  # 沙金黄
		"accent": Color(1.0, 0.62, 0.20),                   # 橙
	},
	12: {
		"name": "残破车站",
		"bg": "res://art/bg_world3.png",
		"weights": {"male": 18, "female": 48, "fat": 34},
		"spawn_interval": 0.80,
		"ambient": Color(1.0, 0.88, 0.70),                  # 落日暖沙
		"accent": Color(1.0, 0.55, 0.25),                   # 暗橙
	},
	13: {
		"name": "风蚀峡谷",
		"bg": "res://art/bg_world3.png",
		"weights": {"male": 18, "female": 45, "fat": 37},
		"spawn_interval": 0.78,
		"ambient": Color(1.0, 0.85, 0.65),                  # 峡谷夕照
		"accent": Color(0.95, 0.50, 0.30),                  # 赭红
	},
	14: {
		"name": "干涸河床",
		"bg": "res://art/bg_world3.png",
		"weights": {"male": 15, "female": 48, "fat": 37},
		"spawn_interval": 0.75,
		"ambient": Color(1.0, 0.82, 0.60),                  # 旱地赤土
		"accent": Color(1.0, 0.45, 0.20),                   # 砖红
	},
	15: {
		"name": "沙暴王城",
		"bg": "res://art/bg_world3.png",
		"weights": {"male": 15, "female": 50, "fat": 35},
		"spawn_interval": 0.72,                             # 世界3 末关：远程压制巅峰
		"ambient": Color(1.0, 0.80, 0.55),                  # 王城金辉
		"accent": Color(1.0, 0.72, 0.15),                   # 金沙金
		"boss": {"type": "brute", "hp_mul": 1.9},           # 世界3 末关 BOSS（强化暴食者）
	},
	# ============================ 世界4：熔岩末日（16–20） ============================
	16: {
		"name": "焦黑公路",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 15, "female": 45, "fat": 40},
		"spawn_interval": 0.70,
		"ambient": Color(1.0, 0.70, 0.50),                  # 熔岩熏红
		"accent": Color(1.0, 0.35, 0.15),                   # 炽橙红
	},
	17: {
		"name": "崩裂桥梁",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 12, "female": 48, "fat": 40},
		"spawn_interval": 0.68,
		"ambient": Color(1.0, 0.62, 0.45),                  # 暗红火光
		"accent": Color(1.0, 0.30, 0.10),                   # 深橙红
	},
	18: {
		"name": "熔岩深渊",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 12, "female": 45, "fat": 43},
		"spawn_interval": 0.66,                             # 肉盾海 + 远程
		"ambient": Color(0.95, 0.55, 0.40),                 # 岩浆橙
		"accent": Color(1.0, 0.25, 0.10),                   # 火红
	},
	19: {
		"name": "炼狱工厂",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 10, "female": 48, "fat": 42},
		"spawn_interval": 0.64,
		"ambient": Color(0.92, 0.50, 0.40),                 # 高炉赤红
		"accent": Color(1.0, 0.20, 0.10),                   # 血红
	},
	20: {
		"name": "终焉熔炉",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 10, "female": 50, "fat": 40},
		"spawn_interval": 0.60,                             # 全游戏最难：远程+肉盾双极限
		"ambient": Color(1.0, 0.45, 0.35),                  # 末日血光
		"accent": Color(1.0, 0.15, 0.10),                   # 亮红
		"boss": {"type": "hulk", "hp_mul": 2.4},            # 世界4 末关 BOSS（强化绿巨人）
	},
	# ============================ 世界5：极寒废土（21–25） ============================
	# 主题与世界4（火/熔岩）相对应，元素循环收束于「冰」。没有专属背景图，沿用 bg_world4，
	# 靠 ambient 叠加冷色调做出冻土视觉差。要换背景图，把下面 5 个 "bg" 改成新的 res:// 路径即可。
	21: {
		"name": "霜冻前哨",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 12, "female": 45, "fat": 43},
		"spawn_interval": 0.58,
		"ambient": Color(0.75, 0.88, 1.0),                  # 冷蓝白
		"accent": Color(0.40, 0.78, 1.0),                   # 冰蓝
	},
	22: {
		"name": "永冻废墟",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 10, "female": 48, "fat": 42},
		"spawn_interval": 0.55,
		"ambient": Color(0.62, 0.82, 0.95),                 # 霜青
		"accent": Color(0.30, 0.70, 0.95),                  # 深霜青
	},
	23: {
		"name": "暴风雪原",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 10, "female": 45, "fat": 45},
		"spawn_interval": 0.52,
		"ambient": Color(0.85, 0.90, 1.0),                  # 灰白雪雾
		"accent": Color(0.85, 0.92, 1.0),                   # 雪白
	},
	24: {
		"name": "玄冰深渊",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 8, "female": 48, "fat": 44},
		"spawn_interval": 0.50,
		"ambient": Color(0.78, 0.70, 0.95),                 # 极光紫
		"accent": Color(0.60, 0.45, 0.95),                  # 极光紫
	},
	25: {
		"name": "终焉冰宫",
		"bg": "res://art/bg_world4.png",
		"weights": {"male": 8, "female": 50, "fat": 42},
		"spawn_interval": 0.48,                             # 全游戏终局：刷速 + 远程肉盾双极限
		"ambient": Color(0.80, 0.95, 1.0),                  # 冰冠白
		"accent": Color(0.55, 0.95, 1.0),                   # 冰晶
		"boss": {"type": "reaper", "hp_mul": 3.0},          # 最终 BOSS 收割者
	},
}

# ---------------------------------------------------------------------------
# 静态取值接口
# ---------------------------------------------------------------------------
# 取第 s 关的完整配置字典。关号不存在时回退到 DEFAULT（城市废墟基线），永不返回空。
static func config(s: int) -> Dictionary:
	return STAGES.get(s, DEFAULT)

# 取关卡显示名（如「城市废墟」）。战斗界面左上角「关卡 N · 名字」用它。
static func stage_name(s: int) -> String:
	return String(config(s)["name"])

# 取本关全部已解锁丧尸的权重；基础三种按原配比分享剩余概率，变异种逐关递增。
static func weights(s: int) -> Dictionary:
	return preload("res://zombie_catalog.gd").stage_weights(s,config(s)["weights"])

# 本关刷怪间隔（秒）。越小刷得越密集；第 1 关 2.0s，之后逐关递减到末关 0.48s。
static func spawn_interval(s: int) -> float:
	return float(config(s)["spawn_interval"])

# 本关氛围色调（乘在背景与世界上的滤色，白色 = 不着色）。用来区分世界/营造气氛。
static func ambient(s: int) -> Color:
	return config(s)["ambient"]

# 主题色（选关界面圆圈描边/地图名用，每关一个辨识色）
# 本关主题色（选关界面圆圈描边/地图名用）。每关一个辨识色，便于玩家区分进度。
static func accent(s: int) -> Color:
	return config(s)["accent"]

# BOSS：只有配了 "boss" 的关才出 BOSS（当前 5/10/15/20/25）。
# 这几个一律用 .get 带默认值 —— 本文件里 weights()/ambient()/accent() 都直接
# ["key"] 取值，未配置的关一旦访问就会崩；BOSS 是可选字段，必须容错。
# 取本关 BOSS 配置 {type, hp_mul}；没配 boss 的关返回空字典。必须用 .get 容错——
# 因为不是每关都有 boss 字段，直接 ["boss"] 访问会崩（而 weights/ambient 每关都有）。
static func boss_config(s: int) -> Dictionary:
	return config(s).get("boss", {})

# 本关是否出 BOSS（当前 5/10/15/20/25 关配了 boss）。main.gd 据此决定是否生成 BOSS。
static func has_boss(s: int) -> bool:
	return not boss_config(s).is_empty()

# 本关 BOSS 类型（brute/hulk/reaper）。空字符串代表没 BOSS。spawn 逻辑据此选模型。
static func boss_type(s: int) -> String:
	return String(boss_config(s).get("type", ""))

# 本关 BOSS 血量倍率（1.0 = 基准，末关最高 3.0）。用来缩放 BOSS 难度，越高越肉。
static func boss_hp_mul(s: int) -> float:
	return float(boss_config(s).get("hp_mul", 1.0))

# 通关目标：第 1 关 8 只，之后每关 +4
static func goal(s: int) -> int:
	return 8 + (s - 1) * 4

# 背景贴图（文件不存在返回 null，调用方保留场景里默认的背景）
# 加载本关背景贴图。文件缺失时返回 null，main.gd 保留场景里默认背景，避免白屏。
static func bg_texture(s: int) -> Texture2D:
	var p := String(config(s)["bg"])
	if not ResourceLoader.exists(p):
		return null
	return load(p)

# 按权重随机选一种丧尸类型（供 main.gd 的刷怪定时器调用）。
# 实现要点：randi() % maxi(total, 1) 用 maxi(total,1) 防止权重全 0 时 mod 0 崩溃；
# 若都不命中（理论上不会）兜底返回 "male" 近战丧尸，保证一定有怪可刷。
static func pick_zombie_type(s: int) -> String:
	var w: Dictionary = weights(s)
	var total := 0
	for k in w:
		total += int(w[k])
	var r := randi() % maxi(total, 1)
	for k in w:
		r -= int(w[k])
		if r < 0:
			return String(k)
	return "male"
