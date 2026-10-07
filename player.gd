extends CharacterBody2D

# player.gd —— 玩家角色脚本（移动、跳跃、射击、血量）。完整说明见下方注释块。

signal died

# ============================================================================
# player.gd —— 玩家角色脚本（移动、跳跃、射击、血量）
# ============================================================================
# 挂在 Player 场景（CharacterBody2D）上。
# 玩家是「物理角色」，用 move_and_slide() 处理移动和落地。
#
# 你想改的地方：
#   - 移动速度 / 跳跃高度    → 看 speed / jump_velocity 常量
#   - 角色图片大小           → 看 _ready() 里的 120.0
#   - 血量数值 / 受伤扣多少  → 看 health 变量 和 take_damage()
#   - 射击间隔 / 子弹伤害     → 看 SHOOT_COOLDOWN 和 bullet 的 take_damage(1)
# ============================================================================

# ---- 基础移动参数 ----
@export var speed := 240.0          # 左右移动速度（像素/秒）。想跑快点就调大
@export var acceleration := 1800.0  # 起步加速度，避免按键后瞬间滑出去
@export var deceleration := 2200.0  # 松键刹车速度，避免突然定格
@export var jump_velocity := -520.0 # 跳跃初速度（负数=向上）。想跳更高就调更小（更负）
const GRAVITY := 1200.0             # 重力，每帧给下落加速。越大掉得越快

@onready var sprite: Sprite2D = $Sprite2D   # 角色贴图节点
@onready var weapon_sprite: Sprite2D = $WeaponSprite   # 手持武器贴图
const bullet_scene = preload("res://Bullet.tscn")  # 子弹场景（预加载）
const GRENADE_SCRIPT = preload("res://grenade.gd")   # 手雷（G 键投掷）
const MISSILE_SCRIPT = preload("res://missile.gd")   # 支援导弹（H 键呼叫）
const CHARACTER_LOCOMOTION = preload("res://character_locomotion.gd")
var character_locomotion: Node2D = null

# ---- 技能冷却（手雷 / 支援导弹）----
# 冷却时长由人物数值表 Characters.gd 提供，HUD 直接读下面两个变量显示进度
var grenade_cd := 0.0        # 手雷剩余冷却（秒），0 = 可以扔
var missile_cd := 0.0        # 支援导弹剩余冷却（秒），0 = 可以呼叫
var grenade_cd_max := 8.0    # 手雷总冷却（用于算冷却百分比）
var missile_cd_max := 25.0   # 支援导弹总冷却
var char_stats: Dictionary = {}   # 当前人物的最终数值（体力/移速/手雷伤害/导弹伤害）

# ---- 弹药 / 换弹 ----
# 每把武器有弹夹，打完需要换弹（换弹时不能射击）。弹药按装备槽分别记录，切枪不丢弹。
var ammo_by_slot: Dictionary = {}   # 装备槽下标 -> 当前弹量
var _ammo_by_weapon: Dictionary = {}   # 弹量跟随武器，换槽/重新装备不丢失
var reloading := false              # 是否正在换弹
var reload_timer := 0.0             # 换弹剩余时间（秒）
# ---- 医疗包（局内按 F 使用）----
var medkit_cd := 0.0                # 医疗包剩余冷却（秒），0 = 可用
const MEDKIT_CD_MAX := 1.5          # 医疗包冷却（用户指定 1.5s）
const MEDKIT_HEAL := 50             # 医疗包恢复的基础生命值
var medkit_heal_mul := 1.0          # 医疗包治疗量乘区（医生「急救精通」天赋）
var reload_mul := 1.0               # 换弹时间乘区（警察「快速换弹」天赋）
var dmg_mul := 1.0                 # 子弹伤害乘区（军人「军械精通」天赋）
var damage_taken_mul := 1.0        # 受到伤害乘区（维修工「加固护甲」天赋）

var facing := 1                     # 朝向：1=朝右，-1=朝左（用于射击方向和贴图翻转）
var shoot_timer := 0.0              # 当前冷却计时器
var aim_dir := Vector2.RIGHT        # 当前瞄准方向
const HAND_OFFSET_RIGHT := Vector2(-16, 4)   # 右手相对于角色中心的偏移（画面左侧）
const HAND_OFFSET_LEFT  := Vector2(16, 4)    # 朝左时左手偏移
var weapon_base_scale := Vector2(1, 1)      # 武器原始缩放（用于左右翻转时保留大小）

# 重制后的六名游戏内角色贴图。按角色固定使用，避免切换武器时回退旧人物。
const REMADE_SIDE_TEXTURES := {
	"driver": "res://art/characters_v3/side/driver_mp5.png",
	"doctor": "res://art/characters_v3/side/doctor_g17.png",
	"police": "res://art/characters_v3/side/police_m1911.png",
	"soldier": "res://art/characters_v3/side/soldier_m249.png",
	"mechanic": "res://art/characters_v3/side/mechanic_ak47.png",
	"programmer": "res://art/characters_v3/side/programmer_de.png",
}

