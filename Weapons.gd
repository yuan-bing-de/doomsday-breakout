extends Node

# ============================================================================
# Weapons.gd —— 武器库（全局单例）
# ============================================================================
# 管理所有武器数据、解锁状态、当前装备。
# 开局自动装备第一把手枪（M1911），其余武器用金币解锁。
# 按数字键 1~6 切换已拥有武器；按 B 打开购买面板。
# ============================================================================

# 武器列表：id -> 属性字典
const DATA := {
	"pistol_m1911": {
		"name": "M1911 经典",
		"type": "pistol",
		"damage": 7,
		"fire_rate": 4.5,          # 每秒射击次数（拉开强弱差距：基础最弱）
		"price": 0,
		"texture": "res://art/weapons/pistol_m1911.png",
		"magazine": 7,             # .45 ACP 单排弹匣
		"bullet_size": 1.0,        # .45 ACP，中等手枪弹
		"bullet_tracer": false,    # 手枪无曳光
		"reload_time": 2.0,         # 换弹时间（秒）
		"panel_scale": 0.72,        # 面板里显示缩放（手枪偏大，略缩）
		"desc": ".45 ACP，单发停止作用好，美军经典手枪。"
	},
	"pistol_g17": {
		"name": "G17 制式",
		"type": "pistol",
		"damage": 11,
		"fire_rate": 6.5,
		"price": 300,
		"texture": "res://art/weapons/pistol_g17.png",
		"magazine": 17,            # 9mm 双排弹匣
		"bullet_size": 0.8,        # 9mm，比 .45 小
		"bullet_tracer": false,
		"reload_time": 1.5,         # 换弹时间（秒）
		"desc": "9mm Parabellum，弹匣容量大、射速快。"
	},
	"pistol_de": {
		"name": "DE 沙鹰",
		"type": "pistol",
		"damage": 42,
		"fire_rate": 2.0,
		"price": 800,
		"texture": "res://art/weapons/pistol_de.png",
		"magazine": 7,             # .50 AE 大威力少弹量
		"bullet_size": 1.4,        # .50 AE，最大的手枪弹
		"bullet_tracer": false,
		"reload_time": 2.5,         # 换弹时间（秒）
		"panel_scale": 0.72,        # 面板里显示缩放（手枪偏大，略缩）
		"desc": ".50 AE，单发威力惊人，后坐力大导致射速慢。"
	},
	"pistol_p250": {
		"name": "P250 紧凑",
		"type": "pistol",
		"damage": 13,
		"fire_rate": 7.0,           # 紧凑高射速
		"price": 550,
		"texture": "res://art/weapons/pistol_p250.png",
		"magazine": 15,
		"bullet_size": 0.85,
		"bullet_tracer": false,
		"reload_time": 1.4,
		"desc": "SIG P250，紧凑握持、射速快，高性价比的副武器升级。"
	},
	"pistol_m45": {
		"name": "M45A1 战术",
		"type": "pistol",
		"damage": 20,
		"fire_rate": 5.5,
		"price": 950,
		"texture": "res://art/weapons/pistol_m45.png",
		"magazine": 12,
		"bullet_size": 1.1,
		"bullet_tracer": false,
		"reload_time": 1.8,
		"desc": ".45 ACP 战术手枪，单发威力高于 M1911，后坐略大。"
	},
	"pistol_p226": {
		"name": "P226 制式",
		"type": "pistol",
		"damage": 22,
		"fire_rate": 7.0,
		"price": 1400,
		"texture": "res://art/weapons/pistol_p226.png",
		"magazine": 18,
		"bullet_size": 0.9,
		"bullet_tracer": false,
		"reload_time": 1.5,
		"desc": "SIG P226，军警制式，威力与射速均衡、弹匣容量大。"
	},
	"pistol_fn57": {
		"name": "Five-seveN 穿甲",
		"type": "pistol",
		"damage": 24,
		"fire_rate": 10.0,         # 极高射速
		"price": 1900,
		"texture": "res://art/weapons/pistol_fn57.png",
		"magazine": 20,
		"bullet_size": 0.75,
		"bullet_tracer": false,
		"reload_time": 1.3,
		"desc": "FN Five-seveN，高速小口径穿甲弹，射速极高、弹匣大。"
	},
	"pistol_m500": {
		"name": "M500 马格南",
		"type": "pistol",
		"damage": 90,              # 单发毁伤极高
		"fire_rate": 1.6,
		"price": 2800,
		"texture": "res://art/weapons/pistol_m500.png",
		"magazine": 5,
		"bullet_size": 1.5,
		"bullet_tracer": false,
		"reload_time": 3.2,
		"desc": "S&W M500，.50 马格南左轮，单发毁伤恐怖，弹少射速慢。"
	},
	"mg_mp5": {
		"name": "MP5 冲锋枪",
		"type": "machine_gun",
		"damage": 9,
		"fire_rate": 13.0,
		"price": 1200,
		"texture": "res://art/weapons/mg_mp5_new.png",
		"magazine": 30,            # 9mm 冲锋枪弹匣
		"bullet_size": 0.8,        # 9mm 冲锋枪弹
		"bullet_tracer": true,     # 冲锋枪有曳光弹
		"reload_time": 2.5,         # 换弹时间（秒）
		"desc": "9mm 冲锋枪，高射速、低后坐，适合近距离清扫。"
	},
	"mg_ak47": {
		"name": "AK-47 突击",
		"type": "machine_gun",
		"damage": 22,
		"fire_rate": 8.5,
		"price": 2500,
		"texture": "res://art/weapons/mg_ak47.png",
		"magazine": 30,            # 7.62mm 弧形弹匣
		"bullet_size": 1.2,        # 7.62mm 步枪弹，较长
		"bullet_tracer": true,
		"reload_time": 3.0,         # 换弹时间（秒）
		"desc": "7.62x39mm，威力与射速均衡，可靠耐用。"
	},
	"mg_m249": {
		"name": "M249 班用机枪",
		"type": "machine_gun",
		"damage": 20,
		"fire_rate": 15.0,
		"price": 4500,
		"texture": "res://art/weapons/mg_m249.png",
		"magazine": 100,           # 5.56mm 弹链供弹
		"bullet_size": 1.0,        # 5.56mm，中等步枪弹
		"bullet_tracer": true,
		"reload_time": 8.0,         # 换弹时间（秒）
		"desc": "5.56mm 弹链供弹，持续火力最强。"
	},
	"mg_ump45": {
		"name": "UMP45 冲锋枪",
		"type": "machine_gun",
		"damage": 16,
		"fire_rate": 14.0,
		"price": 1800,
		"texture": "res://art/weapons/mg_ump45.png",
		"magazine": 25,
		"bullet_size": 0.85,
		"bullet_tracer": true,
		"reload_time": 2.2,
		"desc": ".45 ACP 冲锋枪，近距离压制力强、后坐低。"
	},
	"mg_m4a1": {
		"name": "M4A1 卡宾枪",
		"type": "machine_gun",
		"damage": 24,
		"fire_rate": 13.0,
		"price": 3200,
		"texture": "res://art/weapons/mg_m4a1.png",
		"magazine": 30,
		"bullet_size": 1.0,
		"bullet_tracer": true,
		"reload_time": 2.6,
		"desc": "5.56mm 卡宾枪，威力与射速平衡的万能枪械。"
	},
	"mg_g36": {
		"name": "G36 突击步枪",
		"type": "machine_gun",
		"damage": 28,
		"fire_rate": 12.0,
		"price": 10000,
		"texture": "res://art/weapons/mg_g36.png",
		"magazine": 100,
		"bullet_size": 1.05,
		"bullet_tracer": true,
		"reload_time": 2.8,
		"desc": "5.56mm 突击步枪，精度与持续火力俱佳。"
	},
	"mg_pkm": {
		"name": "PKM 通用机枪",
		"type": "machine_gun",
		"damage": 40,
		"fire_rate": 11.0,
		"price": 60000,
		"texture": "res://art/weapons/mg_pkm.png",
		"magazine": 100,
		"bullet_size": 1.2,
		"bullet_tracer": true,
		"reload_time": 5.5,
		"desc": "7.62mm 通用机枪，大弹链高伤害，压制力顶尖。"
	},
	"mg_m134": {
		"name": "M134 米尼冈",
		"type": "machine_gun",
		"damage": 40,
		"fire_rate": 40.0,         # 狂暴射速
		"price": 90000,
		"texture": "res://art/weapons/mg_m134.png",
		"magazine": 200,
		"bullet_size": 0.9,
		"bullet_tracer": true,
		"reload_time": 8.0,
		"desc": "7.62mm 六管加特林，射速狂暴、弹链恐怖，终极火力。"
	}
}

