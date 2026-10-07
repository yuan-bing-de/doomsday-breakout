extends Node

# ============================================================================
# GameState.gd —— 全局状态（跨场景保存的数据，Autoload 单例）
# ============================================================================
# 游戏一启动就存在，任何脚本都能用 GameState.xxx 访问，场景切换也不丢。
# 负责：① 选人 ② 玩家等级/经验 ③ 金币/钻石 ④ 击杀掉落 ⑤ 图标生成
# ============================================================================

# ---- 选人 ----
var selected_character := "driver"
var unlocked_characters = ["driver"]
# 每个人物的天赋等级：char_id -> 等级（0 = 还没升过）。跨场景、跨重启持久化。
var talent_levels: Dictionary = {}

func is_unlocked(char_id: String) -> bool:
	return char_id in unlocked_characters
# 把人物加入已解锁列表（去重）。解锁后该人物可在选人界面选用、天赋可升级。
# 注意：只改内存，由调用方（check_character_unlocks）负责 save_profile 落盘持久化。
func unlock_character(char_id: String):
	if not char_id in unlocked_characters:
		unlocked_characters.append(char_id)

# ---- 人物天赋 / 数值 ----
# 取某人物「某一天赋(idx)」的当前等级
func char_talent_lv(char_id: String, idx: int = 0) -> int:
	var arr: Array = talent_levels.get(char_id, [])
	if idx >= 0 and idx < arr.size():
		return int(arr[idx])
	return 0

# 取某人物所有天赋等级的数组（长度 = 天赋数，未升级的部分补 0）
func char_talent_lvs(char_id: String) -> Array:
	var arr: Array = talent_levels.get(char_id, [])
	var n: int = Characters.talent_count(char_id)
	while arr.size() < n:
		arr.append(0)
	return arr

# 取某人物在当前天赋等级下的最终数值（生命值/移速/手雷伤害/导弹伤害 + 各项乘区）
func char_stats(char_id: String) -> Dictionary:
	return Characters.stats_for(char_id, char_talent_lvs(char_id))

# 升级某人物「某一天赋(idx)」：只提升该天赋等级，不碰其他数值项
# 花费：精魂（Characters.talent_soul_cost），不再消耗金币
# 返回是否升级成功（精魂不足 / 已满级 / 该人物没有该天赋 → false）
func upgrade_talent(char_id: String, idx: int = 0) -> bool:
	if not Characters.has_talent(char_id):
		return false
	if idx < 0 or idx >= Characters.talent_count(char_id):
		return false
	var lv := char_talent_lv(char_id, idx)
	if lv >= Characters.talent_max_level(char_id, idx):
		return false
	var cost := Characters.talent_soul_cost(lv)
	if item_count("soul") < cost:
		return false
	var arr: Array = talent_levels.get(char_id, [])
	while arr.size() <= idx:
		arr.append(0)
	arr[idx] = lv + 1
	talent_levels[char_id] = arr
	remove_item("soul", cost)      # 扣精魂（金币不再参与天赋升级）
	save_profile()
	stats_changed.emit()
	return true

# 升级按钮的可用状态（精魂够 + 未满级）
func can_upgrade_talent(char_id: String, idx: int = 0) -> bool:
	if not Characters.has_talent(char_id):
		return false
	if idx < 0 or idx >= Characters.talent_count(char_id):
		return false
	var lv := char_talent_lv(char_id, idx)
	if lv >= Characters.talent_max_level(char_id, idx):
		return false
	return item_count("soul") >= Characters.talent_soul_cost(lv)

# 按解锁条件检查所有人（条件数据在 Characters.gd 的 unlock 字段）
# 用累计统计（total_kills / level_clears / chests_opened …）判断，返回本次新解锁的人物 id
func check_character_unlocks() -> Array:
	var newly: Array = []
	for cid in Characters.ORDER:
		if is_unlocked(cid):
			continue
		var stat := Characters.unlock_stat(cid)
		var need := Characters.unlock_target(cid)
		if stat == "none" or need <= 0:
			continue
		if _stat_value(stat) >= need:
			unlock_character(cid)
			newly.append(cid)
	if not newly.is_empty():
		save_profile()
	return newly

# 解锁条件的当前进度文字，例如「累计击杀 100 个丧尸（37/100）」
func unlock_progress_text(char_id: String) -> String:
	var stat := Characters.unlock_stat(char_id)
	var need := Characters.unlock_target(char_id)
	if stat == "none" or need <= 0:
		return "初始角色"
	var cur := mini(_stat_value(stat), need)
	return "%s（%d/%d）" % [Characters.unlock_text(char_id), cur, need]

# ---- 关卡解锁 ----
# STAGE_COUNT：总关卡数（LevelSelect / Main 共用）
# unlocked_stage：已解锁到的最高关（默认第 1 关）。测试时改成 10 可全部解锁预览。
# selected_stage：用户最后浏览/选中的关卡，**持久化到存档**（进度区 selected_stage）。
#   规则：进选关界面时保留上次选中的那一关；只有「通关新关卡」才把 selected_stage
#   推进到刚通关的那一关（见 unlock_stage 的 s 参数）。范围钳在 1 ~ unlocked_stage，
#   避免存档里的旧值越界（例如回退档或解锁数被下调）。
const STAGE_COUNT := 25
var unlocked_stage := 1     # 已解锁到的最高关卡号（1 ~ STAGE_COUNT）
var selected_stage := 1     # 当前选中的关卡号（1 ~ unlocked_stage），已落盘
# 某关是否已解锁：关卡号不超过「已解锁到的最高关」即为已解锁。
func stage_unlocked(s: int) -> bool:
	return s <= unlocked_stage
# 通关后解锁下一关。
#   s：刚通关的关卡号（调用方传 selected_stage + 1）。
#   保护①：只有 s > unlocked_stage 才推进，重复通关/重玩不会把进度改小。
#   保护②：mini(s, STAGE_COUNT) 钳上限，通关最后一关也不会越界成 26。
#   副作用：仅在「解锁了新关」时顺带把 selected_stage 推进到新解锁的那一关，
#          这是全项目**唯一**会改写 selected_stage 的地方（其余写入走 set_selected_stage）。
func unlock_stage(s: int):
	if s > unlocked_stage:
		unlocked_stage = mini(s, STAGE_COUNT)
		if selected_stage < unlocked_stage:
			selected_stage = unlocked_stage
		save_profile()      # 进度变了必须立刻落盘，避免退出游戏后丢进度

# 记住用户最后选中的关卡。
#   调用方：level_select 点关卡圆圈 / 切换世界 / 点「开始」，main 的胜利面板「下一关」。
#   为何要单独开这个接口：直接给 selected_stage 赋值**不会落盘**，
#   退到主界面甚至完全退出游戏后重进就会丢失选中关。本封装负责钳范围 + 立即存档。
#   范围：钳到 1 ~ unlocked_stage，防止选到尚未解锁的关卡。
#   副作用：值没变时直接返回，不做无谓的写盘。
func set_selected_stage(s: int) -> void:
	var v := clampi(s, 1, unlocked_stage)
	if v == selected_stage:
		return
	selected_stage = v
	save_profile()


# ---- 设置：音量 / 亮度 ----
# ui_volume   : 主界面（Hub/关卡选择等菜单）音量 0~100
# game_volume : 游戏界面（Main 战斗场景）音量 0~100
# brightness  : 亮度 0~100（100 = 正常不压暗，越低越暗）
var ui_volume := 80.0
var game_volume := 80.0
var brightness := 100.0

var _brightness_layer: CanvasLayer = null
var _brightness_rect: ColorRect = null
const SETTINGS_PATH := "user://settings.cfg"

# ---- 宝箱系统 ----
# 四种宝箱：木/银/金/传奇。概率之和 35+30+25+10 = 100%。
# unlock_sec：解锁所需时间（秒）；reward_*：开启后获得的奖励；color：图标颜色。
const CHEST_DEFS := {
	"wood":      {"name": "木宝箱",   "prob": 0.35, "unlock_sec": 300,   "reward_gold": 640,  "reward_diamond": 0,  "color": Color(0.55, 0.36, 0.18)},
	"silver":    {"name": "银宝箱",   "prob": 0.30, "unlock_sec": 3600,  "reward_gold": 1600, "reward_diamond": 0,  "color": Color(0.75, 0.78, 0.85)},
	"gold":      {"name": "金宝箱",   "prob": 0.25, "unlock_sec": 10800, "reward_gold": 4000, "reward_diamond": 0,  "color": Color(0.95, 0.75, 0.15)},
	"legendary": {"name": "传奇宝箱", "prob": 0.10, "unlock_sec": 28800, "reward_gold": 8000, "reward_diamond": 40, "color": Color(0.62, 0.30, 0.90)},
}
const CHEST_ORDER := ["wood", "silver", "gold", "legendary"]
const CHEST_SLOT_COUNT := 4
const CHEST_KILL_INTERVAL := 50      # 每累计击杀多少丧尸得一个宝箱
const CHEST_PATH := "user://chests.cfg"

