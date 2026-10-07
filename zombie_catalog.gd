extends RefCounted

# ============================================================================
# zombie_catalog.gd —— 丧尸数据唯一源（★ 改丧尸数值就在这个文件★）
# ----------------------------------------------------------------------------
# 【这是哪里】G:\末日突围\zombie_catalog.gd，下面的 DEFINITIONS 表。
#
# 【本文件是全项目丧尸数值的唯一来源】
#   被 8 个文件引用：main.gd（刷怪/战斗）、zombie.gd（行为）、Stages.gd（关卡刷怪权重）、
#   level_select.gd（选关说明）、codex_panel.gd（图鉴）、zombie_motion*.gd（动作）等。
#   ⚠️ 改数值**只改这里**，不要去改 main.gd 里的东西——main.gd 第 74 行
#      `const ZTYPES = ZOMBIE_CATALOG.DEFINITIONS` 只是引用本表，改它没用。
#
# ---- DEFINITIONS 每个字段的含义（第 3~12 行，一行一种丧尸）----
#   name           : 显示名（战斗提示、图鉴、选关说明都用它）
#   unlock         : 第几关开始出现（1 = 第一关就有）
#   texture        : 立绘贴图路径
#   max_health     : 血量上限
#   speed          : 移动速度（像素/秒）
#   attack_type    : 攻击方式 melee近战 / ranged远程 / special特殊
#   melee_range    : 近战攻击距离（像素），超出就不打
#   ranged_range   : 远程攻击距离（像素）
#   attack_interval: 两次攻击的最小间隔（秒），越小越快
#   damage         : 每次攻击造成的伤害
#   tip            : 战术提示（图鉴/选关说明展示给玩家看，改了数值记得同步这句）
#
# ---- 想改什么去哪里改 ----
#   某只丧尸太弱/太强 → 改它的 max_health / speed / damage
#   攻击太频繁       → 调 attack_interval（数值越大越慢）
#   想让某个变异种更早出现 → 改它的 unlock（第几关）
#   变异种出现概率    → 看 special_percentages() 里的 initial / steps 两个数组
#   刷怪总比例        → Stages.gd 的 weights（普通 vs 变异的大比例）
#
# 改完直接运行游戏即可生效，不需要动其他任何文件。
# ============================================================================

# 所有普通/变异丧尸共用的数据源；关卡、战斗和选关说明均读取这里。
const DEFINITIONS := {
	"male": {"name":"游荡者", "unlock":1, "texture":"res://art/zombie_male.png", "max_health":30, "speed":90.0, "attack_type":"melee", "melee_range":72.0, "ranged_range":0.0, "attack_interval":1.3, "damage":5, "tip":"近身挥爪，拉开距离或跳跃躲避。"},
	"female": {"name":"长舌女尸", "unlock":1, "texture":"res://art/zombie_female.png", "max_health":30, "speed":80.0, "attack_type":"ranged", "melee_range":0.0, "ranged_range":460.0, "attack_interval":2.0, "damage":5, "tip":"从嘴部伸出长舌，保持距离。"},
	"fat": {"name":"肥胖丧尸", "unlock":1, "texture":"res://art/zombie_fat.png", "max_health":150, "speed":55.0, "attack_type":"melee", "melee_range":78.0, "ranged_range":0.0, "attack_interval":1.6, "damage":5, "tip":"血厚移速慢，可边退边打。"},
	"runner": {"name":"突进者", "unlock":4, "texture":"res://art/mutants/runner.png", "max_health":100, "speed":110.0, "attack_type":"melee", "melee_range":65.0, "ranged_range":0.0, "attack_interval":1.5, "damage":7, "tip":"红线蓄力 0.65 秒后直线冲刺；跳起避开，冲刺后有硬直。"},
	"spitter": {"name":"腐蚀者", "unlock":7, "texture":"res://art/mutants/spitter.png", "max_health":120, "speed":80.0, "attack_type":"special", "melee_range":0.0, "ranged_range":430.0, "attack_interval":4.5, "damage":8, "tip":"向预警圈吐酸液，落地残留 3.5 秒；离开绿圈或跳过。"},
	"armored": {"name":"铁甲尸", "unlock":11, "texture":"res://art/mutants/armored.png", "max_health":300, "speed":70.0, "attack_type":"melee", "melee_range":80.0, "ranged_range":0.0, "attack_interval":1.8, "damage":12, "tip":"正面子弹减伤 55%；背后射击、手雷和导弹可绕过护甲。"},
	"volatile": {"name":"爆囊尸", "unlock":16, "texture":"res://art/mutants/volatile.png", "max_health":100, "speed":80.0, "attack_type":"special", "melee_range":0.0, "ranged_range":0.0, "attack_interval":1.0, "damage":22, "tip":"靠近后停下，蓄爆 1.2 秒；离开橙色范围或击杀打断。"},
	"howler": {"name":"嚎叫者", "unlock":21, "texture":"res://art/mutants/howler.png", "max_health":350, "speed":60.0, "attack_type":"melee", "melee_range":70.0, "ranged_range":0.0, "attack_interval":1.8, "damage":6, "tip":"紫色声波使附近普通丧尸移速和近战伤害提高 20%，持续 4 秒、不叠加；优先击杀。"},
}
const MUTANTS := ["runner", "spitter", "armored", "volatile", "howler"]