# ---- 走路动画（路线 B：逐帧迈步）----
# 贴图在 art/walk/{角色}_{武器}_0..3.png，4 帧一个循环：
#   F0 接触（后腿蹬地 / 前腿着地）→ F1 换腿（后腿前摆抬起、身体抬起）→ F2 反向接触 → F3 反向换腿
# 帧图是把原图的下半身做「逐行整像素位移 + 中轴镜像」生成的，
# 没有插值、没有旋转，像素网格完整，风格和原图完全一致。
const WALK_FRAME_COUNT := 4
# The previous driver frame set was built from the wrong orange-jacket sprite.
# Keep the approved upright driver visible until frames are rebuilt from that sprite.
const ENABLE_DRIVER_WALK_FRAMES := true
const WALK_KEYS := {
	"driver": "driver_mg_mp5",
	"doctor": "doctor_pistol_g17",
	"police": "police_pistol_m1911",
	"soldier": "soldier_mg_m249",
	"mechanic": "mechanic_mg_ak47",
	"programmer": "programmer_pistol_de",
}
# 每个角色的「步幅」（贴图 1216 高缩放到 180 时的一步长度，屏幕像素）
# 用来算步频，让脚和地面的相对速度对上，不会打滑
const STRIDE_PX := {
	"driver": 61.3, "doctor": 24.0, "police": 38.2,
	"soldier": 43.1, "mechanic": 0.0, "programmer": 0.0,
}

var walk_phase := 0.0          # 步伐相位（0~TAU 跑完一个 4 帧循环，每跨 π 即落脚一次）
var _ground_distance := 0.0    # 本次移动在地面上真正走过的距离，用它而不是定时器推进动画
var idle_time := 0.0           # 站立呼吸计时
var walk_frames: Array[Texture2D] = []   # 当前（角色,武器）的 4 张迈步帧
var walk_frame_idx := -1                 # 当前用的是第几帧（-1 = 还没设过）
var stride_px := 60.0                    # 当前角色的步幅（屏幕像素），用于算步频
var sprite_base_scale := Vector2.ONE  # 角色贴图的目标缩放（180px 高），压缩拉伸以它为基准
var sprite_ground_offset := 0.0       # 视觉脚底相对碰撞体底边的校正
var squash := 0.0              # 当前压缩量：>0 压扁，<0 拉伸
var _dust_tex: Texture2D = null  # 扬尘贴图（只生成一次，复用）

# ---- 枪口偏移（按角色不同，从贴图像素扫描得出，180px 高缩放后）----
# 每个角色持枪伸出长度不同，子弹/火光从这里射出
const MUZZLE_OFFSETS := {
	"mechanic":   Vector2(61, -41),
	# The approved driver sprite is 1024x1536. Its muzzle is around source
	# pixel (960, 492), which maps to this offset at the 180px display scale.
	# 22px visual grounding offset is compensated here so bullets leave the
	# horizontal muzzle at the same world height as the approved sprite.
	"driver":     Vector2(53, -32),
	"doctor":     Vector2(37, -36),
	"police":     Vector2(61, -44),
	"soldier":    Vector2(59, -48),
	"programmer": Vector2(45, -37),
}

# ---- 血量系统 ----
# 玩家 100 血，每次被丧尸/舌头打到扣 5 点（见 take_damage）
var health := 100
var max_hp := 100
var invuln := 0.0        # 无敌时间（秒）。受伤后短暂无敌，避免一帧扣光
var dead := false        # 是否已死亡（死亡后停止一切操作）
var _damage_flash: Tween = null

# ----------------------------------------------------------------------------
# _ready()：角色一进场执行一次
# ----------------------------------------------------------------------------
func _ready():
	# 碰撞层（2026-09-25）：layer1=地面；layer2=玩家；layer4=丧尸。
	# 玩家 layer=2、mask=1 → 只撞地面，与丧尸零物理交互（可穿过丧尸、不会把丧尸顶飞）。
	# 穿过丧尸的移速惩罚在 _physics_process 里按"贴身丧尸"判定另做。
	collision_layer = 2
	collision_mask = 1

	# 通用动作节点内管理独立枪械和前景手掌，隐藏旧的场景武器节点。
	if weapon_sprite != null:
		weapon_sprite.visible = false
		weapon_sprite.texture = null

	# 按当前人物 + 天赋等级套用数值（生命值上限 / 移速 / 手雷伤害 / 导弹伤害）
	_apply_character_stats()

	# 初始化武器系统：保留玩家已选的手持武器（存档/上一关的选枪），
	# 只有手持槽为空才自动补默认 M1911（修复：进下一关枪被重置回 M1911）
	Weapons.ensure_armed()
	Weapons.weapon_changed.connect(_on_weapon_changed)
	_init_ammo()   # 给所有已装备槽上满弹

	# 按（角色, 武器）组合加载贴图；没有组合图时回退到角色 v3 图
	_refresh_character_texture()
	update_hud()   # 刷新血条显示
	_update_weapon_visual()