# chest_kill_count：距下一个宝箱的累计击杀数（跨场景持久）
var chest_kill_count := 0
# chests：4 个槽，元素为 null（空）或 {"type":String, "unlock_end":int(毫秒时间戳,0=未开始解锁)}
var chests: Array = [null, null, null, null]

# 注意：这里不能叫 _ready（文件末尾已有一个 _ready 用于读玩家存档），
# 由那个 _ready 调用本函数完成设置初始化
func _init_settings():
	load_settings()
	load_chests()
	load_tasks()
	load_bag()
	_build_brightness_overlay()
	set_brightness(brightness)

# 0~100 → 音量 db（0 = 静音 -80db）
# 音量 0~100 转成 Godot 音频总线分贝。<=0 直接静音（-80dB 是 Godot 可表示的最低值，约等于无声）；
# 其余用 linear_to_db 把 0~1 的线性比例转成分贝（对数曲线，更符合人耳对响度的感知）。
func volume_to_db(v: float) -> float:
	if v <= 0.0:
		return -80.0
	return linear_to_db(v / 100.0)

func apply_ui_volume():
	AudioServer.set_bus_volume_db(0, volume_to_db(ui_volume))

func apply_game_volume():
	AudioServer.set_bus_volume_db(0, volume_to_db(game_volume))

# 亮度：用一层全局黑色遮罩的透明度来压暗画面（鼠标穿透，不影响点击）
# 设置亮度（0~100，100=正常）。亮度越低 → 黑色遮罩越不透明 → 画面越暗。
# 0.75 是压暗上限：即便亮度调到 0，遮罩最多 75% 透明黑，留一点可见度不至于全黑屏。
func set_brightness(v: float):
	brightness = clamp(v, 0.0, 100.0)
	if _brightness_rect != null:
		_brightness_rect.color = Color(0, 0, 0, (100.0 - brightness) / 100.0 * 0.75)

func _build_brightness_overlay():
	_brightness_layer = CanvasLayer.new()
	_brightness_layer.name = "BrightnessOverlay"
	_brightness_layer.layer = 128
	add_child(_brightness_layer)
	_brightness_rect = ColorRect.new()
	_brightness_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brightness_layer.add_child(_brightness_rect)

func save_settings():
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "ui_volume", ui_volume)
	cfg.set_value("settings", "game_volume", game_volume)
	cfg.set_value("settings", "brightness", brightness)
	cfg.save(SETTINGS_PATH)

func load_settings():
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	ui_volume = float(cfg.get_value("settings", "ui_volume", ui_volume))
	game_volume = float(cfg.get_value("settings", "game_volume", game_volume))
	brightness = float(cfg.get_value("settings", "brightness", brightness))

# ---- 宝箱逻辑 ----
# 按概率随机抽一种宝箱类型
func roll_chest_type() -> String:
	var r := randf() * 100.0
	var acc := 0.0
	for t in CHEST_ORDER:
		acc += CHEST_DEFS[t]["prob"] * 100.0
		if r < acc:
			return t
	return "wood"

# 找一个空槽放入随机宝箱；满则返回 -1
func add_chest() -> int:
	for i in range(CHEST_SLOT_COUNT):
		if chests[i] == null:
			chests[i] = {"type": roll_chest_type(), "unlock_end": 0}
			save_chests()
			return i
	return -1

# 开始解锁某槽：给该槽的 unlock_end 写入「当前时间 + 解锁时长」的时间戳。
#   slot     : 槽号 0 ~ CHEST_SLOT_COUNT-1。
#   unlock_end：0 表示「未解锁」；>0 是解锁结束时刻（毫秒时间戳），到期即变为可领取。
#   用绝对时间戳而非倒计时秒数：玩家关掉游戏/关机跨过这段时间，重进仍能正确接着算剩余时间。
#
# ★ 互斥规则（2026-10-04 用户需求）：同一时间只允许 1 个宝箱在解锁。
#   校验放在**底层**而不是界面层，任何调用方（宝箱界面 / 胜利面板 / 脚本）都无法绕过。
#   返回 true = 成功开始倒计时；false = 被拒绝。
#   四种拒绝情形：① 槽号越界 ② 空槽 ③ 该槽已在解锁中 ④ 别的槽已在解锁中（互斥）。
func start_unlock(slot: int) -> bool:
	if slot < 0 or slot >= CHEST_SLOT_COUNT:
		return false                       # ① 越界
	var c = chests[slot]
	if c == null or c["unlock_end"] != 0:
		return false                       # ②空槽 或 ③本槽已在解
	# 互斥：已有别的宝箱在解锁中则拒绝（本槽自身已在解的情况上面已挡掉）
	if any_chest_unlocking():
		return false                       # ④互斥
	var sec: float = CHEST_DEFS[c["type"]]["unlock_sec"]
	c["unlock_end"] = int(Time.get_unix_time_from_system() * 1000.0) + int(sec * 1000.0)
	chests[slot] = c
	save_chests()                          # 开始时间即落盘，防止退出游戏后倒计时丢失
	return true

# 清理「同一时间多个宝箱在解锁」的非法状态。
#   背景：互斥规则加设之前，旧存档里可能已经有 2~3 个宝箱同时在倒计时（违规数据）。
#   策略：保留「剩余时间最长」的那一个（也就是快完成、最接近到手的那份，最不吃亏），
#         其余把 unlock_end 归 0 中断，退回「已就位未解锁」，玩家可随时重新点解锁。
#   返回被清理的槽号数组；无非法状态时返回空数组。只有真的清理了才落盘。
#   调用时机：打开宝箱界面时（chest_panel._ready，建界面之前先修，保证渲染即正确）。
func fix_multi_unlocking() -> Array:
	var busy: Array = []
	for i in range(CHEST_SLOT_COUNT):
		if chest_state(i) == 2:            # 2 = 解锁中
			busy.append(i)
	if busy.size() <= 1:                   # 0 个或 1 个都合法，无需处理
		return []
	# 找剩余时间最长的槽作为保留项
	var keep: int = busy[0]
	for i in busy:
		if remaining_ms(i) > remaining_ms(keep):
			keep = i
	var cleared: Array = []
	for i in busy:
		if i == keep:
			continue                       # 保留的那个不动
		var c = chests[i]
		if c != null:
			c["unlock_end"] = 0            # 中断倒计时 → 回到「已就位未解锁」，可重开
			chests[i] = c
		cleared.append(i)
	if not cleared.is_empty():
		save_chests()
	return cleared

# 查某槽当前状态。返回 0空 / 1未解锁 / 2解锁中 / 3可领取（时间到了）。
#   注意「可领取(3)」的宝箱**不占用**互斥名额——已解锁完只等玩家点领取，
#   不该再挡住别的宝箱继续解锁。
#   状态是「算出来的」而非存的：每次调用都拿当前时间戳和 unlock_end 现算，
#   所以进程重启/跨天都不会把倒计时算错。
func chest_state(slot: int) -> int:
	if slot < 0 or slot >= CHEST_SLOT_COUNT:
		return 0                              # 越界视为空槽
	var c = chests[slot]
	if c == null:
		return 0                              # 空槽
	if c["unlock_end"] == 0:
		return 1                              # 有宝箱但没开始解锁
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if now < c["unlock_end"]:
		return 2                              # 还没到结束时间 = 解锁中
	return 3                                  # 到点了 = 可领取

# 剩余毫秒数（解锁中返回正值，已完成/未解锁/空槽返回 0）。
#   界面用它刷新倒计时文字「剩余 x:xx」和进度条比例。
func remaining_ms(slot: int) -> float:
	var c = chests[slot]
	if c == null or c["unlock_end"] == 0:
		return 0.0
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return float(maxi(0, c["unlock_end"] - now))

# 找出「当前正在解锁」的槽号（0 ~ CHEST_SLOT_COUNT-1；没有任何宝箱在解则返回 -1）。
#   计时数据仍由每个槽自己存，这里只负责查询，不负责计时。
#   互斥规则（2026-10-04）的判定依据：返回值 >= 0 就说明已经有宝箱占着名额了。
#   注意互斥正式生效后，正常情况下最多只会命中一个；返回首个匹配即可。
func chest_unlocking_slot() -> int:
	for i in range(CHEST_SLOT_COUNT):
		if chest_state(i) == 2:
			return i
	return -1

# 是否有任意宝箱正在解锁（true = 已占用了唯一的解锁名额）。
#   「同一时间只能解锁一个宝箱」互斥规则的对外判定接口，被三处调用：
#     ① start_unlock() 底层拦截（真正强制生效的地方）；
#     ② chest_panel 把其余槽的「解锁」按钮置灰 + 点击时给提示；
#     ③ main.gd 胜利面板的宝箱卡片按钮置灰。
func any_chest_unlocking() -> bool:
	return chest_unlocking_slot() >= 0