static func unlocked(id: String, stage: int) -> bool:
	return DEFINITIONS.has(id) and int(DEFINITIONS[id].unlock) <= clampi(stage,1,25)

static func new_at(stage: int) -> String:
	for id in MUTANTS:
		if int(DEFINITIONS[id].unlock) == stage:
			return id
	return ""

# 各变异种的绝对概率独立增长，新种加入不会挤低已解锁变异种的概率。
static func special_percentages(stage: int) -> Dictionary:
	var s := clampi(stage,1,25)
	var result := {}
	var initial := [8,6,6,5,5]
	var steps := [3,3,2,2,2]
	for i in range(MUTANTS.size()):
		var id: String = MUTANTS[i]
		var since: int = s - int(DEFINITIONS[id].unlock)
		if since >= 0:
			result[id] = int(initial[i]) + floori(float(since)/float(steps[i]))
	return result

static func stage_weights(stage: int, original: Dictionary) -> Dictionary:
	var special := special_percentages(stage)
	var remaining := 100
	for value in special.values():
		remaining -= int(value)
	var result := {}
	for id in ["male","female","fat"]:
		result[id] = int(original.get(id,0)) * remaining
	for id in special:
		result[id] = int(special[id]) * 100
	return result

static func summary(stage: int) -> String:
	var names := PackedStringArray()
	for id in DEFINITIONS:
		if unlocked(id,stage):
			names.append(DEFINITIONS[id].name)
	var total := 0
	for value in special_percentages(stage).values():
		total += int(value)
	return "第 %d 关 · %d 种丧尸 · 变异种出现概率 %d%%\n%s" % [stage,names.size(),total," / ".join(names)]

static func briefing(stage: int) -> String:
	var lines := PackedStringArray()
	var special := special_percentages(stage)
	for id in MUTANTS:
		if special.has(id):
			var cfg: Dictionary = DEFINITIONS[id]
			lines.append("%s  %d%% · %s" % [cfg.name,int(special[id]),cfg.tip])
	if lines.is_empty():
		return "先熟悉近战、长舌与肉盾。第 4 关将出现突进者。"
	return "\n".join(lines)

static func configure(z: Node, id: String) -> void:
	var key := id if DEFINITIONS.has(id) else "male"
	var cfg: Dictionary = DEFINITIONS[key]
	z.zombie_type = key
	z.texture_path = cfg.texture
	z.max_health = int(cfg.max_health)
	z.speed = float(cfg.speed)
	z.attack_type = cfg.attack_type
	z.melee_range = float(cfg.melee_range)
	z.ranged_range = float(cfg.ranged_range)
	z.attack_interval = float(cfg.attack_interval)
	z.melee_damage = int(cfg.damage)
