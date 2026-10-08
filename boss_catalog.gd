extends RefCounted

# ============================================================================
# boss_catalog.gd —— BOSS 数据源（★ 改 BOSS 数值就在这个文件★）
# ----------------------------------------------------------------------------
# 与 zombie_catalog.gd 对称的结构，同样是「数据唯一源」，战斗/图鉴/选关说明都读这里。
# main.gd 第 89 行 `const BOSSTYPES = BOSS_CATALOG.DEFINITIONS` 只是引用本表。
# ⚠️ 改 BOSS 数值只改这里，不要改 main.gd。
#
# ---- 三个 BOSS 一览（实际血量 = max_health × Stages.boss_hp_mul(关卡)，随关卡递增）----
#   暴食者 brute  第 5 关   基础血 1200  移速 45  接触伤害 18  技能：冲锋
#   绿巨人 hulk   第 10 关  基础血 1000  移速 60  接触伤害 22  技能：震地
#   收割者 reaper 第 25 关  基础血 1500  移速 50  接触伤害 15  技能：召唤
#
# ---- 字段含义（与普通丧尸相同的略过）----
#   max_health      : 基础血量（还要乘关卡倍率才实际生效）
#   speed           : 移速
#   contact_damage  : 碰到玩家造成的伤害（持续贴身时的伤害）
#   attack_interval : 普通攻击间隔（秒）
#   skill_type      : 技能类型 charge冲锋 / slam震地 / summon召唤
#   skill_interval  : 技能冷却（秒）
#   skill_damage    : 技能伤害（summon 为 0，因为它不直接伤人）
#   skill2_type     : 副技能类型 roar怒吼 / rock投石 / wave斩波（"" = 无副技能）
#   skill2_interval : 副技能冷却（秒）
#   skill2_damage   : 副技能伤害
#   skill2_range    : 副技能作用半径（rock=爆炸半径 / roar=声波半径 / wave 用 0）
#   movement        : 走位模式 chase追击 / kite风筝（远程 BOSS 保持距离：太近后撤/太远靠近）
#   kite_min        : 风筝内圈距离（像素），movement=kite 时生效
#   kite_max        : 风筝外圈距离（像素），movement=kite 时生效
#   motion          : 动作层参数表（boss_motion.gd 读取）
#                     style 走路风格 heavy沉重 / proud稳健 / float漂浮
#                     stride 一步像素距离；bob 起伏 px；sway 摇摆 rad；lean 前倾 rad
#                     step_dust 每步尘土粒子数；dust_color 尘土颜色
#                     float_amp/float_speed 漂浮幅度与频率（float 风格用）
#   tip             : 图鉴里的技能说明（改数值记得同步这句）
#
# ---- 想改什么去哪里改 ----
#   BOSS 太难/太简单 → 改 max_health 或 skill_damage
#   BOSS 技能太频繁   → 调 skill_interval（数值越大越慢）
#   BOSS 更快         → 改 speed
#   想加第 4 个 BOSS   → DEFINITIONS 加一项 + ORDER 加上它 + Stages.gd 配出现关卡
# ============================================================================

const DEFINITIONS := {
	"brute": {
		"name": "暴食者", "unlock": 5,
		"texture": "res://art/boss_prototypes_20260926/boss_brute.png",
		"max_health": 1200, "speed": 45.0, "attack_type": "melee",
		"melee_range": 115.0, "ranged_range": 0.0, "attack_interval": 2.2,
		"contact_damage": 18, "skill_type": "charge", "skill_interval": 6.0, "skill_damage": 25,
		"skill2_type": "roar", "skill2_interval": 12.0, "skill2_damage": 12, "skill2_range": 320.0,
		"motion": {
			"style": "heavy", "stride": 85.0, "bob": 5.0, "sway": 0.035, "lean": 0.06,
			"step_dust": 2, "dust_color": Color(0.55, 0.45, 0.32, 0.8),
		},
		"tip": "冲锋：蓄力后高速突进，撞到玩家造成 25 点伤害；未撞到则撞墙硬直，是躲开它的窗口。血最厚但移速最慢。副技能「怒吼」：震退身边小怪并造成 12 点范围伤害。",
	},
	"hulk": {
		"name": "绿巨人", "unlock": 10,
		"texture": "res://art/boss_prototypes_20260926/boss_hulk.png",
		"max_health": 1000, "speed": 60.0, "attack_type": "melee",
		"melee_range": 120.0, "ranged_range": 0.0, "attack_interval": 2.5,
		"contact_damage": 22, "skill_type": "slam", "skill_interval": 7.0, "skill_damage": 30,
		"skill2_type": "rock", "skill2_interval": 10.0, "skill2_damage": 20, "skill2_range": 70.0,
		"motion": {
			"style": "proud", "stride": 75.0, "bob": 4.0, "sway": 0.025, "lean": 0.05,
			"step_dust": 3, "dust_color": Color(0.5, 0.47, 0.42, 0.8),
		},
		"tip": "震地：砸地产生大范围冲击波，范围内的玩家受 30 点伤害。攻击间隔偏长，拉开距离可避开。副技能「投石」：弯腰掷出巨石，落地爆炸造成 20 点伤害。",
	},
	"reaper": {
		"name": "收割者", "unlock": 25,
		"texture": "res://art/boss_prototypes_20260926/boss_reaper.png",
		"max_health": 1500, "speed": 50.0, "attack_type": "ranged",
		"melee_range": 0.0, "ranged_range": 600.0, "attack_interval": 1.8,
		"movement": "kite", "kite_min": 320.0, "kite_max": 520.0,
		"contact_damage": 15, "skill_type": "summon", "skill_interval": 9.0, "skill_damage": 0,
		"skill2_type": "wave", "skill2_interval": 8.0, "skill2_damage": 30, "skill2_range": 0.0,
		"motion": {
			"style": "float", "float_amp": 9.0, "float_speed": 2.0, "sway": 0.02,
			"step_dust": 0,
		},
		"tip": "召唤：定期召出小怪支援自身，同时远程射击。血量最高、射速最快，终局 BOSS。副技能「死亡斩波」：挥镰甩出紫色月牙，命中玩家造成 30 点伤害。",
	},
}

const ORDER := ["brute", "hulk", "reaper"]

# BOSS 是否已解锁（玩家已通关的最高关 ≥ 首次出现关卡）
static func unlocked(id: String, stage: int) -> bool:
	return DEFINITIONS.has(id) and int(DEFINITIONS[id].unlock) <= clampi(stage, 1, 25)

# 取定义（容错：未知 id 回退 brute，避免调用方拿空字典崩）
static func def(id: String) -> Dictionary:
	return DEFINITIONS.get(id, DEFINITIONS["brute"])