# 武器顺序（按类型内强度升序排列；手枪前 8 把、机枪后 8 把）
const ORDER := [
	"pistol_m1911", "pistol_g17", "pistol_de",
	"pistol_p250", "pistol_m45", "pistol_p226", "pistol_fn57", "pistol_m500",
	"mg_mp5", "mg_ak47", "mg_m249",
	"mg_ump45", "mg_m4a1", "mg_g36", "mg_pkm", "mg_m134"
]

# ---- 强化（升级）比例常量 ----
# 每升 1 级，四项数值同时提升，强弱差距随等级拉开
const UPGRADE_DMG_STEP := 0.15        # 每级 +15% 伤害
const UPGRADE_RATE_STEP := 0.08       # 每级 +8% 射速
const UPGRADE_MAG_STEP := 0.20        # 每级 +20% 弹夹容量
const UPGRADE_RELOAD_STEP := 0.08     # 每级 -8% 换弹时间（换弹更快）

# 当前武器在某强化等级下的有效数值（局内战斗与面板都读这套）
func upgrade_level(id: String) -> int:
	return int(GameState.weapon_upgrade_levels.get(id, 0))

func effective_damage(id: String) -> int:
	var lv := upgrade_level(id)
	return int(round(float(DATA[id]["damage"]) * (1.0 + UPGRADE_DMG_STEP * lv)))

