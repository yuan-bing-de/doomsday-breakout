class_name Characters
extends RefCounted

# ============================================================================
# Characters.gd —— 人物数值表（全局只读数据 + 数值计算）
# ============================================================================
# 所有人物共用的「基础数值 + 天赋 + 解锁条件」都写在这里。
# 不挂在任何节点上，靠 class_name 直接调用：Characters.stats_for("driver", 3)
#
# 数值面板（人物详情界面）显示的四项 = 生命值 / 移速 / 手雷伤害 / 支援导弹伤害
#   最终值 = 基础值 →（按各天赋等级加成）→ 显示值
#
# ★ 天赋：每个人物可有「多个」天赋，写成 "talents": [ {…}, {…} ] 数组。
#   已设计：司机(疾行)、医生(强健体魄/急救精通)、警察(投掷专家/快速换弹)、
#           军人(军械精通/导弹指挥)、维修工(精工改装/加固护甲)、
#           程序员(自动化脚本/算法优化)。六个人物全部已设计。
#   加天赋的方法见文件末尾的说明。
# ============================================================================

# 人物显示顺序（选人界面的排列顺序 = 这个顺序）
const ORDER := ["driver", "doctor", "police", "soldier", "mechanic", "programmer"]

# 天赋等级上限 & 升级花费公式（花费 = TALENT_COST_BASE × (当前等级 + 1)）
#   0→1 级 300 金，1→2 级 600 金，2→3 级 900 金 …… 9→10 级 3000 金
# 注意：天赋升级已改用精魂（见 talent_soul_cost），金币花费公式仅保留作历史参考/展示
const TALENT_MAX_LEVEL := 10
const TALENT_COST_BASE := 300

# 天赋升级的精魂消耗：Lv0-4 每级 1 个，Lv5-9 每级 2 个（单个天赋从 0 升到 10 共 15 个）
const TALENT_SOUL_COST_BASE := 1