# ----------------------------------------------------------------------------
# _apply_character_stats()：把人物数值表里算好的数值套到玩家身上
#   天赋升级只改「被天赋影响的那一项」，其余项保持基础值（见 Characters.stats_for）
# ----------------------------------------------------------------------------
func _apply_character_stats():
	var cid: String = GameState.selected_character
	char_stats = Characters.stats_for(cid, GameState.char_talent_lvs(cid))

	max_hp = int(char_stats["hp"]) + int(char_stats.get("hp_add", 0))
	health = max_hp
	speed = float(char_stats["speed"])

	var d := Characters.def(cid)
	# 下面把「基础数值 × 乘区」相乘，得到本角色的最终值：
	# 每个 *_mul 是独立乘区（天赋只改被点亮的那个，其余保持 1.0），多个乘区相互独立、直接相乘即为玩家实际生效数值。
	grenade_cd_max = float(d.get("grenade_cd", 8.0)) * float(char_stats.get("grenade_cd_mul", 1.0))
	missile_cd_max = float(d.get("missile_cd", 25.0)) * float(char_stats.get("missile_cd_mul", 1.0))
	medkit_heal_mul = float(char_stats.get("medkit_mul", 1.0))
	reload_mul = float(char_stats.get("reload_mul", 1.0))
	dmg_mul = float(char_stats.get("dmg_mul", 1.0))
	damage_taken_mul = float(char_stats.get("damage_taken_mul", 1.0))
	grenade_cd = 0.0
	missile_cd = 0.0

# ----------------------------------------------------------------------------
# _physics_process()：物理帧循环（约每秒 60 次），所有移动逻辑写这里
# ----------------------------------------------------------------------------
func _physics_process(delta):
	if dead:
		return   # 死了就什么都不做

	# 无敌时间倒计时
	if invuln > 0:
		invuln -= delta

	# 技能冷却倒计时（手雷 / 支援导弹）
	if grenade_cd > 0.0:
		grenade_cd = maxf(0.0, grenade_cd - delta)
	if missile_cd > 0.0:
		missile_cd = maxf(0.0, missile_cd - delta)

	# 换弹倒计时：结束即补满当前槽弹夹
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			ammo_by_slot[Weapons.active_slot] = Weapons.effective_magazine(Weapons.get_active_id())
			_ammo_by_weapon[Weapons.get_active_id()] = ammo_by_slot[Weapons.active_slot]
	# 医疗包冷却倒计时
	if medkit_cd > 0.0:
		medkit_cd = maxf(0.0, medkit_cd - delta)

	# ---- 重力与落地 ----
	if not is_on_floor():
		velocity.y += GRAVITY * delta   # 不在地面 → 受重力下落
	else:
		if velocity.y > 0:
			velocity.y = 0              # 落地后停止下落

	# ---- 左右移动 ----
	var dir := 0
	if Input.is_action_pressed("move_forward"):   # 默认 W 键 / 右键
		dir += 1
	if Input.is_action_pressed("move_backward"):  # 默认 S 键 / 左键
		dir -= 1
	# 丧尸群减速：与任意丧尸贴身（中心距 < 58px）时移速减半（2026-09-25）
	# 玩家与丧尸零物理碰撞（可穿过），用距离判定是否"陷在尸群里"来施加减速。
	var in_swarm := false
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(global_position) < 58.0:
			in_swarm = true
			break
	# 速度平滑地追向目标速度；人物起步、停步与逐帧步态会保持一致。
	var target_speed := dir * speed * (0.5 if in_swarm else 1.0)
	var rate := acceleration if dir != 0 else deceleration
	velocity.x = move_toward(velocity.x, target_speed, rate * delta)
	if dir != 0:
		facing = dir                  # 记录朝向
		sprite.flip_h = dir < 0       # 朝左就水平翻转贴图

	# ---- 跳跃 ----
	if Input.is_action_just_pressed("jump") and is_on_floor():   # 默认空格，且必须在地面
		velocity.y = jump_velocity
		squash = -0.12   # 起跳瞬间纵向拉伸（<0 = 拉长）

	# 执行移动（CharacterBody2D 的标准移动函数）
	var was_air := not is_on_floor()
	var previous_x := global_position.x
	move_and_slide()
	# 只记录碰撞系统实际允许的地面位移：撞到障碍物时，人物不会原地踏步。
	_ground_distance = absf(global_position.x - previous_x) if is_on_floor() else 0.0
	if was_air and is_on_floor():
		squash = 0.16    # 落地瞬间纵向压扁

	# ---- 走路/站立动画（上下起伏 + 扬尘 + 压缩拉伸）----
	_update_walk_animation(delta, _ground_distance)

	# ---- 计算瞄准方向（始终指向最近丧尸）----
	_update_aim()

	# ---- 更新武器视觉位置与角度 ----
	_update_weapon_aim()

	# ---- 射击 ----
	shoot_timer -= delta
	# ★ 鼠标左键开火前先看指针是否悬在 UI 控件上（按钮/面板等）。
	#   Input.is_mouse_button_pressed() 是轮询原始鼠标状态，不经过 GUI 事件系统，
	#   点「菜单/商店/设置」按钮的那一下按下会被误当成开火 → 点菜单就开枪。
	#   悬在 UI 上时禁止鼠标开火；键盘 J（shoot 动作）不受影响。
	var over_ui: bool = get_viewport().gui_get_hovered_control() != null
	if shoot_timer <= 0 and (Input.is_action_pressed("shoot") or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not over_ui)):
		shoot()

