extends Node2D

# ============================================================================
# background_lamp.gd —— 背景场景里的街灯（Node2D 节点版）
# ============================================================================
# 与主界面共用 UV 灯光材质（复用 lamp_flicker.gd），背景场景单独预览时效果一致。
# 挂在背景场景的灯节点上，每帧按 cycle_seconds 周期把亮度写进 shader 参数。
# 注意：真正的闪烁曲线/材质工厂在 lamp_flicker.gd，这里只负责「挂上去 + 驱动」。
# ============================================================================

const LampFlicker := preload("res://lamp_flicker.gd")
@export_range(0.5, 60.0) var cycle_seconds := 6.0
@onready var backdrop: Sprite2D = $Backdrop
var _elapsed := 0.0
var _lamp_material: ShaderMaterial

func _ready() -> void:
	_lamp_material = LampFlicker.create_material()
	backdrop.material = _lamp_material

func _process(delta: float) -> void:
	_elapsed += delta
	_lamp_material.set_shader_parameter("lamp_strength", LampFlicker.strength_at_time(_elapsed, cycle_seconds))