# 领取宝箱：发金币/钻石 → 清空该槽 → 返回奖励字典。
#   slot    ：要领取的槽号。
#   返回值  ：{type, gold, diamond}；未就绪（状态非 3）时返回空字典 {}，调用方据此判断。
#   副作用  ：加钱/加钻、emit stats_changed（界面刷新）、记录成就统计、存档。
#   注意    ：领取会让该槽变回空槽，从而**释放互斥名额**，此时可以开始解锁新的宝箱。
func collect_chest(slot: int) -> Dictionary:
	if chest_state(slot) != 3:
		return {}
	var c = chests[slot]
	var def = CHEST_DEFS[c["type"]]
	gold += int(def["reward_gold"])
	diamonds += int(def["reward_diamond"])
	stats_changed.emit()
	record_chest_opened()      # 成就统计：累计开启宝箱数
	chests[slot] = null
	save_chests()
	save_profile()
	return {"type": c["type"], "gold": int(def["reward_gold"]), "diamond": int(def["reward_diamond"])}

func save_chests():
	var cfg := ConfigFile.new()
	for i in range(CHEST_SLOT_COUNT):
		if chests[i] == null:
			cfg.set_value("chests", "slot_%d" % i, "")
		else:
			cfg.set_value("chests", "slot_%d" % i, "%s|%d" % [chests[i]["type"], chests[i]["unlock_end"]])
	cfg.save(CHEST_PATH)

func load_chests():
	var cfg := ConfigFile.new()
	if cfg.load(CHEST_PATH) != OK:
		return
	for i in range(CHEST_SLOT_COUNT):
		var raw: String = cfg.get_value("chests", "slot_%d" % i, "")
		if raw == "":
			chests[i] = null
		else:
			var parts := raw.split("|")
			if parts.size() >= 2 and CHEST_DEFS.has(parts[0]):
				chests[i] = {"type": parts[0], "unlock_end": int(parts[1])}
			else:
				chests[i] = null

# ============================================================================
# ---- 每日任务 / 成就 ----
# ============================================================================
# 每日任务：每天 3 个，进度每天重置（按系统日期）。单个完成可领奖；
#          3 个全部完成可再领「额外奖励」。跨天自动重置。
# 成就：跨天累计统计，**分级制** —— 每条成就有多个等级（ⅠⅡⅢ…），领取当前等级奖励后
# 自动升到下一级（目标更大、奖励更厚），全部等级领完后显示「已达成」。
signal tasks_changed            # 任务进度/领奖状态变化时发射（任务面板监听刷新）

const TASKS_PATH := "user://tasks.cfg"

const DAILY_TASKS := [
	{"id": "kill20", "name": "击杀 20 个丧尸", "target": 20, "reward_gold": 300, "reward_diamond": 0},
	{"id": "coin15", "name": "捡取 15 枚金币", "target": 15, "reward_gold": 300, "reward_diamond": 0},
	{"id": "clear1", "name": "通关 1 个关卡",  "target": 1,  "reward_gold": 500, "reward_diamond": 0},
]
const DAILY_BONUS := {"reward_gold": 1000, "reward_diamond": 5}

# 分级成就：每条 = 一个统计维度；tiers 按等级递增（target 递增、奖励递增）。
# tier["name"] 是该等级的成就称号（面板显示「称号 Ⅰ/Ⅱ/Ⅲ…」）。
const ACHIEVEMENTS := [
	{"id": "kill", "stat": "total_kills", "verb": "累计击杀 %d 个丧尸", "tiers": [
		{"name": "初出茅庐",   "target": 50,    "reward_gold": 500,   "reward_diamond": 0},
		{"name": "丧尸猎人",   "target": 300,   "reward_gold": 2000,  "reward_diamond": 5},
		{"name": "丧尸天敌",   "target": 1000,  "reward_gold": 6000,  "reward_diamond": 15},
		{"name": "末日收割者", "target": 3000,  "reward_gold": 15000, "reward_diamond": 40},
		{"name": "人间灭绝者", "target": 10000, "reward_gold": 40000, "reward_diamond": 100},
	]},
	{"id": "coin", "stat": "total_coins", "verb": "累计拾取 %d 枚金币", "tiers": [
		{"name": "拾荒者",     "target": 100,  "reward_gold": 1000,  "reward_diamond": 0},
		{"name": "捡破烂专家", "target": 500,  "reward_gold": 3000,  "reward_diamond": 10},
		{"name": "金币大亨",   "target": 2000, "reward_gold": 8000,  "reward_diamond": 30},
		{"name": "末日首富",   "target": 8000, "reward_gold": 20000, "reward_diamond": 80},
	]},
	{"id": "clear", "stat": "level_clears", "verb": "累计通关 %d 次", "tiers": [
		{"name": "关卡征服者", "target": 5,   "reward_gold": 1500,  "reward_diamond": 0},
		{"name": "战区老兵",   "target": 20,  "reward_gold": 4000,  "reward_diamond": 10},
		{"name": "战区霸主",   "target": 60,  "reward_gold": 10000, "reward_diamond": 30},
		{"name": "末日战神",   "target": 150, "reward_gold": 25000, "reward_diamond": 80},
	]},
	{"id": "chest", "stat": "chests_opened", "verb": "累计开启 %d 个宝箱", "tiers": [
		{"name": "宝藏收集家", "target": 10,  "reward_gold": 2000,  "reward_diamond": 10},
		{"name": "寻宝猎人",   "target": 40,  "reward_gold": 6000,  "reward_diamond": 20},
		{"name": "开箱狂魔",   "target": 120, "reward_gold": 15000, "reward_diamond": 60},
		{"name": "宝藏大师",   "target": 300, "reward_gold": 30000, "reward_diamond": 120},
	]},
]

# ---- 累计统计（成就用，跨天持久）----
var total_kills := 0
var total_coins := 0
var level_clears := 0
var chests_opened := 0

# ---- 每日任务状态 ----
var daily_date := ""                       # 任务所属日期 "YYYY-MM-DD"
var daily_progress: Dictionary = {}        # 任务 id -> 当前进度
var daily_claimed: Array = []              # 已领奖的任务 id
var daily_bonus_claimed := false           # 额外奖励是否已领
var ach_claimed_tiers: Dictionary = {}     # 成就 id -> 已领取的等级数（0 = 一级都没领）

# ---- 商店每日限购状态 ----
# 每种商品每天只能买一次，跨天自动清空。与每日任务用同一套「日期变了就重置」的模式。
var shop_date := ""                        # 限购记录所属日期 "YYYY-MM-DD"
var shop_bought: Array = []                # 今天已购买的商品 id

# 日期变了就清空商店购买记录（新的一天重新可买）
func _ensure_shop():
	var today := Time.get_date_string_from_system()
	if shop_date == today:
		return
	shop_date = today
	shop_bought = []
	save_tasks()

# 今天还能不能买这个商品
func shop_can_buy(id: String) -> bool:
	_ensure_shop()
	return not (id in shop_bought)

# 标记该商品今天已买（不校验、不扣钱，纯记账；购买逻辑在 shop_panel.gd）
func shop_mark_bought(id: String) -> void:
	_ensure_shop()
	if not (id in shop_bought):
		shop_bought.append(id)

# 日期变了就重置每日任务（新的一天）
func _ensure_daily():
	var today := Time.get_date_string_from_system()
	if daily_date == today:
		return
	daily_date = today
	daily_progress = {}
	daily_claimed = []
	daily_bonus_claimed = false
	for t in DAILY_TASKS:
		daily_progress[t["id"]] = 0
	save_tasks()

func daily_target(id: String) -> int:
	for t in DAILY_TASKS:
		if t["id"] == id:
			return int(t["target"])
	return 0

func daily_progress_of(id: String) -> int:
	_ensure_daily()
	return int(daily_progress.get(id, 0))

func daily_done(id: String) -> bool:
	return daily_progress_of(id) >= daily_target(id)

func daily_is_claimed(id: String) -> bool:
	return id in daily_claimed

func daily_all_done() -> bool:
	for t in DAILY_TASKS:
		if not daily_done(t["id"]):
			return false
	return true

func daily_can_claim_bonus() -> bool:
	return daily_all_done() and not daily_bonus_claimed

# 累加某任务进度（封顶到目标值；已完成则不再累加）
func add_daily_progress(id: String, amount: int):
	_ensure_daily()
	var tgt := daily_target(id)
	var cur := int(daily_progress.get(id, 0))
	if cur >= tgt:
		return
	daily_progress[id] = mini(tgt, cur + amount)
	tasks_changed.emit()

# 领取单个每日任务奖励
func claim_daily(id: String) -> bool:
	_ensure_daily()
	if daily_is_claimed(id) or not daily_done(id):
		return false
	for t in DAILY_TASKS:
		if t["id"] == id:
			gold += int(t["reward_gold"])
			diamonds += int(t["reward_diamond"])
			break
	daily_claimed.append(id)
	save_tasks()
	save_profile()
	stats_changed.emit()
	tasks_changed.emit()
	return true

