extends Node

# ============================================================================
# AudioManager.gd —— 全局音频管理器（自动加载单例）
# ============================================================================
# 把音频文件放到 res://audio/ 即可自动生效：
#   res://audio/bgm.ogg        -> 背景音乐（进关卡后循环播放，返回菜单/主界面自动停止）
#   res://audio/ambience.ogg   -> 主界面氛围音（Hub 主菜单循环播放，进入关卡自动停止；也兼容 ambience.wav）
#   res://audio/home.ogg       -> 家园温馨音（进家园面板循环播放；进家园时暂停 Hub 恐怖氛围，关家园恢复；也兼容 home.wav）
#   res://audio/shoot.ogg      -> 开枪音效
# 没有文件也不会报错，游戏照常运行。
#
# 音量：BGM 与氛围音都走 Master 总线，由各自场景进场时调用 GameState.apply_game_volume()
# /apply_ui_volume() 切到对应的「游戏界面音量 / 主界面音量」滑块值，互不干扰。
# ============================================================================

var bgm_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var home_player: AudioStreamPlayer    # 家园温馨音专用播放器（进家园循环播，关家园停）
var click_player: AudioStreamPlayer   # UI 点击音效专用播放器（音量锁 150%，与其它音效池隔离）
var sfx_pool: Array[AudioStreamPlayer] = []
# 音效播放器池大小：预创建 8 个 AudioStreamPlayer，play_sfx 时循环复用其中空闲的那个，避免同时音效互相打断
const SFX_COUNT := 8
# UI 点击音效放大到原来的 150%（线性 1.5 倍 ≈ +3.52dB）。用户嫌默认音量太轻，要求加响。
const CLICK_VOLUME_SCALE := 1.5

# ---- 连发原声循环（高射速武器连续开火时播放，避免短音叠加糊成一片）----
var auto_loop_player: AudioStreamPlayer   # 专用通道，独立循环，不占 sfx_pool
var auto_burst_count := 0                 # 当前这一轮连发已发射击数（判断点射/连发用）
var auto_last_shot_ms := 0                # 上一发 play_shoot 调用的毫秒时间戳（判断连发是否结束）

func _ready():
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	# 仅加载并设为循环，不在这里播放（菜单/主界面应保持静音）
	var bgm = _try_load("res://audio/bgm.ogg")
	if bgm != null:
		bgm.loop = true
		bgm_player.stream = bgm
	# 主界面氛围音：同样只加载不自动播，由 Hub 场景进场时 start_ambience() 触发
	ambience_player = AudioStreamPlayer.new()
	add_child(ambience_player)
	var amb = _try_load("res://audio/ambience.ogg")
	if amb == null:
		amb = _try_load("res://audio/ambience.wav")
	if amb != null:
		amb.loop = true
		ambience_player.stream = amb
	# 家园温馨音：独立播放器，只加载不自动播，由家园面板 _ready() 触发 start_home()、
	# _close() 触发 stop_home()。进家园时会先 stop_ambience() 暂停 Hub 恐怖氛围，避免两套叠音。
	home_player = AudioStreamPlayer.new()
	add_child(home_player)
	var home = _try_load("res://audio/home.ogg")
	if home == null:
		home = _try_load("res://audio/home.wav")
	if home != null:
		home.loop = true
		home_player.stream = home
	# UI 点击音效：独立播放器 + 150% 音量。只加载不播，由各界面挂 attach_click() 后按需触发。
	click_player = AudioStreamPlayer.new()
	click_player.volume_db = linear_to_db(CLICK_VOLUME_SCALE)
	add_child(click_player)
	var clk := _try_load("res://audio/click.ogg")
	if clk != null:
		clk.loop = false
		click_player.stream = clk
	for i in SFX_COUNT:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_pool.append(p)
	# 连发原声循环播放器：加载 shoot_auto_loop.ogg 并设为循环，但不自动播放；
	# 仅在检测到高射速武器连续开火(达到阈值)时由 play_shoot 触发，停火后自动停。
	auto_loop_player = AudioStreamPlayer.new()
	add_child(auto_loop_player)
	var al := _try_load(SHOOT_AUTO_LOOP)
	if al != null:
		al.loop = true
		auto_loop_player.stream = al

