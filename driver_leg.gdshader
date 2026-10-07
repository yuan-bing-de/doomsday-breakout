// ============================================================================
// driver_leg.gdshader —— 司机双腿变形着色器（GPU 蒙皮，专属版）
// ----------------------------------------------------------------------------
// 供 driver_locomotion.gd 使用。与 character_leg.gdshader 算法同源，
// 区别是司机用「两条独立贴图腿」各自摆动，而不是共用一张腿部图，
// 因此每条腿单独传一组锚点与旋转角，摆动更自由、层次感更好。
//
// 【与通用版的区别】
//   通用版（character_leg）：一张腿图，参数靠 cut_y 区分前后
//   本版（driver_leg）    ：左右腿各一张贴图，各自独立旋转，避免左右腿同相位
//
// 【关键参数】
//   source_origin —— 该腿贴图在源图中的原点
//   rest_hip/knee/ankle —— 静止姿势下三支点（基准）
//   posed_hip/knee/ankle —— 当前帧位置（CPU 每帧算好传入）
//   cut_y        —— 腿/躯干分界线
//   rotations    —— 该腿各关节旋转角
//   body_bob     —— 身体起伏量（两条腿共用，保持身体整体一致）
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

