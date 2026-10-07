extends RefCounted

# ============================================================================
# weapon_visuals.gd —— 16 把枪的握持/枪口锚点数据（归一化坐标，纯数据表）
# ----------------------------------------------------------------------------
# 原英文注释机翻：
#   「归一化的源图锚点：后握把、辅助手掌、枪口出口。」
#   「flip（水平翻转）在贴合之前就已经应用了（原始 MP5 图朝左）。」
#
# 【坐标为什么是 0~1 小数】
# 用**归一化比例**而不是像素，这样同一张枪图不管实际多大、裁剪多少，
# 都能算出正确的握持点，换分辨率也不用重标。
#
# 【字段含义】
#   grip    —— 后握把位置（主手握这里）
#   muzzle  —— 枪口位置（子弹生成点、枪口火光特效都挂这里）
#   height  —— 枪身在图中的显示高度（做贴合缩放用）
#
# 【关于 flip】
# 原始枪图有的是朝左、有的是朝右。代码先把朝向统一（左）再按比例贴合，
# 所以这里的坐标是「已翻转后」对应关系，改图时注意先翻转再量坐标。
#
# 【想改的地方】
#   换枪图/改枪身 → 重新量 grip / muzzle；新增枪 → 在 DATA 里加一项
# ============================================================================

## Normalized source-image anchors: rear grip, support palm, barrel exit.
## flip is applied before fitting (the original MP5 points left).
const DATA = {
	"pistol_m1911":{"grip":Vector2(.23,.66),"muzzle":Vector2(.992,.22),"height":173.0},
	"pistol_g17":{"grip":Vector2(.332,.66),"muzzle":Vector2(.800,.265),"height":231.0},
	"pistol_de":{"grip":Vector2(.21,.64),"muzzle":Vector2(.99,.17),"height":179.0},
	"pistol_p250":{"grip":Vector2(.25,.64),"muzzle":Vector2(.99,.22),"height":169.0},
	"pistol_m45":{"grip":Vector2(.22,.64),"muzzle":Vector2(.99,.20),"height":173.0},
	"pistol_p226":{"grip":Vector2(.21,.65),"muzzle":Vector2(.99,.21),"height":170.0},
	"pistol_fn57":{"grip":Vector2(.19,.65),"muzzle":Vector2(.985,.25),"height":169.0},
	"pistol_m500":{"grip":Vector2(.17,.77),"muzzle":Vector2(.99,.235),"height":192.0},
	"mg_mp5":{"grip":Vector2(.58,.64),"support":Vector2(.21,.42),"muzzle":Vector2(.014,.43),"flip":true},
	"mg_ak47":{"grip":Vector2(.28,.54),"support":Vector2(.60,.40),"muzzle":Vector2(.895,.24)},
	"mg_m249":{"grip":Vector2(.325,.54),"support":Vector2(.665,.375),"muzzle":Vector2(.976,.258)},
	"mg_ump45":{"grip":Vector2(.355,.60),"support":Vector2(.715,.47),"muzzle":Vector2(.996,.356)},
	"mg_m4a1":{"grip":Vector2(.415,.58),"support":Vector2(.745,.46),"muzzle":Vector2(.993,.292)},
	"mg_g36":{"grip":Vector2(.35,.70),"support":Vector2(.71,.45),"muzzle":Vector2(.992,.426)},
	"mg_pkm":{"grip":Vector2(.285,.64),"support":Vector2(.65,.47),"muzzle":Vector2(.994,.275)},
	"mg_m134":{"grip":Vector2(.37,.93),"support":Vector2(.735,.77),"muzzle":Vector2(.99,.625)},
}

static func anchors(weapon_id: String) -> Dictionary:
	return DATA.get(weapon_id, {}).duplicate()