# 进关卡时调用：开始循环播放 BGM（已在播放则跳过，避免重进关卡时叠播）
func start_bgm():
	if bgm_player.stream == null:
		var bgm = _try_load("res://audio/bgm.ogg")
		if bgm == null:
			return
		bgm.loop = true
		bgm_player.stream = bgm
	if not bgm_player.playing:
		bgm_player.play()

# 离开关卡（返回菜单/主界面/关卡选择）时调用：停止 BGM
func stop_bgm():
	if bgm_player.playing:
		bgm_player.stop()

# 进入主界面（Hub）时调用：开始循环播放氛围音（已在播放则跳过，避免重复进主界面叠播）
func start_ambience():
	if ambience_player.stream == null:
		var amb = _try_load("res://audio/ambience.ogg")
		if amb == null:
			amb = _try_load("res://audio/ambience.wav")
		if amb == null:
			return
		amb.loop = true
		ambience_player.stream = amb
	if not ambience_player.playing:
		ambience_player.play()

# 离开主界面（进入关卡/关卡选择）时调用：停止氛围音
func stop_ambience():
	if ambience_player.playing:
		ambience_player.stop()

# 进入家园面板时调用：开始循环播放温馨音（已在播放则跳过）。
# 家园面板是叠在 Hub 之上的全屏 Control，Hub 的恐怖氛围音会一直在后台播，
# 所以进家园前由调用方先 stop_ambience() 暂停恐怖氛围，避免两套叠在一起；关家园再 start_ambience() 恢复。
func start_home():
	if home_player.stream == null:
		var home = _try_load("res://audio/home.ogg")
		if home == null:
			home = _try_load("res://audio/home.wav")
		if home == null:
			return
		home.loop = true
		home_player.stream = home
	if not home_player.playing:
		home_player.play()

# 关闭家园面板时调用：停止温馨音
func stop_home():
	if home_player.playing:
		home_player.stop()

# 安全加载音频：文件存在才 load，否则返回 null（缺文件也不报错，游戏照常运行）
func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null

func play_sfx(name: String):
	var stream := _try_load("res://audio/" + name + ".ogg")
	if stream != null:
		for p in sfx_pool:
			if not p.playing:
				p.stream = stream
				p.play()
				return

# play_shoot(fire_rate)：按武器射速自动选择开枪音效并播放。
# 射速越高、两发之间的间隔越短，若每发都播带长尾的完整枪响会糊成一片噪音，故分两档：
#   res://audio/shoot_pistol.ogg —— 较长、完整的单发枪响。用于低射速（手枪、单发、慢速机枪）。
#   res://audio/shoot_auto.ogg   —— 极短快音。用于高射速（连发机枪、米尼冈），连发只有节奏感不糊。
# 阈值 AUTO_FIRE_RATE：射速(发/秒) 高于此值判为"射速过快"，走短快音。
# 两个文件任一缺失都会安全跳过；两个都缺则完全无声（不报错）。
const AUTO_FIRE_RATE := 8.0
const SHOOT_PISTOL := "res://audio/shoot_pistol.ogg"
const SHOOT_AUTO := "res://audio/shoot_auto.ogg"             # 短促点射快音(0.11s 软化)
const SHOOT_AUTO_LOOP := "res://audio/shoot_auto_loop.ogg"  # 连发原声循环(前端有声音段，软化+无缝)
const AUTO_BURST_THRESHOLD := 3   # 连发达到此发数(超出即第4发)切为连续原声；前3发仍每发播0.11s
const AUTO_BURST_GAP_MS := 200    # 距上一发超过此毫秒数视为连发结束：停原声循环、计数归零