# ----------------------------------------------------------------------------
# _update_walk_animation()：走路/站立的程序化动画（不换贴图）
#   · 走路：身体按正弦曲线上下起伏，每走一段距离在脚底扬起尘土
#   · 站立：极轻微的呼吸起伏
#   · 起跳/落地：整体压缩拉伸（squash & stretch）
# ----------------------------------------------------------------------------
func _update_walk_animation(delta, moved_distance := 0.0):
	if sprite == null:
		return
	if character_locomotion != null and character_locomotion.visible:
		character_locomotion.modulate = sprite.modulate
		if character_locomotion.advance(delta, moved_distance, is_on_floor(), facing, velocity.y):
			_spawn_footstep_dust()
		squash = 0.0
		return

	var moving := moved_distance > 0.01 and is_on_floor()

	if moving:
		# 一整个循环有左右两步。相位由实际走过的像素数推进，
		# 所以无论帧率、加速度或碰撞如何变化，脚步都不会脱离位移节奏。
		var prev_phase := walk_phase
		var cycle_distance := maxf(1.0, 2.0 * stride_px)
		walk_phase = fmod(walk_phase + moved_distance / cycle_distance * TAU, TAU)
		# 逐帧换贴图：4 帧均分一个循环
		_apply_walk_frame(int(walk_phase / (TAU / WALK_FRAME_COUNT)) % WALK_FRAME_COUNT)
		# 贴图保持与碰撞体同一水平锚点，不能额外左右漂移，否则会显得脚在滑。
		sprite.position.x = lerpf(sprite.position.x, 0.0, 0.35)
		sprite.position.y = lerpf(sprite.position.y, sprite_ground_offset, 0.4)

		# 脚步扬尘：相位每跨过 π 的整数倍 = 脚落地瞬间（F0 / F2 都是落脚帧）
		if int(walk_phase / PI) != int(prev_phase / PI):
			_spawn_footstep_dust()
	else:
		# 站立/滞空：停在接触帧，轻微呼吸
		idle_time += delta
		_apply_walk_frame(0)
		sprite.position.y = lerpf(sprite.position.y, sprite_ground_offset + sin(idle_time * 2.2) * 0.9, 0.15)
		sprite.position.x = lerpf(sprite.position.x, 0.0, 0.2)

	# 压缩拉伸：逐帧衰减回 0
	squash = lerpf(squash, 0.0, 0.18)
	if sprite_base_scale != Vector2.ZERO:
		sprite.scale = Vector2(
			sprite_base_scale.x * (1.0 - squash),
			sprite_base_scale.y * (1.0 + squash)
		)

# ----------------------------------------------------------------------------
# _apply_walk_frame()：切换到第 idx 张迈步帧（idx 不变就不动，省开销）
# ----------------------------------------------------------------------------
func _apply_walk_frame(idx: int):
	if walk_frames.size() != WALK_FRAME_COUNT:
		return                      # 没生成过这套帧，保持原贴图
	if idx == walk_frame_idx:
		return
	walk_frame_idx = idx
	sprite.texture = walk_frames[idx]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

# ----------------------------------------------------------------------------
# _spawn_footstep_dust()：脚底扬起一小撮尘土
# ----------------------------------------------------------------------------
func _spawn_footstep_dust():
	if get_parent() == null:
		return
	var d := Sprite2D.new()
	d.texture = _footstep_dust_texture()
	d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 落脚点：角色中心往下约一个半身（脚底附近），在朝向反侧稍稍偏后
	d.global_position = global_position + Vector2(-facing * randf_range(0.0, 8.0), 86.0)
	d.z_index = -1
	var sc := randf_range(0.45, 0.75)
	d.scale = Vector2(sc, sc)
	d.modulate.a = randf_range(0.55, 0.85)
	get_parent().add_child(d)

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(d, "position:y", d.position.y - 12.0, 0.36)
	tw.tween_property(d, "position:x", d.position.x - facing * 10.0, 0.36)
	tw.tween_property(d, "modulate:a", 0.0, 0.36)
	tw.chain().tween_callback(d.queue_free)

# 生成一张小圆形尘土贴图（只做一次，之后重复使用）
func _footstep_dust_texture() -> Texture2D:
	if _dust_tex != null:
		return _dust_tex
	var sz := 14
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (sz - 1) / 2.0
	for y in range(sz):
		for x in range(sz):
			var dd := Vector2(x - c, y - c).length()
			if dd < 6.0:
				var a := clampf(1.0 - dd / 6.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.70, 0.66, 0.58, a))
	_dust_tex = ImageTexture.create_from_image(img)
	return _dust_tex

