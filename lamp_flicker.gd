extends RefCounted

# ============================================================================
# lamp_flicker.gd —— 街灯闪烁（材质工厂 + 亮度曲线，纯静态工具类）
# ============================================================================
# 挂在场景里的灯（background_lamp.gd / 主界面）通过 preload 引用本文件。
# 提供两个静态方法：
#   create_material()          -> 造一个挂 street_lamp.gdshader 的材质
#   strength_at_time(时间,周期) -> 算某个时刻该有多亮（0.06~1.0）
#
# 闪烁节奏：进关 6 秒内稳定常亮，之后每 6 秒来一次「短促熄灭 → 缓慢恢复」，
# 模拟老式街灯接触不良的感觉。纯 RefCounted，不进场景树、不含任何节点逻辑。
# ============================================================================

const SHADER := preload("res://street_lamp.gdshader")
const CYCLE_SECONDS := 6.0

static func create_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("lamp_strength", 1.0)
	return result

# Six steady seconds on entry, then one brief dip and recovery every six seconds.
static func strength_at_time(elapsed: float, cycle_seconds: float = CYCLE_SECONDS) -> float:
	var cycle := maxf(cycle_seconds, 0.5)
	if elapsed < cycle:
		return 1.0
	var phase := fposmod(elapsed, cycle)
	if phase < 0.09:
		return lerpf(1.0, 0.06, smoothstep(0.0, 0.09, phase))
	if phase < 0.17:
		return 0.06
	if phase < 0.40:
		return lerpf(0.06, 1.0, smoothstep(0.17, 0.40, phase))
	return 1.0