func effective_fire_rate(id: String) -> float:
	var lv := upgrade_level(id)
	return float(DATA[id]["fire_rate"]) * (1.0 + UPGRADE_RATE_STEP * lv)

func effective_magazine(id: String) -> int:
	var lv := upgrade_level(id)
	return int(round(float(DATA[id]["magazine"]) * (1.0 + UPGRADE_MAG_STEP * lv)))

# 有效换弹时间 = 基础 × (1 - 8% × 等级)。
# maxf(0.5, ...) 把下限锁在 0.5 秒，防止满级 5 级（减 40%）把换弹压到 0/负值，
# 否则换弹瞬间完成会破坏手感与节奏平衡。
func effective_reload(id: String) -> float:
	var lv := upgrade_level(id)
	return maxf(0.5, float(DATA[id]["reload_time"]) * (1.0 - UPGRADE_RELOAD_STEP * lv))

# 返回一把武器在当前强化等级下的完整数值字典（字段已按强化重算）
func get_effective(id: String) -> Dictionary:
	var d: Dictionary = DATA[id].duplicate()
	d["damage"] = effective_damage(id)
	d["fire_rate"] = effective_fire_rate(id)
	d["magazine"] = effective_magazine(id)
	d["reload_time"] = effective_reload(id)
	return d

# 当前装备（供角色贴图/旧引用使用，始终等于当前激活槽武器）
var current_id := "pistol_m1911"

# 已解锁武器
var unlocked := ["pistol_m1911"]

