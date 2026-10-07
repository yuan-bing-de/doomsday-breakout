// ============================================================================
// street_lamp.gdshader —— 街灯光晕着色器（主界面/背景的灯具发光效果）
// ----------------------------------------------------------------------------
// 英文注释机翻：「使用源图 UV 坐标，使效果固定在画出来的灯具上。」
//
// 【它做什么】
// 在画好的街灯贴图上叠一层柔和的椭圆光晕，营造夜晚氛围。
// 亮度由 lamp_strength 控制，lamp_flicker.gd 每帧按「6 秒稳定 + 短促闪烁」
// 的节奏改这个值，就有了老式路灯接触不良的忽明忽暗感。
//
// 【关键参数】
//   lamp_strength — 整体亮度（0~1）。1=全亮，0.06=几乎熄灭（闪烁最低点）
//
// 【实现要点】
//   用源图的 UV 坐标算光晕，保证光晕「长在灯具上」而不是跟着窗口跑。
//   render_mode unshaded —— 不受场景灯光影响，保证光晕始终可见。
//   soft_ellipse() —— 软边缘椭圆，用 smoothstep 做渐变避免硬边。
//
// 【配套文件】
//   lamp_flicker.gd 提供材质工厂与亮度曲线，background_lamp.gd 挂在节点上驱动。
// ============================================================================
shader_type canvas_item;
render_mode unshaded;

// Source-art UV coordinates keep the effect attached to the painted fixture.
uniform float lamp_strength : hint_range(0.0, 1.0) = 1.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

float soft_ellipse(vec2 uv, vec2 center, vec2 radius) {
	float d = length((uv - center) / radius);
	return 1.0 - smoothstep(0.35, 1.0, d);
}

float fixture_ellipse(vec2 uv, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.72, 1.08, length((uv - center) / radius));
}

void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	float outage = 1.0 - lamp_strength;
	float luminance = dot(painted.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Glass cage and lit underside of the shade, preserving dark metal detail.
	float glass = fixture_ellipse(UV, vec2(0.2078, 0.1710), vec2(0.0180, 0.0420));
	float shade = fixture_ellipse(UV, vec2(0.2075, 0.1460), vec2(0.0330, 0.0140));
	float emission = max(glass, shade) * smoothstep(0.18, 0.78, luminance);
	// More spill below the shade than above it; subtract the baked-in halo.
	float halo = soft_ellipse(UV, vec2(0.2078, 0.2030), vec2(0.0660, 0.1270));
	halo *= smoothstep(0.118, 0.160, UV.y);
	vec3 color = max(vec3(0.0), painted.rgb - outage * halo * vec3(0.140, 0.130, 0.100));
	vec3 unlit_glass = painted.rgb * vec3(0.13, 0.16, 0.20);
	color = mix(color, unlit_glass, emission * outage);
	// Local reflections share the lamp driver; sky and distant street stay still.
	float roof = soft_ellipse(UV, vec2(0.207, 0.371), vec2(0.140, 0.023));
	float windshield = soft_ellipse(UV, vec2(0.130, 0.449), vec2(0.136, 0.078));
	float shoulder = soft_ellipse(UV, vec2(0.239, 0.464), vec2(0.062, 0.092));
	float pavement = soft_ellipse(UV, vec2(0.300, 0.887), vec2(0.200, 0.078));
	float reflected = max(max(roof * 0.32, windshield * 0.15), max(shoulder * 0.10, pavement * 0.065));
	float lit_detail = smoothstep(0.025, 0.25, luminance);
	color *= 1.0 - outage * reflected * lit_detail;
	COLOR = vec4(color, painted.a) * item_tint;
}