# ----------------------------------------------------------------------------
# shoot()：发射子弹
# ----------------------------------------------------------------------------
func shoot():
	if dead or reloading:
		return
	var wid: String = Weapons.get_active_id()
	var wp := Weapons.get_effective(wid)
	var slot: int = Weapons.active_slot
	var cur: int = int(ammo_by_slot.get(slot, 0))
	# 弹夹打空 → 自动开始换弹（换弹期间不能射击）
	if cur <= 0:
		start_reload()
		return
	ammo_by_slot[slot] = cur - 1
	_ammo_by_weapon[wid] = cur - 1
	shoot_timer = 1.0 / wp.fire_rate   # 射击冷却 = 1 ÷ 射速(fire_rate，单位：发/秒)。射速越高，两次射击间隔越短
	var b := bullet_scene.instantiate()

	# 子弹从枪口射出：按角色查表获取枪口偏移（180px 高缩放后）
	# 朝向翻转（sprite.flip_h=true）时：x 取负，y 不变
	var muzzle_base: Vector2 = MUZZLE_OFFSETS.get(GameState.selected_character, Vector2(50, -40))   # 查不到角色时的兜底枪口偏移（右 50px、上 40px）
	var muzzle_x := muzzle_base.x if facing > 0 else -muzzle_base.x
	var muzzle_y := muzzle_base.y
	var muzzle_pos := global_position + Vector2(muzzle_x, muzzle_y)
	if character_locomotion != null and character_locomotion.visible:
		muzzle_pos = global_position + character_locomotion.muzzle_local()
	b.global_position = muzzle_pos
	b.direction = aim_dir
	# 子弹伤害 = 武器基础伤害 × 角色伤害乘区(dmg_mul，军人「军械精通」天赋)。
	# 先乘后 round 取整：保证最终伤害是整数，避免浮点小数伤害在多次命中时累积误差。
	b.damage = int(round(wp.damage * dmg_mul))
	b.owner_node = self          # 告诉子弹「我是发射者」，避免打到自己
	b.bullet_size = wp.get("bullet_size", 1.0)        # 子弹大小（和枪械口径成比例）
	b.bullet_tracer = wp.get("bullet_tracer", false)  # 机枪有曳光
	get_parent().add_child(b)

	# 枪口火光
	_spawn_muzzle_flash(muzzle_pos, wp.get("bullet_size", 1.0))

	# 射击后坐力：武器轻微后移
	if weapon_sprite != null:
		weapon_sprite.position -= aim_dir * 1.5
	if has_node("/root/AudioManager"):
		# 开枪音效按武器射速自动分流：射速快用极短快音（shoot_auto），慢速用完整单发（shoot_pistol）
		AudioManager.play_shoot(wp.fire_rate)

# ----------------------------------------------------------------------------
# _spawn_muzzle_flash()：在枪口位置生成短暂火光效果
# ----------------------------------------------------------------------------
func _spawn_muzzle_flash(pos: Vector2, wp_size: float):
	var flash := Sprite2D.new()
	flash.name = "MuzzleFlash"
	flash.z_index = 5   # 盖在角色之上

	# 画一个星形火光贴图（中心白黄 → 外圈橙红 → 十字射线）
	var sz := 20
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := sz / 2
	for y in range(sz):
		for x in range(sz):
			var dx := x - c
			var dy := y - c
			var dist := sqrt(dx * dx + dy * dy)
			if dist < 2:
				img.set_pixel(x, y, Color(1, 1, 0.85, 1))         # 白黄核心
			elif dist < 4:
				img.set_pixel(x, y, Color(1, 0.8, 0.2, 0.95))     # 黄色
			elif dist < 6:
				img.set_pixel(x, y, Color(1, 0.45, 0.1, 0.7))     # 橙色
			elif (abs(dx) <= 1 and abs(dy) < 9) or (abs(dy) <= 1 and abs(dx) < 9):
				img.set_pixel(x, y, Color(1, 0.5, 0.1, 0.35))     # 十字射线

	flash.texture = ImageTexture.create_from_image(img)
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flash.global_position = pos
	flash.rotation = aim_dir.angle()           # 旋转对齐射击方向
	var sc := 0.8 + wp_size * 0.5              # 大口径武器火光更大
	flash.scale = Vector2(sc, sc)
	get_parent().add_child(flash)

	# 动画：快速放大 + 淡出，0.08 秒后删除
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector2(sc * 1.6, sc * 1.6), 0.03)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)

# 初始化所有已装备槽的弹量（开局满弹）
func _init_ammo():
	_ammo_by_weapon = {}
	_sync_ammo_slots()

func _sync_ammo_slots():
	ammo_by_slot = {}
	for i in range(Weapons.LOADOUT_SLOT_COUNT):
		var wid: String = Weapons.loadout[i]
		if wid != "" and Weapons.DATA.has(wid):
			var magazine: int = Weapons.effective_magazine(wid)
			var remaining: int = clampi(int(_ammo_by_weapon.get(wid, magazine)), 0, magazine)
			_ammo_by_weapon[wid] = remaining
			ammo_by_slot[i] = remaining