# ============================================================================
# 装备栏（loadout）：角色可同时携带多把武器，游戏中按 Q 切换
#   - 4 个槽，前 2 个（0/1）初始免费解锁；槽 2/3 用钻石买断解锁（见 SLOT_DIAMOND_COST）
#   - 每个槽放一把已解锁武器 id（空串 = 空槽）
#   - active_slot：当前手持的槽（游戏中切换）
# ============================================================================
const LOADOUT_SLOT_COUNT := 4
# 装备栏槽位解锁（用钻石买断，状态持久化到 GameState.weapon_unlocked_slots）：
#   - 前 INITIAL_UNLOCKED_SLOTS 个槽初始免费解锁；其余槽的钻石花费见 SLOT_DIAMOND_COST。
#   - 点锁定槽即花费钻石解锁（一次性买断）。想调难度只改 SLOT_DIAMOND_COST 这一行。
const INITIAL_UNLOCKED_SLOTS := 2
const SLOT_DIAMOND_COST := [0, 0, 100, 300]   # 各槽解锁钻石花费，0 = 初始已解锁
var loadout := ["pistol_m1911", "", "", ""]
var active_slot := 0

# 信号：切换当前手持武器时发射（参数=新武器 id）。角色贴图、局内 HUD 监听它刷新显示。
signal weapon_changed(id: String)
# 信号：某武器被金币解锁（buy 成功）时发射（参数=武器 id）。商店/解锁提示界面监听刷新。
signal weapon_unlocked(id: String)

func _ready():
	# GameState 先读存档；此处过滤过期武器 ID，并同步规范化后的装备栏。
	unlocked = ["pistol_m1911"]
	for id in GameState.unlocked_weapons:
		if DATA.has(id) and not id in unlocked:
			unlocked.append(id)
	if GameState.loadout.size() == LOADOUT_SLOT_COUNT:
		loadout = Array(GameState.loadout)
	# 去重：同 id 只保留第一次出现，其余槽清空（兼容旧存档里的重复装备）
	var _seen: Dictionary = {}
	for i in range(LOADOUT_SLOT_COUNT):
		var s: String = loadout[i]
		if s != "":
			if _seen.has(s):
				loadout[i] = ""
			else:
				_seen[s] = true
	for slot in range(LOADOUT_SLOT_COUNT):
		if not is_slot_unlocked(slot) or not is_unlocked(loadout[slot]):
			loadout[slot] = ""
	# 只在「一个武器都没装」时才用默认手枪补槽 0，避免强制把同一把枪塞回两个槽
	var _any := false
	for s in loadout:
		if s != "":
			_any = true
			break
	if not _any:
		loadout[0] = "pistol_m1911"
	GameState.unlocked_weapons = unlocked.duplicate()
	GameState.loadout = loadout.duplicate()
	# 恢复上次的手持槽位（存档里的 weapon_active_slot）；槽被规范化清空时退到有枪的槽
	active_slot = clampi(int(GameState.weapon_active_slot), 0, LOADOUT_SLOT_COUNT - 1)
	if not is_slot_unlocked(active_slot) or loadout[active_slot] == "":
		for i in range(LOADOUT_SLOT_COUNT):
			if not is_slot_unlocked(i):
				continue
			if loadout[i] != "":
				active_slot = i
				break
	GameState.weapon_active_slot = active_slot
	current_id = get_active_id()

# 取当前手持武器的完整数据字典（DATA[id]）。取不到时回退到默认 M1911，永不返回空。
# 旧代码/角色贴图若只想要一把枪的属性时可直接调用它。
func get_current() -> Dictionary:
	return DATA.get(get_active_id(), DATA["pistol_m1911"])

# 当前激活槽里的武器 id（槽为空时回退到槽 0，再回退到默认手枪）
func get_active_id() -> String:
	var id: String = loadout[active_slot]
	if id == "" or not DATA.has(id):
		id = loadout[0]
	if id == "" or not DATA.has(id):
		id = "pistol_m1911"
	return id

func equip(id: String) -> bool:
	# 兼容旧调用：装备到当前激活槽
	return equip_to_slot(active_slot, id)