# ----------------------------------------------------------------------------
# 人物数据
#   hp              : 生命值
#   speed           : 移速（像素/秒），游戏里就是 player.gd 的 speed
#   grenade_damage  : 手雷伤害（爆炸范围内的伤害）
#   missile_damage  : 支援导弹伤害
#   grenade_cd      : 手雷冷却（秒）
#   missile_cd      : 支援导弹冷却（秒）
#   talent          : 天赋，{} = 尚未设计
#   unlock          : 解锁条件，stat = none 表示初始就解锁
# ----------------------------------------------------------------------------
const DEFS := {
	"driver": {
		"name": "司机",
		"hp": 100,
		"speed": 160.0,          # 匹配约 46px/步、3.5步/秒的持枪行走；疾行天赋仍叠加
		"grenade_damage": 200,
		"missile_damage": 800,
		"grenade_cd": 8.0,
		"missile_cd": 25.0,
		"talents": [
			{
				"id": "swift",
				"name": "疾行",
				"desc": "移动速度 +0.02 × 天赋等级",
				"stat": "speed_mul",
				"per_level": 0.02,         # 每级 +2%
				"max_level": 10,
			},
		],
		"unlock": {"stat": "none", "target": 0, "text": "初始角色"},
	},
	"doctor": {
		"name": "医生",
		"hp": 100,
		"speed": 240.0,
		"grenade_damage": 200,
		"missile_damage": 800,
	"grenade_cd": 8.0,
	"missile_cd": 25.0,
	"talents": [
		{
			"id": "vigor",
			"name": "强健体魄",
			"desc": "基础生命值 +5 × 天赋等级",
			"stat": "hp_add",             # 加法：每级 +5 点基础生命
			"per_level": 5,
			"max_level": 10,
		},
		{
			"id": "medic",
			"name": "急救精通",
			"desc": "医疗包治疗量 +4% × 天赋等级",
			"stat": "medkit_mul",         # 医疗包回血量乘区
			"per_level": 0.04,
			"max_level": 10,
		},
	],
	"unlock": {"stat": "total_kills", "target": 100, "text": "累计击杀 100 个丧尸"},
},
	"police": {
		"name": "警察",
		"hp": 100,
		"speed": 240.0,
		"grenade_damage": 200,
		"missile_damage": 800,
	"grenade_cd": 8.0,
	"missile_cd": 25.0,
	"talents": [
		{
			"id": "thrower",
			"name": "投掷专家",
			"desc": "手雷冷却 -3% × 天赋等级",
			"stat": "grenade_cd_mul",     # 手雷冷却乘区（越低越快）
			"per_level": 0.03,
			"max_level": 10,
		},
		{
			"id": "quick_reload",
			"name": "快速换弹",
			"desc": "换弹时间 -6% × 天赋等级",
			"stat": "reload_mul",         # 换弹时间乘区（越低越快）
			"per_level": 0.06,
			"max_level": 10,
		},
	],
	"unlock": {"stat": "level_clears", "target": 3, "text": "累计通关 3 次"},
},
	"soldier": {
		"name": "军人",
		"hp": 100,
		"speed": 240.0,
		"grenade_damage": 200,
		"missile_damage": 800,
		"grenade_cd": 8.0,
		"missile_cd": 25.0,
		"talents": [
			{
				"id": "arsenal_power",
				"name": "军械精通",
				"desc": "子弹伤害 +5% × 天赋等级",
				"stat": "wpn_lvl_dmg_mul",     # 子弹伤害乘区（固定每级加成，不乘武器强化等级）
				"per_level": 0.05,
				"max_level": 10,
			},
			{
				"id": "missile_command",
				"name": "导弹指挥",
				"desc": "支援导弹冷却 -5% × 天赋等级",
				"stat": "wpn_lvl_missile_cd_mul",  # 导弹冷却乘区（固定每级加成，不乘武器强化等级）
				"per_level": 0.05,
				"max_level": 10,
			},
		],
		"unlock": {"stat": "total_kills", "target": 500, "text": "累计击杀 500 个丧尸"},
	},
	"mechanic": {
		"name": "维修工",
		"hp": 100,
		"speed": 240.0,
		"grenade_damage": 200,
		"missile_damage": 800,
		"grenade_cd": 8.0,
		"missile_cd": 25.0,
		"talents": [
			{
				"id": "refit",
				"name": "精工改装",
				"desc": "武器强化费用 -4% × 天赋等级",
				"stat": "upgrade_cost_mul",   # 武器强化费用乘区（越低越便宜，下限 0.4）
				"per_level": 0.04,
				"max_level": 10,
			},
			{
				"id": "reinforce",
				"name": "加固护甲",
				"desc": "受到的伤害 -3% × 天赋等级",
				"stat": "damage_taken_mul",   # 受伤乘区（越低越抗揍，下限 0.5）
				"per_level": 0.03,
				"max_level": 10,
			},
		],
		"unlock": {"stat": "level_clears", "target": 10, "text": "累计通关 10 次"},
	},
	"programmer": {
		"name": "程序员",
		"hp": 100,
		"speed": 240.0,
		"grenade_damage": 200,
		"missile_damage": 800,
		"grenade_cd": 8.0,
		"missile_cd": 25.0,
		"talents": [
			{
				"id": "auto_script",
				"name": "自动化脚本",
				"desc": "关卡内拾取金币 +5% × 天赋等级",
				"stat": "coin_mul",           # 局内金币拾取乘区（不影响任务/成就奖励）
				"per_level": 0.05,
				"max_level": 10,
			},
			{
				"id": "optimize",
				"name": "算法优化",
				"desc": "击杀获得的经验 +4% × 天赋等级",
				"stat": "exp_mul",            # 击杀经验乘区
				"per_level": 0.04,
				"max_level": 10,
			},
		],
		"unlock": {"stat": "chests_opened", "target": 20, "text": "累计开启 20 个宝箱"},
	},
}


