// ============================================================================
// character_leg.gdshader —— 玩家角色腿部变形着色器（GPU 蒙皮，通用版）
// ----------------------------------------------------------------------------
// 供 character_locomotion.gd 使用，6 个角色（司机/医生/警察/军人/维修工/程序员）共用。
//
// 【它做什么】
// 把腿部贴图切成网格后，按「髋→膝→踝」三个支点做旋转，让腿能弯曲摆动。
// 纯顶点着色器运算，逐帧只改 uniform（几个角度数字），不重建网格。
//
// 【关键参数】
//   source_origin —— 腿部贴图在源图中的左上角原点
//   rest_hip/knee/ankle —— 静止姿势下的髋/膝/踝位置（基准姿态）
//   posed_hip/knee/ankle —— 当前帧摆动后的位置（由 CPU 每帧算出传入）
//   cut_y        —— 腿部裁切线 y 坐标（此线以上属躯干，不参与腿变形）
//   rotations    —— 四个旋转角（髋部、大腿、小腿等，逐层累加）
//   body_bob     —— 身体上下起伏量（走路时身体轻微上下）
//
// 【辅助函数】
//   rotate_offset() —— 二维向量旋转，配 cos/sin 复用，省去每次重算三角函数
// ============================================================================
shader_type canvas_item;
uniform vec2 source_origin;
uniform vec2 rest_hip;
uniform vec2 rest_knee;
uniform vec2 rest_ankle;
uniform float cut_y;
uniform vec2 posed_hip;
uniform vec2 posed_knee;
uniform vec2 posed_ankle;
uniform vec4 rotations;
uniform float body_bob;
vec2 rotate_offset(vec2 p, vec2 cs) {
	return vec2(p.x*cs.x-p.y*cs.y,p.x*cs.y+p.y*cs.x);
}
void vertex() {
	vec2 p = VERTEX + source_origin;
	vec2 thigh = posed_hip + rotate_offset(p-rest_hip,rotations.xy);
	vec2 shin = posed_knee + rotate_offset(p-rest_knee,rotations.zw);
	vec2 boot = posed_ankle + p-rest_ankle;
	vec2 body = p+vec2(0.0,body_bob);
	vec2 result = mix(body,thigh,smoothstep(cut_y,rest_hip.y+65.0,p.y));
	result = mix(result,shin,smoothstep(rest_knee.y-55.0,rest_knee.y+55.0,p.y));
	result = mix(result,boot,smoothstep(rest_ankle.y-45.0,rest_ankle.y+18.0,p.y));
	VERTEX = result-source_origin;
}