# 开始换弹（已换弹中则忽略；死亡时不允许）
func start_reload():
	if dead or reloading:
		return
	reloading = true
	# 换弹时间 = 武器基础换弹时间 × 换弹乘区(reload_mul)。
	# 用 maxf(0.15, ...) 设下限 0.15 秒：即使天赋把换弹缩到极快，也至少有 0.15s 的换弹动作手感，避免瞬间换弹。
	reload_timer = maxf(0.15, Weapons.effective_reload(Weapons.get_active_id()) * reload_mul)

# 使用医疗包：消耗背包里的医疗包，恢复 50 生命，1.5s 冷却
func use_medkit() -> bool:
	if dead or medkit_cd > 0.0:
		return false
	if GameState.item_count("medkit") <= 0:
		return false
	GameState.remove_item("medkit", 1)
	health = mini(max_hp, health + int(round(float(MEDKIT_HEAL) * medkit_heal_mul)))
	medkit_cd = MEDKIT_CD_MAX
	update_hud()
	# 绿色闪烁提示回血
	if sprite != null:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(0.4, 1.0, 0.5), 0.05)
		tw.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2)
	return true

func _update_aim():
	# 自动瞄准：只在枪口朝向（facing）那一侧、且「当前在视口内」的丧尸里找最近的一个
	# 朝右(facing=1)时只瞄右边的丧尸，朝左(facing=-1)时只瞄左边的丧尸
	# 屏幕内没有符合条件的丧尸时，保持水平朝前射击
	#   —— 关键修复：丧尸出生时落在屏幕外(x=玩家+1100)且正从地里往上爬，
	#      旧逻辑会把这些「看不见的丧尸」也锁成目标，导致枪口朝屏幕外偏下的点、
	#      子弹沿一条向下倾斜的对角线飞（看着像"不沿直线"）。
	#      现在用相机可见矩形过滤掉屏外丧尸，屏内无丧尸就严格水平直射。
	aim_dir = Vector2(facing, 0)
	var zombies := get_tree().get_nodes_in_group("zombies")
	var nearest = null
	var nearest_dist := INF
	# 取相机可见矩形（世界坐标），用于过滤屏幕外的丧尸
	var cam := get_viewport().get_camera_2d()
	var view_rect := Rect2()
	if cam != null:
		var center := cam.get_screen_center_position()      # 屏幕中心对应的世界坐标
		var half := get_viewport().get_visible_rect().size * 0.5 * cam.zoom   # 半屏（世界单位，含缩放）
		view_rect = Rect2(center.x - half.x, center.y - half.y, half.x * 2.0, half.y * 2.0)
	for z in zombies:
		# 方向过滤：只有丧尸在 facing 方向上（身前）才参与瞄准
		var offset_x: float = z.global_position.x - global_position.x
		if offset_x * facing <= 0:
			continue   # 丧尸在身后或正上方，跳过
		# 可见性过滤：只瞄「当前在屏幕内」的丧尸；屏外（含刚出生正在爬出的）不参与，避免子弹斜飞
		if cam != null and not view_rect.has_point(z.global_position):
			continue
		var d := global_position.distance_to(z.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = z
	if nearest != null:
		aim_dir = (nearest.global_position - global_position).normalized()

# ----------------------------------------------------------------------------
# _update_weapon_aim()：把独立武器贴图(weapon_sprite)对齐到瞄准方向
#   参数：无（读取全局 aim_dir 与 facing）
#   作用：武器绕自身旋转指向目标；朝左时水平翻转贴图（y 缩放取负）并切到左手偏移
#         朝右时用右手偏移，保持武器贴图永远在身前一侧
# ----------------------------------------------------------------------------
func _update_weapon_aim():
	if character_locomotion != null and character_locomotion.visible:
		return
	if weapon_sprite == null:
		return
	var angle := aim_dir.angle()
	weapon_sprite.rotation = angle
	if aim_dir.x >= 0:
		weapon_sprite.position = HAND_OFFSET_RIGHT
		weapon_sprite.scale = Vector2(weapon_base_scale.x, weapon_base_scale.y)
	else:
		weapon_sprite.position = HAND_OFFSET_LEFT
		weapon_sprite.scale = Vector2(weapon_base_scale.x, -weapon_base_scale.y)

func _input(event):
	if dead:
		return
	# 数字键 1~9、0：把对应序号的武器装备到「当前手持槽」（实际覆盖 ORDER 前 10 把，见下方循环）
	# Q：在已装备的两个槽之间切换手持武器
	if event is InputEventKey and event.pressed and not event.echo:
		# 数字键 1~9、0：把对应序号的武器装备到「当前手持槽」
		# 覆盖 ORDER 前 10 把；其余武器（序号更大）用商店 B 装备 / 切换
		var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
		for i in range(keys.size()):
			if event.keycode == keys[i]:
				if i < Weapons.ORDER.size():
					var id: String = Weapons.ORDER[i]
					if Weapons.is_unlocked(id):
						Weapons.equip_to_slot(Weapons.active_slot, id)
					else:
						print("武器未解锁: %s (需要 %d 金币)" % [Weapons.DATA[id].name, Weapons.DATA[id].price])
		if event.keycode == KEY_Q:
			Weapons.swap_active()
		# G：投掷手雷（范围爆炸伤害）
		if event.keycode == KEY_G:
			throw_grenade()
		# H：呼叫支援导弹（从天而降，范围伤害）
		if event.keycode == KEY_H:
			launch_missile()
		# R：手动换弹（弹夹没满也能换）
		if event.keycode == KEY_R:
			start_reload()
		# F：使用医疗包（局内按 F 回血）
		if event.keycode == KEY_F:
			use_medkit()

# ----------------------------------------------------------------------------
# throw_grenade()：朝身前抛出一颗手雷（冷却好了才允许）
# ----------------------------------------------------------------------------
func throw_grenade() -> bool:
	if dead or grenade_cd > 0.0:
		return false
	# 消耗品：没有手雷库存时不允许投掷（弹药 + 冷却双重门槛）
	if GameState.grenade_ammo <= 0:
		return false
	var g = GRENADE_SCRIPT.new()
	g.setup(int(char_stats.get("grenade_damage", 60)), facing)
	get_parent().add_child(g)
	g.global_position = global_position + Vector2(float(facing) * 22.0, -34.0)   # 手雷从身前 22px、头顶上方 34px 处抛出（避免直接生成在脚下）
	GameState.grenade_ammo -= 1
	GameState.save_profile()
	grenade_cd = grenade_cd_max
	return true

# ----------------------------------------------------------------------------
# launch_missile()：在目标位置呼叫一枚从天而降的支援导弹
#   落点 = 离玩家最近的丧尸；附近没丧尸就落在玩家身前 260px
# ----------------------------------------------------------------------------
func launch_missile() -> bool:
	if dead or missile_cd > 0.0:
		return false
	# 消耗品：没有导弹库存时不允许呼叫（弹药 + 冷却双重门槛）
	if GameState.missile_ammo <= 0:
		return false
	var m = MISSILE_SCRIPT.new()
	m.setup(int(char_stats.get("missile_damage", 150)), _pick_missile_target_x())
	get_parent().add_child(m)
	GameState.missile_ammo -= 1
	GameState.save_profile()
	missile_cd = missile_cd_max
	return true

# 选导弹落点：优先砸离玩家最近的丧尸（不分左右），否则砸玩家身前
func _pick_missile_target_x() -> float:
	var nearest = null
	var nearest_dist := INF
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z):
			continue
		var n2 := z as Node2D
		if n2 == null:
			continue
		var d := global_position.distance_to(n2.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = n2
	if nearest != null:
		return nearest.global_position.x
	return global_position.x + float(facing) * 260.0   # 附近无丧尸时，导弹默认落在玩家身前 260px 处

func _on_weapon_changed(id: String):
	_sync_ammo_slots()
	reloading = false
	reload_timer = 0.0
	_update_weapon_visual()

func _update_weapon_visual():
	# CharacterLocomotion owns HeldWeapon and its hand layers.
	# The legacy scene weapon must not draw a duplicate gun.
	if weapon_sprite != null:
		weapon_sprite.texture = null
		weapon_sprite.visible = false
	# 武器变化时刷新（角色×武器）组合贴图
	_refresh_character_texture()

# 六个人物共用动作节点；武器按实际 ID 装配，旧图仅用作缺失资源时的兜底。
func _refresh_character_texture():
	var char_id: String = GameState.selected_character
	var wid: String = Weapons.current_id
	if character_locomotion == null:
		character_locomotion = CHARACTER_LOCOMOTION.new()
		character_locomotion.name = "CharacterLocomotion"
		add_child(character_locomotion)
	if character_locomotion.configure(char_id, wid, Weapons.get_effective(wid)):
		character_locomotion.show()
		sprite.hide()
		walk_frames.clear()
		walk_frame_idx = -1
		character_locomotion.advance(0.0, 0.0, is_on_floor(), facing, velocity.y)
		return
	if character_locomotion != null:
		character_locomotion.hide()
	sprite.show()
	var combo := "res://art/chars/%s_%s.png" % [char_id, wid]
	var armed := "res://art/chars/%s_m1911.png" % char_id
	var fallback := "res://art/%s.png" % char_id
	var path: String = REMADE_SIDE_TEXTURES.get(char_id, combo)
	if not ResourceLoader.exists(path):
		path = combo
	if not ResourceLoader.exists(path):
		path = armed
	if not ResourceLoader.exists(path):
		path = fallback
	print("[player] char=%s weapon=%s -> load %s" % [char_id, wid, path])
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var scale_by_visible_height := {
			"driver": 0.1430,
			"doctor": 0.1287,
			"police": 0.1284,
			"soldier": 0.1351,
			"mechanic": 0.1267,
			"programmer": 0.1329,
		}
		var s: float = float(scale_by_visible_height.get(char_id, 180.0 / tex.get_height()))
		# The approved driver has transparent padding below the boots. Move only
		# the visual sprite down to the collision bottom; this does not alter its
		# scale or the muzzle's world height calculation.
		sprite_ground_offset = float({
			"driver": 7.1,
			"doctor": 3.5,
			"police": 4.2,
			"soldier": 7.3,
			"mechanic": 3.3,
			"programmer": 5.0,
		}.get(char_id, 0.0))
		# 记下基准缩放：起跳/落地压缩拉伸以它为基准，避免把角色越缩越小
		sprite_base_scale = Vector2(s, s)
		sprite.scale = sprite_base_scale
		stride_px = float(STRIDE_PX.get(char_id, 60.0))
		if stride_px <= 0.1:
			stride_px = 60.0
		# Only the driver's remade four-frame set is ready. Other characters keep
		# their remade static side texture instead of falling back to old frames.
		walk_frames.clear()
		walk_frame_idx = -1
		var walk_key: String = WALK_KEYS.get(char_id, "")
		if ENABLE_DRIVER_WALK_FRAMES and not walk_key.is_empty():
			_load_walk_frames(walk_key)
			if walk_frames.size() == WALK_FRAME_COUNT:
				_apply_walk_frame(0)
	else:
		var img: Image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.25, 0.6, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)