# ----------------------------------------------------------------------------
# 取某个人物的数据（找不到就退回司机，永远不会返回空）
# ----------------------------------------------------------------------------
static func def(char_id: String) -> Dictionary:
	if DEFS.has(char_id):
		return DEFS[char_id]
	return DEFS["driver"]


# 取人物中文显示名。拿不到时回退到 id 本身（如 "driver"），避免界面出现空文本。
static func display_name(char_id: String) -> String:
	return String(def(char_id).get("name", char_id))


# 返回人物正面立绘路径 res://art/characters_v3/front/<id>.png。
# 选人界面/详情界面用它加载头像；文件缺失时由调用方兜底（不会在此报错）。
static func front_art(char_id: String) -> String:
	return "res://art/characters_v3/front/%s.png" % char_id


# ----------------------------------------------------------------------------
# 天赋（每个人物可拥有多个，存为数组；没有 talents 键或为空数组 = 未设计）
#   每个天赋字典字段：
#     id        内部标识
#     name      显示名
#     desc      说明文字
#     stat      影响的数值键（见 stats_for 的 match）
#     per_level 每级加成量（hp_add 是加法点值；其余是比例，0.04 = +4%）
#     max_level 该天赋等级上限
#
#   stat 取值：
#     speed_mul / hp_mul / grenade_mul / missile_mul  → 乘区（+比例）
#     hp_add        → 基础生命加法（每级 +N 点，不随基础值缩放）
#     medkit_mul    → 医疗包治疗量乘区
#     grenade_cd_mul→ 手雷冷却乘区（越低越快，最低 0.1）
#     reload_mul    → 换弹时间乘区（越低越快，最低 0.1）
#     wpn_lvl_dmg_mul       → 子弹伤害乘区（固定每级加成，不与武器强化等级耦合）
#     wpn_lvl_missile_cd_mul→ 支援导弹冷却乘区（固定每级加成，越低越快，最低 0.1）
#     upgrade_cost_mul      → 武器强化费用乘区（越低越便宜，最低 0.4）
#     damage_taken_mul      → 受到伤害乘区（越低越抗揍，最低 0.5）
#     coin_mul              → 关卡内拾取金币乘区（不影响任务/成就奖励）
#     exp_mul               → 击杀获得经验乘区
# ----------------------------------------------------------------------------
static func talents(char_id: String) -> Array:
	return def(char_id).get("talents", [])


static func talent_count(char_id: String) -> int:
	return talents(char_id).size()


static func has_talent(char_id: String) -> bool:
	return talent_count(char_id) > 0


# 取某人物第 idx 个天赋的完整字典（含 id/name/desc/stat/per_level/max_level）。
# idx 越界或该人物无天赋时返回空字典 {}，调用方用 .is_empty() 判断是否存在。
static func talent_at(char_id: String, idx: int) -> Dictionary:
	var ts := talents(char_id)
	if idx >= 0 and idx < ts.size():
		return ts[idx]
	return {}


# 取某天赋的显示名；取不到时返回 "?" 占位，便于在面板中发现配置错误。
static func talent_name(char_id: String, idx: int) -> String:
	return String(talent_at(char_id, idx).get("name", "?"))


# 取某天赋的详细描述文字（如「移速 +2% × 天赋等级」），用于天赋面板展示。
static func talent_desc(char_id: String, idx: int) -> String:
	return String(talent_at(char_id, idx).get("desc", ""))


# 取某天赋的等级上限。优先用天赋字典里的 max_level；缺省时回退到全局 TALENT_MAX_LEVEL(10)。
# 该人物没有该天赋则返回 0（表示不可升级）。
static func talent_max_level(char_id: String, idx: int) -> int:
	var t := talent_at(char_id, idx)
	if t.is_empty():
		return 0
	return int(t.get("max_level", TALENT_MAX_LEVEL))


