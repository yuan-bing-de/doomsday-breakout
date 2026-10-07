extends RefCounted
class_name Endless

# ============================================================================
# Endless.gd —— 无尽模式配置（数据驱动，唯一数据源）
# ----------------------------------------------------------------------------
# 玩法：无限存活，没有时间上限，死了才算结束。难度**线性缓增**，堆死为主。
# 波次机制：每波比上一波更密更厚；每 REWARD_WAVE 的倍数波给一次奖励结算。
#
# 难度增长（线性，非指数——保证能熬很久，考验续航而非爆发）：
#   刷怪间隔 : 每波 × INTERVAL_DECAY，下限 INTERVAL_MIN
#   敌人血量 : 每波 × HP_GROWTH
#   每波数量 : 每 REWARD_WAVE 波 +1 只，上限 EXTRA_MAX
#   BOSS     : 每 BOSS_EVERY 波出一只，血量 × (1 + 波次 × BOSS_HP_PER_WAVE)
#
# 想调难度只动下面这几个常量，其余自动算。
# ============================================================================

# ---- 波次节奏 ----
const INTERVAL_DECAY := 0.94      # 每波刷怪间隔倍率（越小越难）
const INTERVAL_MIN := 0.35        # 刷怪间隔下限（秒）
const HP_GROWTH := 1.05           # 每波敌人血量倍率
const REWARD_WAVE := 5            # 每这么多波结算一次奖励
const EXTRA_PER_REWARD := 1       # 每次奖励后，每波多刷几只
const EXTRA_MAX := 6             # 每波额外刷怪数量上限
const BOSS_EVERY := 10            # 每这么多波出一只 BOSS
const BOSS_HP_PER_WAVE := 0.12    # BOSS 每波额外血量系数（线性叠加）

# ---- 每波丧尸数量（核心手感：每波都比上一波多）----
#   基础数量随波次**线性递增**（每 2 波 +1 只），另叠加奖励波的额外只数。
#   第 1 波 = 3 只，第 11 波 = 8 只，第 21 波 = 13 只……
#   想整体调数量只动 BASE_START / BASE_PER_WAVES 两个常量。
const BASE_START := 3             # 第 1 波的丧尸数量
const BASE_PER_WAVES := 2         # 每多少波 +1 只基础数量
const BASE_MAX := 24              # 基础数量上限（防止后期数量爆炸卡死）

# ---- 奖励（波次奖励：活到该波就拿，不看击杀数）----
const REWARD_GOLD := 120          # 每个奖励节点的金币
const REWARD_SOUL := 2            # 每个奖励节点的精魂
const REWARD_DIAMOND_BASE := 3    # 每个奖励节点的钻石 = 基础 + 节点序号×系数
const REWARD_DIAMOND_STEP := 2    # 钻石随节点序号递增的系数

# ---- 背景（复用现有三张，不额外要美术资源）----
const BG := "res://art/background_city.png"

# ============================================================================
#  难度曲线（纯函数，主线与 UI 共用）
# ============================================================================
# _clamp_wave(w)：波次至少为 1。
static func _clamp_wave(w: int) -> int:
	return maxi(1, w)

# spawn_interval(wave)：第 wave 波的刷怪间隔（秒）。逐波乘以衰减率，下限 INTERVAL_MIN。
static func spawn_interval(wave: int) -> float:
	var w := _clamp_wave(wave)
	var v := 2.0 * pow(INTERVAL_DECAY, float(w - 1))
	return maxf(INTERVAL_MIN, v)

# hp_mul(wave)：第 wave 波的敌人血量倍率。线性缓增，不设上限（线性本来就不指数爆炸）。
static func hp_mul(wave: int) -> float:
	var w := _clamp_wave(wave)
	return pow(HP_GROWTH, float(w - 1))

# extra_per_wave(wave)：奖励波带来的额外刷怪数量（每 REWARD_WAVE 波 +1，只增不减）。
static func extra_per_wave(wave: int) -> int:
	var w := _clamp_wave(wave)
	return mini(EXTRA_MAX, (w - 1) / REWARD_WAVE * EXTRA_PER_REWARD)

# base_per_wave(wave)：该波的基础丧尸数量（不含奖励波额外只数）。
# 线性递增：每 BASE_PER_WAVES 波 +1 只，从 BASE_START 起步，上限 BASE_MAX。
static func base_per_wave(wave: int) -> int:
	var w := _clamp_wave(wave)
	return mini(BASE_MAX, BASE_START + (w - 1) / BASE_PER_WAVES)

# total_per_wave(wave)：该波实际要刷的丧尸总数 = 基础数量 + 奖励波额外只数。
# 第 1 波 BASE_START 只；之后每 2 波 +1；每 5 波额外 +1（上限 EXTRA_MAX）。
static func total_per_wave(wave: int) -> int:
	var w := _clamp_wave(wave)
	return mini(BASE_MAX + EXTRA_MAX, base_per_wave(w) + extra_per_wave(w))

# is_reward_wave(wave)：该波是否为奖励节点（REWARD_WAVE 的倍数）。
static func is_reward_wave(wave: int) -> bool:
	return _clamp_wave(wave) % REWARD_WAVE == 0

# reward_index(wave)：奖励节点序号（第几个奖励，从 1 起）；非奖励波返回 0。
static func reward_index(wave: int) -> int:
	if not is_reward_wave(wave):
		return 0
	return _clamp_wave(wave) / REWARD_WAVE

# reward_for(wave)：到达该奖励波时可获得的奖励 {gold, soul, diamond}；非奖励波返回空字典。
static func reward_for(wave: int) -> Dictionary:
	var idx := reward_index(wave)
	if idx <= 0:
		return {}
	return {
		"gold": REWARD_GOLD * idx,
		"soul": REWARD_SOUL * idx,
		"diamond": REWARD_DIAMOND_BASE + REWARD_DIAMOND_STEP * (idx - 1),
	}

# is_boss_wave(wave)：该波是否出 BOSS（BOSS_EVERY 的倍数）。
static func is_boss_wave(wave: int) -> bool:
	return _clamp_wave(wave) % BOSS_EVERY == 0

# boss_hp_mul(wave)：该波 BOSS 的额外血量倍率（线性叠加：1 + 波次 × 系数）。
static func boss_hp_mul(wave: int) -> float:
	return 1.0 + float(_clamp_wave(wave)) * BOSS_HP_PER_WAVE

# boss_pool()：可用的 BOSS 类型池（与 boss_catalog.gd 的键一致）。
static func boss_pool() -> Array:
	return ["brute", "hulk", "reaper"]

# boss_type_for(wave)：该波 BOSS 的类型。按波次循环取池，保证三个 BOSS 都出得到。
static func boss_type_for(wave: int) -> String:
	var pool := boss_pool()
	return pool[(_clamp_wave(wave) / BOSS_EVERY - 1) % pool.size()]