# 加载 art/walk/{key}_0..3.png；缺任何一张就整体放弃（保持原贴图不动）
func _load_walk_frames(key: String):
	walk_frames.clear()
	walk_frame_idx = -1
	var got: Array[Texture2D] = []
	for i in range(WALK_FRAME_COUNT):
		var p := "res://art/walk/%s_%d.png" % [key, i]
		if not ResourceLoader.exists(p):
			return
		got.append(load(p) as Texture2D)
	walk_frames = got

# ----------------------------------------------------------------------------
# update_hud()：刷新左下角血条
# 血条用 ColorRect，直接改宽度和颜色，简单可靠（不用图片）
# ----------------------------------------------------------------------------
func update_hud():
	var bar_fg: ColorRect = get_tree().get_first_node_in_group("health_bar_fg")
	var label: Label = get_tree().get_first_node_in_group("health_label")
	if bar_fg != null:
		var pct := float(health) / float(max_hp)
		pct = clamp(pct, 0.0, 1.0)
		# 宽度：满血 196px，按剩余血量百分比缩放
		bar_fg.size.x = int(196.0 * pct)
		# 颜色随血量变化：>50% 绿，>25% 黄，否则红
		if pct > 0.5:
			bar_fg.color = Color(0.15, 0.85, 0.2, 1)    # 绿色
		elif pct > 0.25:
			bar_fg.color = Color(0.9, 0.75, 0.1, 1)     # 黄色
		else:
			bar_fg.color = Color(0.9, 0.12, 0.12, 1)     # 红色
	if label != null:
		label.text = "HP: %d" % health   # 显示数字，如 HP: 95