# play_shoot(fire_rate)：按武器射速与"连发长度"选择开枪音效。
# 低射速(手枪/单发, fire_rate<=8)：每发独立播完整单发音，不做连发处理。
# 高射速(连发机枪, fire_rate>8)：分两段——
#   本轮前 AUTO_BURST_THRESHOLD 发(≤3)：每发播一次 0.11s 快音，保留点射手感；
#   超过阈值(第4发起，即连发)：改播 shoot_auto_loop.ogg 连续循环，不再叠短音，避免糊成一片；
#   停火超过 AUTO_BURST_GAP_MS 毫秒 -> 连发结束，停循环、计数归零，下次点射重新从 0.11s 起。
func play_shoot(fire_rate: float):
	if fire_rate <= AUTO_FIRE_RATE:
		_play_once(SHOOT_PISTOL)
		return
	var now := Time.get_ticks_msec()
	if now - auto_last_shot_ms > AUTO_BURST_GAP_MS:
		_stop_auto_loop()          # 与上一发间隔过长 -> 新一轮连发，先停可能还在播的循环并清零
	auto_last_shot_ms = now
	auto_burst_count += 1
	if auto_burst_count <= AUTO_BURST_THRESHOLD:
		_play_once(SHOOT_AUTO)     # 短连发：每发一次 0.11s 软化快音
	else:
		_start_auto_loop()         # 长连发：连续原声循环，覆盖后续所有发，不再叠短音

# 从 sfx_pool 取空闲播放器播一次指定路径的音效（用于每发独立音）
func _play_once(path: String):
	var stream := _try_load(path)
	if stream == null:
		return
	stream.loop = false
	for p in sfx_pool:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	if sfx_pool.size() > 0:        # 池全忙时强行用第一个，保证不断音
		sfx_pool[0].stream = stream
		sfx_pool[0].play()

# 连发原声循环：确保 shoot_auto_loop.ogg 在播（已在播则跳过，避免重复触发）
func _start_auto_loop():
	if auto_loop_player.stream == null:
		var al := _try_load(SHOOT_AUTO_LOOP)
		if al == null:
			return
		al.loop = true
		auto_loop_player.stream = al
	if not auto_loop_player.playing:
		auto_loop_player.play()

# 停连发原声循环并清零连发计数（停火或新一轮连发开始时调用）
func _stop_auto_loop():
	if auto_loop_player.playing:
		auto_loop_player.stop()
	auto_burst_count = 0

# 每帧检测：玩家松手停火后，超过间隔自动停循环（play_shoot 只在开枪时调用，
# 所以"完全停火"要靠这里兜底，否则循环会一直播）
func _process(_delta: float):
	if auto_loop_player.playing and (Time.get_ticks_msec() - auto_last_shot_ms) > AUTO_BURST_GAP_MS:
		_stop_auto_loop()

# 主界面（Hub）等界面 UI 点击音效：加载 res://audio/click.ogg 播放一次（不循环）。
# 用独立 click_player（音量 150%），不占用 sfx_pool——池子留给 shoot/explosion 等，
# 避免点击音把池里播放器占满、或被别的音效覆盖音量。文件缺失则静默跳过。
func play_click():
	if click_player.stream == null:
		var clk := _try_load("res://audio/click.ogg")
		if clk == null:
			return
		clk.loop = false
		click_player.stream = clk
	# 每次重置为 150%，防止被其它逻辑改动过音量后失效
	click_player.volume_db = linear_to_db(CLICK_VOLUME_SCALE)
	click_player.play()

# attach_click(btn)：给任意按钮挂上点击音效。内部用 Signal 的 is_connected 做幂等保护，
# 重复调用不会叠加多个连接（否则快速连点会叠音、越来越响）。
# 用法：AudioManager.attach_click(按钮)
func attach_click(btn: BaseButton):
	if btn == null or not is_instance_valid(btn):
		return
	if not btn.pressed.is_connected(play_click):
		btn.pressed.connect(play_click)
