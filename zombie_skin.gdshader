// ============================================================================
// zombie_skin.gdshader —— 丧尸蒙皮变形着色器（GPU 顶点动画的核心）
// ----------------------------------------------------------------------------
// 英文注释机翻：「UV 最初携带预计算的肢体权重；在光栅化前恢复源图 UV。」
//
// 【它做什么】
// 丧尸的立绘是一张静态 PNG，这个着色器负责让它的肢体「动起来」：
// 顶点着色阶段按髋/膝/踝的当前姿态做旋转+位移，把网格顶点摆到新位置。
//
// 【关键技巧：权重预烘焙进 UV】
// Godot 的 canvas_item 着色器拿不到自定义顶点属性，巧妙做法是——
// 把每个顶点的「肢体权重」预先算好塞进 UV 坐标里传进来，
// 光栅化（fragment）之前再用 texture_size 还原成真正的源图 UV 去采样贴图。
// 这样既绕开了引擎限制，又实现了 GPU 蒙皮。
//
// 【主要参数】
//   texture_size —— 源图尺寸，用于把归一化坐标还原成像素/贴图 UV
//   pelvis/neck  —— 骨盆与脖子的位置（躯干旋转的支点）
//   body_angle / body_shift —— 躯干整体倾斜角与位移
//   head_angle   —— 头部单独摆动角
//   near/far_shoulder / elbow —— 四肢肩/肘锚点（近侧=靠镜头，远侧=靠后）
//   arm_angles   —— 四肢上下臂各自旋转角（vec4：近大臂/近小臂/远大臂/远小臂）
//   hip0...      —— 双腿髋部锚点
// ============================================================================
shader_type canvas_item;
// UV initially carries precomputed limb weights; source UV is restored before rasterization.
uniform vec2 texture_size;
uniform vec2 pelvis;
uniform vec2 neck;
uniform float body_angle;
uniform vec2 body_shift;
uniform float head_angle;
uniform vec2 near_shoulder;
uniform vec2 near_elbow;
uniform vec2 far_shoulder;
uniform vec2 far_elbow;
uniform vec4 arm_angles; // near upper/lower, far upper/lower
uniform vec2 hip0;
uniform vec2 knee0;
uniform vec2 ankle0;
uniform vec2 hip1;
uniform vec2 knee1;
uniform vec2 ankle1;
uniform vec2 posed_hip0;
uniform vec2 posed_knee0;
uniform vec2 posed_ankle0;
uniform vec2 posed_hip1;
uniform vec2 posed_knee1;
uniform vec2 posed_ankle1;
uniform vec4 leg_angles;
uniform float leg_blend;
vec2 rot(vec2 p,float a) {float c=cos(a);float s=sin(a);return vec2(p.x*c-p.y*s,p.x*s+p.y*c);}
vec2 body(vec2 p) {return pelvis+rot(p-pelvis,body_angle)+body_shift;}
vec2 arm(vec2 p,vec2 shoulder,vec2 elbow,vec2 angles) {
	vec2 upper=shoulder+rot(p-shoulder,angles.x);
	vec2 moved_elbow=shoulder+rot(elbow-shoulder,angles.x);
	vec2 lower=moved_elbow+rot(p-elbow,angles.y);
	vec2 axis=normalize(elbow-shoulder);
	float progress=dot(p-elbow,axis);
	return mix(upper,lower,smoothstep(-30.0,35.0,progress));
}
vec2 leg(vec2 p,vec2 h,vec2 k,vec2 a,vec2 ph,vec2 pk,vec2 pa,vec2 angles) {
	vec2 upper=ph+rot(p-h,angles.x);
	vec2 lower=pk+rot(p-k,angles.y);
	vec2 foot=pa+p-a;
	vec2 result=mix(upper,lower,smoothstep(k.y-40.0,k.y+40.0,p.y));
	return mix(result,foot,smoothstep(a.y-32.0,a.y+18.0,p.y));
}
void vertex() {
	vec2 weights=UV;
	vec2 p=VERTEX;
	UV=p/texture_size;
	vec2 upper=p;
	if(abs(weights.x)>.001) {
		vec2 posed=weights.x>0.0 ? arm(p,near_shoulder,near_elbow,arm_angles.xy) : arm(p,far_shoulder,far_elbow,arm_angles.zw);
		upper=mix(upper,posed,abs(weights.x));
	}
	float head_weight=(1.0-smoothstep(neck.y-50.0,neck.y+25.0,p.y))*(1.0-abs(weights.x));
	upper=mix(upper,neck+rot(upper-neck,head_angle),head_weight);
	vec2 result=body(upper);
	if(abs(weights.y)>.001) {
		vec2 posed=weights.y<0.0 ? leg(p,hip0,knee0,ankle0,posed_hip0,posed_knee0,posed_ankle0,leg_angles.xy) : leg(p,hip1,knee1,ankle1,posed_hip1,posed_knee1,posed_ankle1,leg_angles.zw);
		result=mix(result,posed,abs(weights.y)*leg_blend);
	}
	VERTEX=result;
}