# ----------------------------------------------------------------------------
# take_damage()：受伤扣血
#   amount 是扣多少点（丧尸/舌头都传 5）
# ----------------------------------------------------------------------------
func take_damage(amount):
	if amount <= 0 or invuln > 0 or dead:
		return   # 无敌中或已死 → 不扣
	# 维修工「加固护甲」：受伤按乘区减免；至少扣 1 点，避免低伤害被减免到 0 变成免伤
	health -= maxi(1, int(round(float(amount) * damage_taken_mul)))
	invuln = 1.0        # 受伤后 1 秒无敌
	update_hud()        # 刷新血条
	# 致命伤同步结算，避免闪烁等待期间仍能开枪、回血或触发通关。
	if health <= 0:
		health = 0
		_show_game_over()
		return
	# 闪红一下提示受伤
	if _damage_flash != null and _damage_flash.is_valid():
		_damage_flash.kill()
	sprite.modulate = Color(1, 0.3, 0.3)
	_damage_flash = create_tween()
	_damage_flash.tween_interval(0.12)
	_damage_flash.tween_property(sprite, "modulate", Color.WHITE, 0.0)

# ----------------------------------------------------------------------------
# _show_game_over()：显示「游戏结束」面板，并按 R 重开
# ----------------------------------------------------------------------------
func _show_game_over():
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	died.emit()
	var go_panel: Control = get_tree().get_first_node_in_group("game_over_panel")
	if go_panel != null:
		go_panel.visible = true   # 显示结束面板（Main.tscn 里已做好）
		# 让所有丧尸停下
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.has_method("stop_moving"):
				z.stop_moving()
		# 等待玩家按 R 重开
		while true:
			await get_tree().process_frame
			# 等待期间场景可能被切走（返回关卡选择/返回主界面）→ 协程安静结束
			if not is_inside_tree():
				return
			if Input.is_key_pressed(KEY_R):
				get_tree().reload_current_scene()
				return
	else:
		# 没有结束面板就直接等 0.6 秒重开
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree():
			return   # 等待期间场景已被切走
		get_tree().reload_current_scene()