# 把武器装进指定槽（只能装到已解锁的槽）
func equip_to_slot(slot: int, id: String) -> bool:
	if slot < 0 or not is_slot_unlocked(slot):
		return false
	if not is_unlocked(id) or not DATA.has(id):
		return false
	var previous_active_slot := active_slot
	var previous_id := get_active_id()
	# 同一把枪只能同时装在一个槽：若已在别的槽，先把它从旧槽挪走（旧槽变空）
	for i in range(LOADOUT_SLOT_COUNT):
		if i != slot and loadout[i] == id:
			loadout[i] = ""
	loadout[slot] = id
	# 移走当前手持枪时，手持槽跟随枪移动，不能继续指向空槽。
	if loadout[active_slot] == "":
		active_slot = slot
	current_id = get_active_id()
	GameState.loadout = loadout.duplicate()
	GameState.weapon_active_slot = active_slot
	GameState.save_profile()
	# 只有装备到当前手持槽才换枪（触发角色贴图刷新）
	if slot == active_slot or active_slot != previous_active_slot or current_id != previous_id:
		weapon_changed.emit(current_id)
	return true

# swap_slots(a, b)：调换两个槽里的枪（拖拽装备栏用）。
# 前提：两槽下标合法、两槽都已解锁、且**两槽都装了枪**（空槽/锁定槽不参与调换），否则返回 false。
func swap_slots(a: int, b: int) -> bool:
	if a < 0 or a >= LOADOUT_SLOT_COUNT or b < 0 or b >= LOADOUT_SLOT_COUNT or a == b:
		return false
	if not is_slot_unlocked(a) or not is_slot_unlocked(b):
		return false
	if loadout[a] == "" or loadout[b] == "":
		return false
	var tmp: String = loadout[a]
	loadout[a] = loadout[b]
	loadout[b] = tmp
	# 手持 id 可能变了（两槽都是枪时当前 id 不变，但保险起见重算）
	current_id = get_active_id()
	GameState.loadout = loadout.duplicate()
	GameState.save_profile()
	weapon_changed.emit(current_id)
	return true

# unequip_from_slot(slot)：把指定槽的枪卸下（该槽变空）。slot 非法或本来是空则返回 false。
# 手持槽被卸空时，active_slot 顺延到其它还有枪的已解锁槽；全都空则退回 0（get_active_id 兜底 M1911）。
# 卸下只是"不携带"，不退款、不影响是否已购买（is_unlocked 仍为 true，可随时再装备）。
func unequip_from_slot(slot: int) -> bool:
	if slot < 0 or slot >= LOADOUT_SLOT_COUNT:
		return false
	if not is_slot_unlocked(slot) or loadout[slot] == "":
		return false
	loadout[slot] = ""
	# 手持槽被卸空 → 顺延到其它还有枪的已解锁槽
	if active_slot == slot:
		active_slot = -1
		for i in range(LOADOUT_SLOT_COUNT):
			if is_slot_unlocked(i) and loadout[i] != "":
				active_slot = i
				break
		if active_slot < 0:
			active_slot = 0
	current_id = get_active_id()
	GameState.loadout = loadout.duplicate()
	GameState.weapon_active_slot = active_slot
	GameState.save_profile()
	weapon_changed.emit(current_id)
	return true

# 游戏中按 Q：在所有「已解锁且装有枪」的槽之间循环切换手持武器
func swap_active():
	var cand: Array = []
	for i in range(LOADOUT_SLOT_COUNT):
		if is_slot_unlocked(i) and loadout[i] != "":
			cand.append(i)
	if cand.size() <= 1:
		return
	var cur := cand.find(active_slot)
	var nxt: int = cand[(cur + 1) % cand.size()]
	active_slot = nxt
	current_id = get_active_id()
	GameState.weapon_active_slot = active_slot
	GameState.save_profile()
	weapon_changed.emit(current_id)

# 场景加载时调用：手持槽有枪就保持不动（保留玩家上局选的枪），
# 只有手持槽为空才自动换到有枪的槽 / 补默认手枪。绝不强制塞 M1911。
func ensure_armed():
	if loadout[active_slot] != "":
		current_id = get_active_id()
		return
	for i in range(LOADOUT_SLOT_COUNT):
		if not is_slot_unlocked(i):
			continue
		if loadout[i] != "":
			active_slot = i
			current_id = get_active_id()
			GameState.weapon_active_slot = active_slot
			weapon_changed.emit(current_id)
			return
	equip("pistol_m1911")   # 一把枪都没有的全新存档：补默认手枪