# 从 lv 升到 lv+1 需要的金币（所有天赋共用同一套花费公式）
# 注意：天赋升级已改用精魂，此函数不再参与天赋扣费（见 talent_soul_cost）
static func talent_cost(lv: int) -> int:
	return TALENT_COST_BASE * (lv + 1)


# 从 lv 升到 lv+1 需要的精魂数量（天赋升级的实际花费）
# Lv0-4 每级 1 个，Lv5-9 每级 2 个 → 单个天赋 0→10 共 15 个
static func talent_soul_cost(lv: int) -> int:
	return TALENT_SOUL_COST_BASE + lv / 5


# 升到指定等级累计要花的钱（仅用于展示，不参与扣费）
static func talent_total_cost(lv: int) -> int:
	var sum := 0
	for i in range(lv):
		sum += talent_cost(i)
	return sum


# 某天赋在某等级的加成文字，例如「移速 +6%」「生命值 +50」
static func talent_bonus_text(char_id: String, idx: int, lv: int) -> String:
	var t := talent_at(char_id, idx)
	if t.is_empty() or lv <= 0:
		return ""
	var per := float(t.get("per_level", 0.0)) * float(lv)
	match String(t.get("stat", "")):
		"speed_mul":
			return "移速 +%d%%" % int(round(per * 100.0))
		"hp_mul":
			return "生命值 +%d%%" % int(round(per * 100.0))
		"grenade_mul":
			return "手雷伤害 +%d%%" % int(round(per * 100.0))
		"missile_mul":
			return "支援导弹伤害 +%d%%" % int(round(per * 100.0))
		"hp_add":
			return "生命值 +%d" % int(round(per))
		"medkit_mul":
			return "医疗包治疗 +%d%%" % int(round(per * 100.0))
		"grenade_cd_mul":
			return "手雷冷却 -%d%%" % int(round(per * 100.0))
		"reload_mul":
			return "换弹时间 -%d%%" % int(round(per * 100.0))
		"wpn_lvl_dmg_mul":
			return "伤害 +%d%%" % int(round(per * 100.0))
		"wpn_lvl_missile_cd_mul":
			return "支援导弹冷却 -%d%%" % int(round(per * 100.0))
		"upgrade_cost_mul":
			return "强化费用 -%d%%" % int(round(per * 100.0))
		"damage_taken_mul":
			return "受到伤害 -%d%%" % int(round(per * 100.0))
		"coin_mul":
			return "金币获取 +%d%%" % int(round(per * 100.0))
		"exp_mul":
			return "经验获取 +%d%%" % int(round(per * 100.0))
	return "+%.2f × %d" % [per, lv]


