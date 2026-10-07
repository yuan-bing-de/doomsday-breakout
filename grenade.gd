extends Node2D

# ============================================================================
# grenade.gd —— 手雷（玩家按 G 投掷）
# ============================================================================
# 生命周期：从玩家身前抛出 → 抛物线飞行（自转）→ 落地瞬间引爆
#          → 对半径 RADIUS 内所有丧尸造成范围伤害 + 爆炸特效 → 自己消失
#
# 伤害与冷却由人物数值表（Characters.gd）决定，player.gd 在投掷时通过
# setup() 传进来，这里不写死人物相关的数值。
# ============================================================================

const GRAVITY := 1600.0        # 手雷自己的重力（比角色重一些，落得更利落）
const THROW_VX := 460.0        # 水平初速（像素/秒），乘朝向
const THROW_VY := -330.0       # 垂直初速（负数=向上抛）
const GROUND_Y := 478.0        # 落脚线（同丧尸/金币用的路面）
const BLAST_RADIUS := 150.0    # 爆炸范围半径（像素）
const FUSE_MAX := 2.2          # 最长引信：万一一直没落地，到这个时间也炸
const SPIN := 9.0              # 自转角速度（视觉）

var damage := 60               # 爆炸伤害（由 player.gd 传入）
var _vx := 0.0
var _vy := 0.0
var _age := 0.0
var _exploded := false
var _sprite: Sprite2D = null


# 由 player.gd 在投掷时调用：伤害 + 投掷方向（1=右，-1=左）
func setup(dmg: int, dir: int):
	damage = dmg
	_vx = THROW_VX * float(dir if dir != 0 else 1)
	_vy = THROW_VY


# ----------------------------------------------------------------------------
# _ready()：手雷生成时创建自身贴图并设层级
#   作用：用代码画一颗手雷贴图挂到本节点；z_index=4 让它盖在角色/丧尸之上
# ----------------------------------------------------------------------------
func _ready():
	_sprite = Sprite2D.new()
	_sprite.texture = _grenade_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	z_index = 4


# ----------------------------------------------------------------------------
# _process()：每帧推进手雷的抛物线飞行
#   参数：delta 帧间隔（秒）
#   作用：施加重力(_vy 累加 GRAVITY)、平移、自转；落地（y 到达落脚线附近）
#         或引信到期(FUSE_MAX) 就触发 _explode()
# ----------------------------------------------------------------------------
func _process(delta: float):
	if _exploded:
		return

	_age += delta
	_vy += GRAVITY * delta
	global_position += Vector2(_vx, _vy) * delta
	rotation += SPIN * delta          # 空中自转（小物件，不影响像素网格观感）

	# 落地判定：y 到达「落脚线上方 12px」即视为砸到地面；或引信 _age 超过 FUSE_MAX(2.2s) 强制引爆，双保险
	if global_position.y >= GROUND_Y - 12.0 or _age >= FUSE_MAX:
		_explode()


# ----------------------------------------------------------------------------
# _explode()：引爆手雷
#   作用：① 把爆炸中心 y 压到地面附近（GROUND_Y-8）② 调用 Explosion 对半径内丧尸造成伤害
#         ③ 播放爆炸特效 ④ 播放音效 ⑤ 删除自身。
#   _exploded 标志保证即使被多次调用也只炸一次（幂等）
# ----------------------------------------------------------------------------
func _explode():
	if _exploded:
		return
	_exploded = true
	var center := global_position
	center.y = minf(center.y, GROUND_Y - 8.0)   # 爆炸高度不超过地面上方 8px，避免炸点悬在半空

	var parent := get_parent()
	Explosion.damage_zombies(center, BLAST_RADIUS, damage)
	if parent != null:
		Explosion.blast(parent, center, BLAST_RADIUS)
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("explosion")   # 有 res://audio/explosion.ogg 才会响，没有则静默
	queue_free()


# ----------------------------------------------------------------------------
# 代码画一颗手雷：墨绿椭圆弹体 + 顶部引信头 + 拉环
# ----------------------------------------------------------------------------
func _grenade_texture() -> Texture2D:
	var w := 16
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.22, 0.30, 0.20)     # 墨绿
	var body_hi := Color(0.36, 0.46, 0.32)
	var body_lo := Color(0.13, 0.18, 0.12)
	for y in range(6, h - 1):
		var t := float(y - 6) / float(h - 7)
		var half := 5.0 - absf(t - 0.5) * 2.2
		for x in range(w):
			var dx := absf(float(x) - (w - 1) / 2.0)
			if dx <= half:
				if float(x) < (w - 1) / 2.0 - half * 0.35:
					img.set_pixel(x, y, body_hi)
				elif float(x) > (w - 1) / 2.0 + half * 0.4:
					img.set_pixel(x, y, body_lo)
				else:
					img.set_pixel(x, y, body)
	# 顶部引信头
	for y in range(2, 6):
		for x in range(5, 11):
			img.set_pixel(x, y, Color(0.42, 0.40, 0.36))
	# 拉环（小圆环）
	for x in range(10, 15):
		img.set_pixel(x, 3, Color(0.62, 0.62, 0.66))
	img.set_pixel(14, 4, Color(0.62, 0.62, 0.66))
	return ImageTexture.create_from_image(img)