# 某武器是否已用金币购买解锁（在 unlocked 列表里）。未解锁的武器不能装备/切换/强化。
func is_unlocked(id: String) -> bool:
	return id in unlocked

# ---- 装备格解锁（钻石买断，状态持久化在 GameState.weapon_unlocked_slots）----
# 某槽解锁所需钻石（0 = 初始已解锁）
func slot_unlock_cost(slot: int) -> int:
	if slot < 0 or slot >= SLOT_DIAMOND_COST.size():
		return 0
	return int(SLOT_DIAMOND_COST[slot])

# 该装备格是否已解锁：前 INITIAL_UNLOCKED_SLOTS 个初始解锁，其余看是否花钻石买过
func is_slot_unlocked(slot: int) -> bool:
	if slot < 0 or slot >= LOADOUT_SLOT_COUNT:
		return false
	if slot < INITIAL_UNLOCKED_SLOTS:
		return true
	return GameState.is_weapon_slot_unlocked(slot)

# 当前已解锁的装备格数量（用于钳制 active_slot 等）
func unlocked_slot_count() -> int:
	var n := 0
	for s in range(LOADOUT_SLOT_COUNT):
		if is_slot_unlocked(s):
			n += 1
	return n

# 花费钻石解锁某格（一次性买断）：成功返回 true（自动扣费 + 持久化 + 发信号）
func unlock_slot(slot: int) -> bool:
	if is_slot_unlocked(slot):
		return false
	var c := slot_unlock_cost(slot)
	if c <= 0:
		return false
	if GameState.diamonds < c:
		return false
	GameState.diamonds -= c
	GameState.unlock_weapon_slot(slot)
	GameState.save_profile()
	weapon_slot_unlocked.emit(slot)
	return true

# 信号：某装备格被钻石买断解锁（unlock_slot 成功）时发射（参数=槽下标）。
# 装备界面监听它刷新槽的锁定/解锁状态。
signal weapon_slot_unlocked(slot: int)

# 锁定槽上显示的解锁条件文字
func slot_unlock_text(slot: int) -> String:
	var c := slot_unlock_cost(slot)
	if c <= 0:
		return "初始解锁"
	return "钻石 %d 解锁" % c

# 锁定槽上显示的进度文字（已有/需要 钻石）
func slot_unlock_progress_text(slot: int) -> String:
	var c := slot_unlock_cost(slot)
	if c <= 0:
		return ""
	return "%d/%d" % [mini(GameState.diamonds, c), c]

func can_afford(id: String) -> bool:
	if not DATA.has(id):
		return false
	return GameState.gold >= DATA[id]["price"]

func buy(id: String) -> bool:
	if is_unlocked(id) or not DATA.has(id):
		return false
	var price: int = DATA[id]["price"]
	if GameState.gold < price:
		return false
	GameState.gold -= price
	unlocked.append(id)
	GameState.unlocked_weapons = unlocked.duplicate()
	GameState.loadout = loadout.duplicate()
	# 扣费和解锁写入同一份存档，完成后再通知界面。
	GameState.save_profile()
	GameState.stats_changed.emit()
	weapon_unlocked.emit(id)
	return true

# 在 ORDER 顺序里找「下一把已解锁」的武器并装备（到当前手持槽），到末尾循环回开头。
# 旧的数字键 1~6 切换逻辑用它；只装备已解锁的，自动跳过未购买的枪。
func next_weapon():
	var idx := ORDER.find(current_id)
	for i in range(1, ORDER.size()):
		var next: String = ORDER[(idx + i) % ORDER.size()]
		if is_unlocked(next):
			equip(next)
			return

# 同 next_weapon，但反方向（上一把已解锁武器）。% ORDER.size() 处理越界回绕，保证循环。
func prev_weapon():
	var idx := ORDER.find(current_id)
	for i in range(1, ORDER.size()):
		var prev: String = ORDER[(idx - i + ORDER.size()) % ORDER.size()]
		if is_unlocked(prev):
			equip(prev)
			return