# 领取「3 个全完成」的额外奖励
func claim_daily_bonus() -> bool:
	_ensure_daily()
	if not daily_can_claim_bonus():
		return false
	gold += int(DAILY_BONUS["reward_gold"])
	diamonds += int(DAILY_BONUS["reward_diamond"])
	daily_bonus_claimed = true
	save_tasks()
	save_profile()
	stats_changed.emit()
	tasks_changed.emit()
	return true

# ---------------------------------------------------------------------------
# 分级成就接口：id -> 某条成就；等级从 0 开始（0 = Ⅰ 级目标进行中）。
# ach_claimed_tiers[id] = 已领取的等级数；全部领完 = ach_finished(id)。
# ---------------------------------------------------------------------------
func _ach_def(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}

func ach_tier_count(id: String) -> int:
	var d := _ach_def(id)
	return d.get("tiers", []).size()

func ach_claimed_tier(id: String) -> int:   # 已领取的等级数
	return int(ach_claimed_tiers.get(id, 0))

func ach_cur_tier(id: String) -> int:       # 当前进行中的等级下标（0 基）
	return mini(ach_claimed_tier(id), ach_tier_count(id) - 1)

func ach_finished(id: String) -> bool:      # 全部等级都领完
	return ach_claimed_tier(id) >= ach_tier_count(id)

func ach_tier_name(id: String) -> String:   # 当前等级的称号
	var d := _ach_def(id)
	var tiers: Array = d.get("tiers", [])
	if tiers.is_empty():
		return ""
	return String(tiers[ach_cur_tier(id)]["name"])

func ach_desc(id: String) -> String:        # 当前等级的目标描述
	var d := _ach_def(id)
	var tiers: Array = d.get("tiers", [])
	if tiers.is_empty():
		return ""
	return String(d.get("verb", "%d")).replace("%d", str(int(tiers[ach_cur_tier(id)]["target"])))

func _stat_value(key: String) -> int:
	match key:
		"total_kills":   return total_kills
		"total_coins":   return total_coins
		"level_clears":  return level_clears
		"chests_opened": return chests_opened
	return 0

func ach_progress(id: String) -> int:
	var d := _ach_def(id)
	if d.is_empty():
		return 0
	var tgt := int(d["tiers"][ach_cur_tier(id)]["target"])
	return mini(_stat_value(d["stat"]), tgt)

func ach_target(id: String) -> int:
	var d := _ach_def(id)
	if d.is_empty():
		return 0
	return int(d["tiers"][ach_cur_tier(id)]["target"])

func ach_reached(id: String) -> bool:       # 当前等级已达成（可领奖）
	var d := _ach_def(id)
	if d.is_empty() or ach_finished(id):
		return false
	return _stat_value(d["stat"]) >= int(d["tiers"][ach_cur_tier(id)]["target"])

# 领取当前等级奖励 → 自动升到下一级（目标/奖励/称号都升级）
func claim_achievement(id: String) -> bool:
	if ach_finished(id) or not ach_reached(id):
		return false
	var d := _ach_def(id)
	var tier: Dictionary = d["tiers"][ach_claimed_tier(id)]
	gold += int(tier["reward_gold"])
	diamonds += int(tier["reward_diamond"])
	ach_claimed_tiers[id] = ach_claimed_tier(id) + 1
	save_tasks()
	save_profile()
	stats_changed.emit()
	tasks_changed.emit()
	return true

# ---- 统计埋点（游戏里调用）----
func record_kill():
	total_kills += 1
	add_daily_progress("kill20", 1)
	save_tasks()

func record_coin_pickup():
	total_coins += 1
	add_daily_progress("coin15", 1)
	save_tasks()

func record_level_clear():
	level_clears += 1
	add_daily_progress("clear1", 1)
	save_tasks()

func record_chest_opened():
	chests_opened += 1
	save_tasks()

func save_tasks():
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "total_kills", total_kills)
	cfg.set_value("stats", "total_coins", total_coins)
	cfg.set_value("stats", "level_clears", level_clears)
	cfg.set_value("stats", "chests_opened", chests_opened)
	cfg.set_value("daily", "date", daily_date)
	cfg.set_value("daily", "claimed", ",".join(daily_claimed))
	cfg.set_value("daily", "bonus_claimed", daily_bonus_claimed)
	cfg.set_value("shop", "date", shop_date)
	cfg.set_value("shop", "bought", ",".join(shop_bought))
	for t in DAILY_TASKS:
		cfg.set_value("daily", "prog_" + t["id"], int(daily_progress.get(t["id"], 0)))
	var tier_parts: Array = []
	for k in ach_claimed_tiers.keys():
		tier_parts.append("%s:%d" % [String(k), int(ach_claimed_tiers[k])])
	cfg.set_value("ach", "tiers", ",".join(tier_parts))
	cfg.save(TASKS_PATH)

func load_tasks():
	var cfg := ConfigFile.new()
	if cfg.load(TASKS_PATH) != OK:
		_ensure_daily()
		return
	total_kills = int(cfg.get_value("stats", "total_kills", 0))
	total_coins = int(cfg.get_value("stats", "total_coins", 0))
	level_clears = int(cfg.get_value("stats", "level_clears", 0))
	chests_opened = int(cfg.get_value("stats", "chests_opened", 0))
	daily_date = String(cfg.get_value("daily", "date", ""))
	daily_bonus_claimed = bool(cfg.get_value("daily", "bonus_claimed", false))
	daily_progress = {}
	for t in DAILY_TASKS:
		daily_progress[t["id"]] = int(cfg.get_value("daily", "prog_" + t["id"], 0))
	daily_claimed = _split_ids(String(cfg.get_value("daily", "claimed", "")))
	shop_date = String(cfg.get_value("shop", "date", ""))
	shop_bought = _split_ids(String(cfg.get_value("shop", "bought", "")))
	# 分级成就：读「id:已领等级数」；旧档只有 claimed 列表 → 按旧成就 id 换算成已领等级数
	ach_claimed_tiers = {}
	var raw_tiers := String(cfg.get_value("ach", "tiers", ""))
	if raw_tiers != "":
		for kv in raw_tiers.split(","):
			var pair := kv.split(":")
			if pair.size() == 2:
				ach_claimed_tiers[pair[0]] = maxi(0, int(pair[1]))
	else:
		# 旧档迁移：kill50→击杀Ⅰ / kill300→击杀Ⅱ / coin100→金币Ⅰ / clear5→通关Ⅰ / chest10→宝箱Ⅰ
		var old_ids := _split_ids(String(cfg.get_value("ach", "claimed", "")))
		for oid in old_ids:
			match String(oid):
				"kill50":  ach_claimed_tiers["kill"]  = maxi(int(ach_claimed_tiers.get("kill", 0)), 1)
				"kill300": ach_claimed_tiers["kill"]  = maxi(int(ach_claimed_tiers.get("kill", 0)), 2)
				"coin100": ach_claimed_tiers["coin"]  = maxi(int(ach_claimed_tiers.get("coin", 0)), 1)
				"clear5":  ach_claimed_tiers["clear"] = maxi(int(ach_claimed_tiers.get("clear", 0)), 1)
				"chest10": ach_claimed_tiers["chest"] = maxi(int(ach_claimed_tiers.get("chest", 0)), 1)
	# 钳到合法等级数内（防旧档数值越界）
	for k in ach_claimed_tiers.keys():
		ach_claimed_tiers[k] = mini(int(ach_claimed_tiers[k]), ach_tier_count(String(k)))
	_ensure_daily()   # 日期变了会重置每日任务

func _split_ids(s: String) -> Array:
	var out: Array = []
	if s == "":
		return out
	for p in s.split(","):
		if p != "":
			out.append(p)
	return out

# ---- 武器解锁 ----
var unlocked_weapons = ["pistol_m1911"]

# ---- 装备栏（loadout）：4 槽，0/1 已解锁，2/3 锁定；元素为武器 id 或 "" ----
var loadout = ["pistol_m1911", "", "", ""]

# ---- 当前手持槽位（0/1）：跨场景、跨重启保留玩家选的枪 ----
var weapon_active_slot := 0

# ---- 钻石买断解锁的装备格（初始 2 个之外的额外槽，slot 下标）----
# 例：[2, 3] 表示槽 2、槽 3 已花钻石解锁。持久化到 player_profile.cfg。
var weapon_unlocked_slots: Array = []

# 某装备格是否已用钻石买断解锁（前 INITIAL_UNLOCKED_SLOTS 个初始免费，不在此列）
func is_weapon_slot_unlocked(slot: int) -> bool:
	return int(slot) in weapon_unlocked_slots

# 标记某装备格为「已钻石解锁」（去重，不主动落盘）
func unlock_weapon_slot(slot: int):
	if not int(slot) in weapon_unlocked_slots:
		weapon_unlocked_slots.append(int(slot))