# ----------------------------------------------------------------------------
# stats_for()：算某人物在「各天赋等级数组」下的最终数值
#   返回 {"hp","speed","grenade_damage","missile_damage",
#         "hp_add","medkit_mul","grenade_cd_mul","reload_mul",
#         "dmg_mul","missile_cd_mul"}
#   只被天赋影响的项才会变，其余保持基础值
# ----------------------------------------------------------------------------
static func stats_for(char_id: String, talent_lvs: Array) -> Dictionary:
	var d := def(char_id)
	var hp := float(d.get("hp", 100))
	var spd := float(d.get("speed", 240.0))
	var gd := float(d.get("grenade_damage", 60))
	var md := float(d.get("missile_damage", 150))
	var hp_add := 0.0
	var medkit_mul := 1.0
	var grenade_cd_mul := 1.0
	var reload_mul := 1.0
	var dmg_mul := 1.0
	var missile_cd_mul := 1.0
	var upgrade_cost_mul := 1.0
	var damage_taken_mul := 1.0
	var coin_mul := 1.0
	var exp_mul := 1.0

	var ts := talents(char_id)
	for i in range(ts.size()):
		var t: Dictionary = ts[i]   # ts 是无类型 Array，必须显式标 Dictionary 否则 := 推断报错
		var mx := int(t.get("max_level", TALENT_MAX_LEVEL))
		var lv := clampi(int(talent_lvs[i]) if i < talent_lvs.size() else 0, 0, mx)
		var per := float(t.get("per_level", 0.0)) * float(lv)
		match String(t.get("stat", "")):
			"speed_mul":   spd *= (1.0 + per)
			"hp_mul":      hp *= (1.0 + per)
			"grenade_mul": gd *= (1.0 + per)
			"missile_mul": md *= (1.0 + per)
			"hp_add":      hp_add += per
			"medkit_mul":  medkit_mul *= (1.0 + per)
			"grenade_cd_mul":  grenade_cd_mul *= maxf(0.1, 1.0 - per)
			"reload_mul":      reload_mul *= maxf(0.1, 1.0 - per)
			# 军人：固定每级加成（不再乘「武器强化总等级数」，否则强化等级一高数值爆炸）
			"wpn_lvl_dmg_mul":      dmg_mul *= (1.0 + per)
			"wpn_lvl_missile_cd_mul": missile_cd_mul *= maxf(0.1, 1.0 - per)
			# 维修工：改装更便宜 + 抗揍（都设下限，避免满级把费用/伤害压到 0）
			"upgrade_cost_mul":   upgrade_cost_mul *= maxf(0.4, 1.0 - per)
			"damage_taken_mul":   damage_taken_mul *= maxf(0.5, 1.0 - per)
			# 程序员：局内资源获取加成（只作用于金币拾取 / 击杀经验，不放大任务奖励）
			"coin_mul":           coin_mul *= (1.0 + per)
			"exp_mul":            exp_mul *= (1.0 + per)
			# 以后加新天赋：在这里补一个 case，并同步 talent_bonus_text()

	return {
		"hp": int(round(hp)),
		"speed": spd,
		"grenade_damage": int(round(gd)),
		"missile_damage": int(round(md)),
		"hp_add": int(round(hp_add)),
		"medkit_mul": medkit_mul,
		"grenade_cd_mul": grenade_cd_mul,
		"reload_mul": reload_mul,
		"dmg_mul": dmg_mul,
		"missile_cd_mul": missile_cd_mul,
		"upgrade_cost_mul": upgrade_cost_mul,
		"damage_taken_mul": damage_taken_mul,
		"coin_mul": coin_mul,
		"exp_mul": exp_mul,
	}


# ----------------------------------------------------------------------------
# 解锁条件
# ----------------------------------------------------------------------------
static func unlock_text(char_id: String) -> String:
	return String(def(char_id).get("unlock", {}).get("text", "未设置"))


static func unlock_stat(char_id: String) -> String:
	return String(def(char_id).get("unlock", {}).get("stat", "none"))


static func unlock_target(char_id: String) -> int:
	return int(def(char_id).get("unlock", {}).get("target", 0))


# ============================================================================
# 以后要加某个人物的天赋，在 DEFS 里把它写成 "talents" 数组（可放多个）：
#
#   "doctor": {
#       ...
#       "talents": [
#           {
#               "id": "medic",              # 随便起的内部标识
#               "name": "急救",              # 显示名
#               "desc": "生命值 +0.05 × 天赋等级",   # 说明文字
#               "stat": "hp_mul",           # 影响哪一项：speed_mul / hp_mul /
#                                           #  grenade_mul / missile_mul /
#                                           #  hp_add / medkit_mul /
#                                           #  grenade_cd_mul / reload_mul
#               "per_level": 0.05,          # 每级加成量（0.05 = 5%；hp_add 是加法点值）
#               "max_level": 10,
#           },
#           # 想再加第二个天赋就在数组里再写一项
#       ],
#       ...
#   },
#
# 如果天赋要影响的不是已有项（比如减冷却、加回复），
# 就在 stats_for() 的 match 里加一个新的 case，并在 talent_bonus_text() 里补文字。
# ============================================================================