# ---- 武器强化（升级）----
# 已购枪械可花金币或钻石升级，最高 5 级，每级同时提升 伤害/射速/弹夹/换弹速度。
const WEAPON_MAX_UPGRADE := 5                    # 单把武器最高强化等级
var weapon_upgrade_levels: Dictionary = {}       # 武器id -> 强化等级（0 = 未强化）

# 升到「下一级（当前等级 level）」所需的金币 / 钻石（等级越高越贵）
# 升到「下一级（当前等级 level）」所需金币：
#   (200 + 武器售价) × 0.30 → 基础成本（200 是固定底数，0.30=30% 售价系数，越贵枪越强越贵）
#   × (level + 1)        → 每升一级更贵（level 从 0 起，升 1 级时 ×2、升 2 级时 ×3…）
#   再 × upgrade_cost_mul（维修工天赋减免，下限 0.4）；最后 maxi(1, ...) 保证至少 1 金。
func weapon_upgrade_gold_cost(id: String, level: int) -> int:
	var price: int = int(Weapons.DATA.get(id, {}).get("price", 0))
	var base: float = float(int((200 + price) * 0.30) * (level + 1))
	# 维修工「精工改装」：强化费用按比例减免（显示与实际扣费都走这里，一处生效）
	var mul: float = float(char_stats(selected_character).get("upgrade_cost_mul", 1.0))
	return maxi(1, int(round(base * mul)))

# 钻石强化价 = 金币价 / 120。120 是「120 金 ≈ 1 钻」的资源兑换比（与游戏内比价一致）。
# maxi(1, ...) 保证至少 1 钻，不会出现 0 钻就能强化的廉价情况。
func weapon_upgrade_diamond_cost(id: String, level: int) -> int:
	return maxi(1, weapon_upgrade_gold_cost(id, level) / 120)

# 是否可强化：已拥有 + 未满级 + 金币或钻石够其一
func can_upgrade_weapon(id: String) -> bool:
	if not Weapons.is_unlocked(id):
		return false
	var lv: int = int(weapon_upgrade_levels.get(id, 0))
	if lv >= WEAPON_MAX_UPGRADE:
		return false
	var gc: int = weapon_upgrade_gold_cost(id, lv)
	var dc: int = weapon_upgrade_diamond_cost(id, lv)
	return gold >= gc or diamonds >= dc

# 强化武器（kind = "gold" 或 "diamond"），成功返回 true
func upgrade_weapon(id: String, kind: String) -> bool:
	if not Weapons.is_unlocked(id):
		return false
	var lv: int = int(weapon_upgrade_levels.get(id, 0))
	if lv >= WEAPON_MAX_UPGRADE:
		return false
	var gc: int = weapon_upgrade_gold_cost(id, lv)
	var dc: int = weapon_upgrade_diamond_cost(id, lv)
	if kind == "gold":
		if gold < gc:
			return false
		gold -= gc
	elif kind == "diamond":
		if diamonds < dc:
			return false
		diamonds -= dc
	else:
		return false
	weapon_upgrade_levels[id] = lv + 1
	save_profile()
	stats_changed.emit()
	return true

# ---- 背包（bag）：40 格，前 20 格免费，后 20 格每 5 格解锁 ----
const BAG_TOTAL := 40
const BAG_FREE := 20
var bag_unlocked := 20

# ---- 背包内容（物品）：一格放一种物品的一叠 ----
# bag_items 存 {物品id: 数量}，bag_order 存占格顺序（第 i 个元素占第 i 个格子）。
const BAG_PATH := "user://bag.cfg"
const ITEM_DEFS := {
	"rotten_meat": {
		"name": "腐肉",
		"icon": "res://art/item_rotten_meat.png",
		"use": "开垦和升级农田",
		"source": "击杀丧尸有 10% 概率掉落",
		"color": Color(0.58, 0.30, 0.32),
	},
	"medkit": {
		"name": "医疗包",
		"icon": "res://art/item_medkit.png",
		"use": "局内按 F 使用，恢复 50 生命",
		"source": "局内 B 商店用金币购买",
		"color": Color(0.20, 0.78, 0.36),
	},
	"soul": {
		"name": "精魂",
		"icon": "res://art/item_soul.png",
		"use": "升级人物天赋",
		"source": "击败关卡 BOSS 掉落",
		"color": Color(0.45, 0.65, 0.95),
	},
	# ---- 农作物：家园收获后进背包，可在背包里卖出换金币（售价见 ITEM_SELL_PRICE）----
	"potato": {
		"name": "土豆",
		"icon": "res://art/item_potato.png",
		"use": "在背包里卖出换金币（单价 %d）" % int(ITEM_SELL_PRICE["potato"]),
		"source": "家园农田收获（生长 60 秒）",
		"color": Color(0.78, 0.61, 0.42),
	},
	"tomato": {
		"name": "番茄",
		"icon": "res://art/item_tomato.png",
		"use": "在背包里卖出换金币（单价 %d）" % int(ITEM_SELL_PRICE["tomato"]),
		"source": "家园农田收获（生长 180 秒）",
		"color": Color(0.84, 0.24, 0.19),
	},
	"watermelon": {
		"name": "西瓜",
		"icon": "res://art/item_watermelon.png",
		"use": "在背包里卖出换金币（单价 %d）" % int(ITEM_SELL_PRICE["watermelon"]),
		"source": "家园农田收获（生长 600 秒）",
		"color": Color(0.34, 0.67, 0.31),
	},
}
# 击杀丧尸掉落腐肉的概率
const ROTTEN_MEAT_DROP_CHANCE := 0.10
var bag_items := {}          # {物品id: 数量}
var bag_order: Array = []    # 占用格子的物品 id，按获得先后排列

signal bag_changed           # 背包内容变化时发射（拾取/消耗），背包界面监听刷新

func item_def(id: String) -> Dictionary:
	return ITEM_DEFS.get(id, {})

func item_name(id: String) -> String:
	return String(item_def(id).get("name", id))

# 背包里已占用的格子数
func bag_used_slots() -> int:
	return bag_order.size()

# 某个物品的持有数量
func item_count(id: String) -> int:
	return int(bag_items.get(id, 0))

# 往背包加物品（拾取腐肉时调用）。没空格且是新物品时返回 false（掉落物丢弃）。
func add_item(id: String, n: int = 1) -> bool:
	if n <= 0 or not ITEM_DEFS.has(id):
		return false
	if bag_items.has(id):
		bag_items[id] = int(bag_items[id]) + n
	else:
		if bag_order.size() >= bag_unlocked:
			return false        # 背包已满，放不下新物品
		bag_items[id] = n
		bag_order.append(id)
	save_bag()
	bag_changed.emit()
	return true

# ============================================================================
# ---- 无尽模式进度（跨场景、跨重启持久）----
#   best_wave : 历史最高波次（选关/结算界面展示）
#   endless_kills : 无尽模式累计击杀（成就/统计用）
#   endless_diamond : 无尽模式累计获得的钻石（统计用）
# ============================================================================
var best_wave: int = 0
var endless_kills: int = 0
var endless_diamond: int = 0
var endless_mode := false          # 本局是否无尽模式（由副本入口置位，主线保持 false）

# 记录一次无尽模式的结算结果：刷新最高波次、累计统计。
# wave 为本局到达的最高波次，kills 为本局击杀，diamond 为本局获得钻石。
func record_endless(wave: int, kills: int, diamond: int):
	best_wave = maxi(best_wave, wave)
	endless_kills += maxi(0, kills)
	endless_diamond += maxi(0, diamond)
	save_profile()
	stats_changed.emit()

# 消耗物品（农田玩法后续使用）
func remove_item(id: String, n: int = 1) -> bool:
	if item_count(id) < n:
		return false
	bag_items[id] = int(bag_items[id]) - n
	if int(bag_items[id]) <= 0:
		bag_items.erase(id)
		bag_order.erase(id)
	save_bag()
	bag_changed.emit()
	return true

# 物品图标：优先读 art/ 里的原始 PNG；缺文件时画一个纯色方块兜底
func item_icon_tex(id: String) -> Texture2D:
	var d := item_def(id)
	var path := String(d.get("icon", ""))
	if path != "":
		var t := _tex_from_png(path)
		if t != null:
			return t
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = d.get("color", Color(0.6, 0.6, 0.6))
	for y in range(6, s - 6):
		for x in range(6, s - 6):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func save_bag():
	var cfg := ConfigFile.new()
	for id in bag_order:
		cfg.set_value("items", String(id), int(bag_items.get(id, 0)))
	cfg.set_value("bag", "order", ",".join(bag_order))
	cfg.save(BAG_PATH)

func load_bag():
	var cfg := ConfigFile.new()
	if cfg.load(BAG_PATH) != OK:
		return
	bag_items = {}
	bag_order = []
	for id in _split_ids(String(cfg.get_value("bag", "order", ""))):
		if not ITEM_DEFS.has(id):
			continue
		var n := int(cfg.get_value("items", id, 0))
		if n > 0:
			bag_items[id] = n
			bag_order.append(id)

# ---- 玩家进度 ----
var level := 1
var exp := 0
const MAX_LEVEL := 100          # 等级上限（封顶 100 级）

# 升到「下一级」所需的经验：1000 + 当前等级 × 100（等级越高越难升）
func exp_per_level(lv: int) -> int:
	return 1000 + lv * 100

# 距离下一级还差多少经验（满级返回 0）
func exp_remaining() -> int:
	if level >= MAX_LEVEL:
		return 0
	return maxi(0, exp_per_level(level) - exp)

# 当前经验条比例（满级返回 1.0）
func exp_progress_ratio() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	return clampf(float(exp) / float(exp_per_level(level)), 0.0, 1.0)

func is_max_level() -> bool:
	return level >= MAX_LEVEL
# 升级后待弹窗展示的等级队列（局内升级时入队，返回主界面由 hub 顺序弹窗消费）
var pending_levelups: Array = []

# ---- 家园（农田系统）----
const HOMESTEAD_PLOTS := 10          # 农田总数
const HOMESTEAD_MAX_LEVEL := 10      # 单块农田最高等级
var homestead_unlocked := 1          # 已解锁的农田数（起始 1 块，1..10）
var homestead_levels: Dictionary = {} # 农田号(1..10) -> 等级（已解锁默认 1）
var gold := 0                  # 金币总数（金100 + 银10 累计）
var diamonds := 0             # 钻石数量
var grenade_ammo := 0        # 手雷持有数量（消耗品，局内按 G 投掷）
var missile_ammo := 0        # 支援导弹持有数量（消耗品，局内按 H 呼叫）
# ★ 腐肉（rotten_meat）是背包里的「物品」，不是顶栏资源——
#   由击杀丧尸掉在地上、走过去捡入背包（见 drop_item.gd / main.gd）。
#   家园解锁/升级消耗的是背包里的该物品（见下面的 remove_item 调用）。

const GOLD_VALUE := 100        # 金币（金色）价值
const SILVER_VALUE := 10       # 金币（银色）价值

signal stats_changed           # 等级/经验/金币/钻石变化时发射，HUD 监听刷新
signal level_up(level: int)     # 每升一级发射（参数=新等级），hub 监听弹提示框

# 加经验，够「本等级对应的 exp_per_level」自动升级；最高到 MAX_LEVEL。
# 每升一级奖励「等于新等级数」的钻石。
# 钻石不在局内发放：只把新等级入 pending_levelups 队列（等级数字即应得钻石数），
# 待返回主界面（hub）随升级提示框逐个累加到账号，避免战斗中干扰 + 让奖励随弹窗递增。
func add_exp(amount: int):
	# 程序员「算法优化」：击杀经验按比例加成（只被 main.gd 的击杀逻辑调用，不放大任务奖励）
	var mul: float = float(char_stats(selected_character).get("exp_mul", 1.0))
	exp += int(round(float(amount) * mul))
	var leveled := false
	while level < MAX_LEVEL and exp >= exp_per_level(level):
		exp -= exp_per_level(level)
		level += 1
		pending_levelups.append(level)     # 入队：钻石随返回主界面弹窗发放
		level_up.emit(level)               # 若主界面已打开则当场弹
		leveled = true
	if leveled:
		# 待弹窗队列需持久化，避免局内升级后直接退出游戏导致奖励丢失
		save_profile()
	stats_changed.emit()

# 击杀掉落面值：20% 出 100 金币、80% 出 10 金币。
# ★ 只返回面值，不直接入账——金币会掉在路面上，需要玩家走过去捡（见 coin.gd）
func roll_coin_value() -> int:
	if randf() < 0.2:
		return GOLD_VALUE
	return SILVER_VALUE

# 金币入账（玩家捡到金币时调用）
func add_gold(amount: int):
	# 程序员「自动化脚本」：关卡内拾取金币按比例加成
	# （add_gold 只被 coin.gd 的拾取逻辑调用，任务/成就奖励不走这里，不会被放大）
	var mul: float = float(char_stats(selected_character).get("coin_mul", 1.0))
	gold += int(round(float(amount) * mul))
	save_profile()
	stats_changed.emit()

func add_diamond(amount: int):
	diamonds += amount
	save_profile()
	stats_changed.emit()

# ===== 图标生成（金币/钻石，用代码画，不依赖图片文件）=====
# 从 res:// 原始 PNG 文件加载纹理（读原始字节，不走 .import，无需编辑器导入）
func _tex_from_png(p: String) -> Texture2D:
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK:
		return null
	return ImageTexture.create_from_image(img)

func _fill_circle(img: Image, col: Color, r: int):
	var c := float(r)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var dx = x - c + 0.5
			var dy = y - c + 0.5
			if dx*dx + dy*dy <= (r-1)*(r-1):
				img.set_pixel(x, y, col)

func gold_icon_tex() -> Texture2D:
	# 优先用 art/coin_gold.png（金圆+美元符号，PIL 生成）
	var t := _tex_from_png("res://art/coin_gold.png")
	if t != null:
		return t
	# 兜底：代码画纯金圆
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_fill_circle(img, Color(1.0, 0.8, 0.1), s/2)
	return ImageTexture.create_from_image(img)

func silver_icon_tex() -> Texture2D:
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_fill_circle(img, Color(0.82, 0.84, 0.9), s/2)
	return ImageTexture.create_from_image(img)

func diamond_icon_tex() -> Texture2D:
	# 优先用 art/diamond_red.png（红色五边形，PIL 生成）
	var t := _tex_from_png("res://art/diamond_red.png")
	if t != null:
		return t
	# 兜底：代码画红色菱形
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var c := float(s)/2.0
	for y in range(s):
		for x in range(s):
			var dx = abs(x - c + 0.5)
			var dy = abs(y - c + 0.5)
			if dx + dy <= c - 1.0:
				img.set_pixel(x, y, Color(0.85, 0.15, 0.15))
	return ImageTexture.create_from_image(img)

# 在 parent 上构建「金币 + 钻石」一行 HUD，返回标签引用字典
# parent 可以是 Control（主界面）或 CanvasLayer（游戏界面）
# 每个货币 = 胶囊形（操场跑道形）底框 PanelContainer，自动适应数字位数
func _make_pill(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(17)   # 高度 34 的一半 → 正操场形
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p

func _make_currency_pill(icon_tex: Texture2D, text: String, border: Color) -> Array:
	var pill := _make_pill(border)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)   # 默认 BEGIN：图标贴胶囊最左
	var icon := TextureRect.new()
	icon.texture = icon_tex
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)
	pill.add_child(box)
	return [pill, label]

func build_currency_hud(parent: Node, start_x := 0.0, y := 16.0) -> Dictionary:
	var gray := Color(0.62, 0.64, 0.68, 0.9)   # 灰色边框
	# 金币胶囊（最小宽度 130，拉长）
	var g := _make_currency_pill(gold_icon_tex(), "%d" % gold, gray)
	g[0].custom_minimum_size = Vector2(130, 0)
	g[0].position = Vector2(start_x, y - 4)
	parent.add_child(g[0])
	# 钻石胶囊，间隔 30 防重叠（130+30=160）
	var d := _make_currency_pill(diamond_icon_tex(), "%d" % diamonds, gray)
	d[0].custom_minimum_size = Vector2(130, 0)
	d[0].position = Vector2(start_x + 160, y - 4)
	parent.add_child(d[0])
	return {"gold": g[1], "diamond": d[1]}

# ============================================================================
# ---- 家园（农田系统）逻辑 ----
# ============================================================================
# 农田 1..HOMESTEAD_PLOTS；homestead_unlocked = 已解锁数量。
# 解锁只能按顺序：只有「当前已解锁数 + 1」那块可解锁（其前一块必须已解锁）。
# 解锁消耗金币 + 腐肉；升级（已解锁块）只消耗腐肉。

# 某块农田的当前等级（已解锁默认 1，锁定返回 0）
func homestead_level(p: int) -> int:
	if p < 1 or p > HOMESTEAD_PLOTS:
		return 0
	if p <= homestead_unlocked:
		return int(homestead_levels.get(p, 1))
	return 0

# 解锁「下一关」所需：金币 + 背包里的腐肉，随序号线性增长
# 解锁「第 p 块」农田的花费：金币 150×(p-1)、腐肉 10×(p-1)。
# p 从 2 起（第 1 块初始免费），故第 2 块=150 金/10 肉、第 3 块=300 金/20 肉，线性递增。
func plot_unlock_cost(p: int) -> Dictionary:
	return {"gold": 150 * (p - 1), "meat": 10 * (p - 1)}

func can_unlock_next() -> bool:
	var p := homestead_unlocked + 1
	if p > HOMESTEAD_PLOTS:
		return false
	var c := plot_unlock_cost(p)
	return gold >= int(c["gold"]) and item_count("rotten_meat") >= int(c["meat"])

# 解锁下一关（自动扣费 + 等级置 1），成功返回 true
func unlock_next_plot() -> bool:
	var p := homestead_unlocked + 1
	if p > HOMESTEAD_PLOTS:
		return false
	var c := plot_unlock_cost(p)
	if gold < int(c["gold"]) or item_count("rotten_meat") < int(c["meat"]):
		return false
	gold -= int(c["gold"])
	remove_item("rotten_meat", int(c["meat"]))
	homestead_unlocked = p
	homestead_levels[p] = 1
	save_profile()
	stats_changed.emit()
	return true

# 已解锁农田升到下一级所需腐肉（= 10 × 当前等级），从背包物品扣
# 已解锁农田升一级所需腐肉 = 10 × 当前等级。等级越高升级越贵（10/20/30…，满级 10 级=100 肉）。
func plot_upgrade_cost(p: int) -> int:
	return 10 * homestead_level(p)

func can_upgrade_plot(p: int) -> bool:
	if p > homestead_unlocked:
		return false
	if homestead_level(p) >= HOMESTEAD_MAX_LEVEL:
		return false
	return item_count("rotten_meat") >= plot_upgrade_cost(p)

# 升级已解锁农田（只扣背包腐肉），成功返回 true
func upgrade_plot(p: int) -> bool:
	if p > homestead_unlocked:
		return false
	var lv := homestead_level(p)
	if lv >= HOMESTEAD_MAX_LEVEL:
		return false
	var cost := 10 * lv
	if item_count("rotten_meat") < cost:
		return false
	remove_item("rotten_meat", cost)
	homestead_levels[p] = lv + 1
	save_profile()
	stats_changed.emit()
	return true

# ============================================================================
# ---- 农田种植（作物系统）----
# ============================================================================
# 每块已解锁农田可种一种作物：种下去开始倒计时生长，成熟后**收获作物进背包**，
# 作物可以在背包里按卖出价售出换金币（见 sell_item / ITEM_SELL_PRICE）。
# 农田等级提升产量：每级 +20%（FARM_YIELD_PER_LEVEL），产量=作物个数（整数）。
# 农田状态：0=锁定 1=空地 2=生长中 3=已成熟。
# 注意：yield_gold 已改为 yield_count（收获「几个」），卖出价统一走 ITEM_SELL_PRICE，
#      这样调整售价只改一处，不必回到每个作物里改。
const CROPS := {
	"potato":     {"name": "土豆", "grow_sec": 60,  "yield_count": 3},
	"tomato":     {"name": "番茄", "grow_sec": 180, "yield_count": 2},
	"watermelon": {"name": "西瓜", "grow_sec": 600, "yield_count": 1},
}
const CROP_ORDER := ["potato", "tomato", "watermelon"]
const FARM_YIELD_PER_LEVEL := 0.2    # 农田每级提高的产量

# 作物卖出价（金币/个）。与原yield_gold 数值保持一致：土豆30 / 番茄100 / 西瓜400。
# 只在这里调价就能同时改「收获价值」和「背包售价」。
const ITEM_SELL_PRICE := {
	"potato": 30,
	"tomato": 100,
	"watermelon": 400,
}

# farm_plots: 农田号 -> {"crop": 作物id, "ready_end": 毫秒时间戳}
var farm_plots: Dictionary = {}

# 0=锁定 1=空地 2=生长中 3=已成熟
func plot_state(p: int) -> int:
	if p > homestead_unlocked:
		return 0
	if not farm_plots.has(p):
		return 1
	var d: Dictionary = farm_plots[p]
	if String(d.get("crop", "")) == "":
		return 1
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return 3 if now >= int(d["ready_end"]) else 2

# 种植（只对空地有效），成功返回 true
func plant_crop(p: int, crop_id: String) -> bool:
	if plot_state(p) != 1 or not CROPS.has(crop_id):
		return false
	var grow := float(CROPS[crop_id]["grow_sec"])
	farm_plots[p] = {"crop": crop_id, "ready_end": int(Time.get_unix_time_from_system() * 1000.0) + int(grow * 1000.0)}
	save_profile()
	stats_changed.emit()
	return true

# 剩余毫秒（生长中返回正值，成熟/空地返回 0）
func plot_remaining_ms(p: int) -> float:
	if not farm_plots.has(p):
		return 0.0
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return float(maxi(0, int(farm_plots[p]["ready_end"]) - now))

# 生长进度 0~1（用于进度条）
func plot_grow_ratio(p: int) -> float:
	if plot_state(p) != 2:
		return 0.0
	var crop_id := String(farm_plots[p]["crop"])
	var total := float(CROPS[crop_id]["grow_sec"]) * 1000.0
	return clampf(1.0 - plot_remaining_ms(p) / total, 0.0, 1.0)

# 某作物在某农田的**产量**（基础个数 × 等级加成，四舍五入且至少 1 个）
func crop_yield(p: int, crop_id: String) -> int:
	var base := int(CROPS[crop_id]["yield_count"])
	var lv := homestead_level(p)
	return maxi(1, int(round(float(base) * (1.0 + FARM_YIELD_PER_LEVEL * (lv - 1)))))

# 某作物单个的卖出价（金币）。不在ITEM_SELL_PRICE 里的物品返回 0 = 不可卖。
func item_sell_price(item_id: String) -> int:
	return int(ITEM_SELL_PRICE.get(item_id, 0))

# 该物品是否可在背包里出售（ITEM_SELL_PRICE 里有价且当前持有 > 0）
func item_sellable(item_id: String) -> bool:
	return item_sell_price(item_id) > 0 and item_count(item_id) > 0

# 出售背包里的物品：扣掉 n 个，按 ITEM_SELL_PRICE 折算金币加给玩家。
# 返回实际卖出数量（0 = 不可卖 / 持有不足 / 背包里没有）。
# 由背包界面的「卖出」按钮调用。
func sell_item(item_id: String, n: int = 1) -> int:
	var price := item_sell_price(item_id)
	if price <= 0 or n <= 0:
		return 0
	var have := item_count(item_id)
	if have <= 0:
		return 0
	var sell_n: int = mini(n, have)
	if not remove_item(item_id, sell_n):
		return 0
	# 卖出所得直接加金币，**不经过 add_gold**：add_gold 带程序员「自动化脚本」的拾取加成，
	# 那是给「关卡内拾取」设计的，卖出的价不该被放大。
	gold += price * sell_n
	save_profile()
	stats_changed.emit()
	return sell_n

# 一键卖出某物品的全部持有数量，返回卖出个数（0 = 不可卖）。背包界面「全部卖出」用。
func sell_all_of(item_id: String) -> int:
	return sell_item(item_id, item_count(item_id))

# 收获（成熟才能收）：清空农田，把作物**放进背包**，返回收获的作物个数。
# 背包满时返回 0（农田不收，避免作物凭空消失）。
func harvest(p: int) -> int:
	if plot_state(p) != 3:
		return 0
	var crop_id := String(farm_plots[p]["crop"])
	var n := crop_yield(p, crop_id)
	# 背包放不下就先不收，让玩家清背包（提示由调用方处理）
	if not add_item(crop_id, n):
		return 0
	farm_plots.erase(p)
	save_profile()
	stats_changed.emit()
	return n

# 一键收获：把全部已成熟（state==3）的农田一次性收进背包，返回收获的作物总数。
# 背包满的田会跳过（add_item 返回 false 时harvest 返回 0，不清空农田）。
func harvest_all() -> int:
	var total := 0
	for p in range(1, 11):
		if plot_state(p) == 3:
			total += harvest(p)
	return total

# ============================================================================
# ---- 玩家资料（个人账号界面：ID + 头像，ConfigFile 持久化）----
# ============================================================================
const AVATAR_COUNT := 6
const PROFILE_PATH := "user://player_profile.cfg"
var player_id := "幸存者_0001"
var avatar_index := 1   # 对应 res://art/avatars/avatar_N.png

func _ready():
	load_profile()
	_init_settings()

func load_profile():
	# 弹药初始库存：老档缺字段、以及全新档（根本没有存档文件）都按此补偿，
	# 避免技能从「免费无限」改成消耗品后玩家突然无法使用（手雷 10 / 导弹 3）。
	grenade_ammo = 10
	missile_ammo = 3
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		player_id = cf.get_value("profile", "player_id", player_id)
		avatar_index = clampi(int(cf.get_value("profile", "avatar_index", avatar_index)), 1, AVATAR_COUNT)
		var raw_loadout: String = cf.get_value("profile", "loadout", "")
		if raw_loadout != "":
			var parts := raw_loadout.split(",")
			if parts.size() == 4:
				loadout = Array(parts)
		weapon_active_slot = clampi(int(cf.get_value("profile", "weapon_active_slot", weapon_active_slot)), 0, Weapons.LOADOUT_SLOT_COUNT - 1)
		bag_unlocked = clampi(int(cf.get_value("profile", "bag_unlocked", bag_unlocked)), BAG_FREE, BAG_TOTAL)
		selected_character = cf.get_value("profile", "selected_character", selected_character)
		# 已解锁人物（至少保留司机）
		var raw_chars := String(cf.get_value("profile", "unlocked_characters", ""))
		if raw_chars != "":
			unlocked_characters = _split_ids(raw_chars)
		if not "driver" in unlocked_characters:
			unlocked_characters.append("driver")
		# 天赋等级（存成 "driver:2|3,doctor:5|0"；旧版单值 "driver:2" 也兼容）
		talent_levels = {}
		var raw_tal := String(cf.get_value("profile", "talent_levels", ""))
		if raw_tal != "":
			for p in raw_tal.split(","):
				if p == "":
					continue
				var kv := p.split(":")
				if kv.size() >= 2:
					var arr: Array = []
					for s in kv[1].split("|"):
						s = s.strip_edges()
						if s != "":
							arr.append(int(s))
					if not arr.is_empty():
						talent_levels[kv[0]] = arr
		# 新字段缺失时保留默认值，兼容旧版本 player_profile.cfg。
		gold = maxi(0, int(cf.get_value("progress", "gold", gold)))
		diamonds = maxi(0, int(cf.get_value("progress", "diamonds", diamonds)))
		grenade_ammo = maxi(0, int(cf.get_value("progress", "grenade_ammo", grenade_ammo)))
		missile_ammo = maxi(0, int(cf.get_value("progress", "missile_ammo", missile_ammo)))
		level = maxi(1, int(cf.get_value("progress", "level", level)))
		exp = maxi(0, int(cf.get_value("progress", "exp", exp)))
		# 升级待弹窗队列（逗号分隔的等级数字），兼容旧档缺字段
		var raw_pl := String(cf.get_value("progress", "pending_levelups", ""))
		pending_levelups = []
		if raw_pl != "":
			for s in raw_pl.split(","):
				s = s.strip_edges()
				if s != "":
					pending_levelups.append(int(s))
		unlocked_stage = clampi(int(cf.get_value("progress", "unlocked_stage", unlocked_stage)), 1, STAGE_COUNT)
		# 读回上次选中的关卡（旧档无此字段时默认沿用已解锁的最高关，不影响老存档）。
		# 必须钳到 1 ~ unlocked_stage：否则老档/回退档里存着越界值会选到锁住的关。
		selected_stage = clampi(int(cf.get_value("progress", "selected_stage", unlocked_stage)), 1, unlocked_stage)
		homestead_unlocked = clampi(int(cf.get_value("progress", "homestead_unlocked", homestead_unlocked)), 1, HOMESTEAD_PLOTS)
		homestead_levels = {}
		var raw_hl := String(cf.get_value("progress", "homestead_levels", ""))
		if raw_hl != "":
			for kv in raw_hl.split(","):
				if kv == "":
					continue
				var pair := kv.split(":")
				if pair.size() == 2:
					homestead_levels[int(pair[0])] = int(pair[1])
		# 农田种植状态（存成 "1:potato:1690000000000,2:tomato:1690000000000"）
		farm_plots = {}
		var raw_fp := String(cf.get_value("progress", "farm_plots", ""))
		if raw_fp != "":
			for kv in raw_fp.split(","):
				if kv == "":
					continue
				var parts := kv.split(":")
				if parts.size() == 3 and CROPS.has(parts[1]):
					farm_plots[int(parts[0])] = {"crop": parts[1], "ready_end": int(parts[2])}
		chest_kill_count = clampi(int(cf.get_value("progress", "chest_kill_count", chest_kill_count)), 0, CHEST_KILL_INTERVAL - 1)
		selected_stage = clampi(selected_stage, 1, unlocked_stage)
		# 无尽模式进度（缺字段时默认 0，兼容旧档）
		best_wave = maxi(0, int(cf.get_value("progress", "best_wave", best_wave)))
		endless_kills = maxi(0, int(cf.get_value("progress", "endless_kills", endless_kills)))
		endless_diamond = maxi(0, int(cf.get_value("progress", "endless_diamond", endless_diamond)))
		if cf.has_section_key("progress", "unlocked_weapons"):
			unlocked_weapons = _split_ids(String(cf.get_value("progress", "unlocked_weapons", "")))
		else:
			# 旧档没有武器解锁表：保留装备槽里有记录的武器，避免迁移后丢枪。
			for id in loadout:
				if id != "" and not id in unlocked_weapons:
					unlocked_weapons.append(id)
		if not "pistol_m1911" in unlocked_weapons:
			unlocked_weapons.append("pistol_m1911")
		# 武器强化等级（缺字段时默认空，兼容旧档）
		weapon_upgrade_levels = {}
		if cf.has_section_key("progress", "weapon_upgrade_levels"):
			for kv in String(cf.get_value("progress", "weapon_upgrade_levels", "")).split(","):
				if kv == "":
					continue
				var pair := kv.split(":")
				if pair.size() == 2:
					weapon_upgrade_levels[pair[0]] = int(pair[1])
		# 钻石买断解锁的装备格（缺字段时默认空，兼容旧档）
		weapon_unlocked_slots = []
		if cf.has_section_key("progress", "weapon_unlocked_slots"):
			for s in String(cf.get_value("progress", "weapon_unlocked_slots", "")).split(","):
				if s.strip_edges() != "":
					weapon_unlocked_slots.append(int(s))

func save_profile():
	var cf := ConfigFile.new()
	cf.set_value("profile", "player_id", player_id)
	cf.set_value("profile", "avatar_index", avatar_index)
	cf.set_value("profile", "loadout", ",".join(loadout))
	cf.set_value("profile", "weapon_active_slot", weapon_active_slot)
	cf.set_value("profile", "bag_unlocked", bag_unlocked)
	cf.set_value("profile", "selected_character", selected_character)
	cf.set_value("profile", "unlocked_characters", ",".join(unlocked_characters))
	var tparts: Array = []
	for k in talent_levels.keys():
		var arr: Array = talent_levels[k]
		var inner: Array = []
		for v in arr:
			inner.append(str(int(v)))
		tparts.append("%s:%s" % [String(k), "|".join(inner)])
	cf.set_value("profile", "talent_levels", ",".join(tparts))
	cf.set_value("progress", "version", 1)
	cf.set_value("progress", "gold", gold)
	cf.set_value("progress", "diamonds", diamonds)
	cf.set_value("progress", "grenade_ammo", grenade_ammo)
	cf.set_value("progress", "missile_ammo", missile_ammo)
	cf.set_value("progress", "level", level)
	cf.set_value("progress", "exp", exp)
	# 升级待弹窗队列（逗号分隔的等级数字）
	var pls: Array = []
	for lv in pending_levelups:
		pls.append(str(lv))
	cf.set_value("progress", "pending_levelups", ",".join(pls))
	cf.set_value("progress", "unlocked_weapons", ",".join(unlocked_weapons))
	var upl: Array = []
	for k in weapon_upgrade_levels.keys():
		upl.append("%s:%d" % [String(k), int(weapon_upgrade_levels[k])])
	cf.set_value("progress", "weapon_upgrade_levels", ",".join(upl))
	var wsl: Array = []
	for s in weapon_unlocked_slots:
		wsl.append(str(int(s)))
	cf.set_value("progress", "weapon_unlocked_slots", ",".join(wsl))
	var hlparts: Array = []
	for k in homestead_levels.keys():
		hlparts.append("%d:%d" % [int(k), int(homestead_levels[k])])
	cf.set_value("progress", "homestead_unlocked", homestead_unlocked)
	cf.set_value("progress", "homestead_levels", ",".join(hlparts))
	var fpparts: Array = []
	for k in farm_plots.keys():
		var d: Dictionary = farm_plots[k]
		fpparts.append("%d:%s:%d" % [int(k), String(d["crop"]), int(d["ready_end"])])
	cf.set_value("progress", "farm_plots", ",".join(fpparts))
	cf.set_value("progress", "unlocked_stage", unlocked_stage)
	cf.set_value("progress", "selected_stage", selected_stage)
	cf.set_value("progress", "chest_kill_count", chest_kill_count)
	# 无尽模式进度存档
	cf.set_value("progress", "best_wave", best_wave)
	cf.set_value("progress", "endless_kills", endless_kills)
	cf.set_value("progress", "endless_diamond", endless_diamond)
	# 先完整写入临时文件，再替换旧档，避免写入中断直接截断旧档。
	var temp_path := PROFILE_PATH + ".tmp"
	var err := cf.save(temp_path)
	if err == OK:
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(PROFILE_PATH))
	if err != OK:
		push_error("玩家进度保存失败（错误码 %d），请检查磁盘空间与目录权限。" % err)

func avatar_texture() -> Texture2D:
	var path := "res://art/avatars/avatar_%d.png" % avatar_index
	if not ResourceLoader.exists(path):
		path = "res://art/avatars/avatar_1.png"
	return load(path)
