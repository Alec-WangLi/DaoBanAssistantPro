#version 460 core

// 玻璃容器边缘的逐像素折射（第二版）。
//
// 输入是「已经模糊过的背景」（由 BackdropFilter 的 filter 链在上游提供），这一层
// 只做位移 + 一圈菲涅尔亮边，不做模糊、不做染色 —— 染色仍在 Dart 侧用渐变叠。
//
// 推导与验收见 `docs/liquid-glass-edge-spec.md`。一句话版本：
//
// * 剖面按**斯涅尔定律**推（四分之一圆环面 + 逐通道折射率），位移压在贴边一圈；
// * 法线用圆角矩形 SDF 的**解析梯度**（圆角区径向、直边区轴向），不再四点差分；
// * 色散是**柯西色散**算出来的：三个通道用三个折射率各算一次剖面，仍然只采三次；
// * 贴边那道亮线是 **Schlick 菲涅尔**（掠射角反射率趋近 1），不是叠的装饰色。
//
// ## 坐标：为什么容器尺寸要单独传一份
//
// `FlutterFragCoord()` 给的是**输入纹理**内的坐标（单位设备像素），而这条链的
// 输入是上游那层高斯模糊的输出 —— 模糊会把自己的 coverage 按 `ceil(√3·σ)` 对称
// 外扩（Impeller `sigma.h` 的 `kKernelRadiusPerSigma`）。所以：
//
// * `uSize` 是**纹理**尺寸 —— 而且它不是我们灌的：`ImageFilter.shader` 的文档
//   明写「The first uniform value must be a vec2, this will be set by the engine
//   to the size of the bound texture」，引擎在 `RuntimeEffectFilterContents`
//   里用输入快照的纹理尺寸覆写 floats 0/1。Dart 侧再 setFloat(0/1, …) 是空操作。
// * `uContainer` 才是容器自己的宽高（floats 8/9，引擎不碰）。
//
// 两者之差就是模糊外扩出来的 padding，除以 2 即每边。几何（SDF / 法线 / 位移）
// 在**容器空间**里算，采样留在**纹理空间**里 —— 混用会让折射带整条落在容器外面，
// 于是容器内每一个像素都走 early return、看起来跟没挂一样（v0.12.8 第一版的 bug）。
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // 输入纹理尺寸（设备像素，**由引擎覆写**，见上）
uniform vec2 uOrigin;      // 图层原点到容器左上角的偏移（设备像素）
uniform float uRadius;     // 容器圆角半径（设备像素）
uniform float uBand;       // 折射带宽度（设备像素）：只有这一圈会弯
uniform float uBend;       // 折射带外缘的最大位移（设备像素）
uniform float uThickness;  // 玻璃厚度感：把法线往中心拽，直边中段也会偏折
// 容器自己的宽高（设备像素）。放在 uThickness 之后 = floats 8/9 —— 引擎只覆写
// floats 0/1（那个 vec2），所以这一份是我们真正说了算的。
uniform vec2 uContainer;
uniform vec2 uLight;       // 光来向（单位向量，屏幕坐标：x 右、y 下）
uniform float uRim;        // 菲涅尔亮边强度
uniform float uDispersion; // 色散的通道分离比例（见 edgeProfile 调用处）
uniform float uIor;        // 绿通道的折射率（位移剖面的形状由它定）
uniform sampler2D uTex;    // 上游模糊过的背景

out vec4 fragColor;

const float kHalfPi = 1.5707963267948966;
const float kFresnel0 = 0.04; // 空气→玻璃的垂直入射反射率

// 圆角矩形的有符号距离：内部为负。
float boxField(vec2 p, vec2 halfSize, float rad) {
    vec2 q = abs(p) - halfSize + vec2(rad);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

// 圆角矩形 SDF 的解析梯度（指向外）。圆角区沿径向、直边区沿轴向 —— 与四点差分
// 同解，但便宜且不会在 corner 里抖。
vec2 boxGradient(vec2 p, vec2 halfSize, float rad) {
    vec2 q = abs(p) - halfSize + vec2(rad);
    if (q.x > 0.0 && q.y > 0.0) {
        return normalize(sign(p) * q);
    }
    return (q.x > q.y) ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}

// 「引擎坐标 → 纹理 uv」。
//
// ⚠️ **Impeller 走 OpenGL(ES) 后端时 y 轴是反的**，这是 dart:ui 里
// `ImageFilter.shader` 的文档原文：「When Impeller uses the OpenGL(ES) backend,
// the y-axis direction is reversed. Custom fragment shaders must invert the y-axis
// on GLES or they will render upside-down.」
//
// 分界点选在**最后一次换算**上：SDF、法线、位移全在引擎那套坐标里算（胶囊上下
// 对称，`boxField` 对 rel.y 取绝对值，算出来的深度与法线方向与翻不翻无关），只在
// 「位置 → 采样点」这一步翻回来，于是采样落点与屏幕上看到的像素一一对应。
vec2 toUv(vec2 p) {
    vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

// 侧向位移的剖面，按斯涅尔定律从「四分之一圆环面」推出来。
//
// u = 1 在容器外缘（玻璃面与视线几乎平行）、u = 0 在折射带内缘（面正对视线）。
// 球冠几何给出 sin(入射角) = u；折射角由 sin(θr) = u / n 得到；侧向位移与
// tan(θi - θr) 成正比，再除以 u = 1 处的值归一化到 1。
//
// 形状上它在贴边极陡（u = 1 处为 1、半带处只有 0.165），所以位移集中在最外那
// 一圈 —— 这正是「边缘被切出一道光弧」与「一大片缓涂抹」的分别。
float edgeProfile(float u, float n) {
    float su = clamp(u, 0.0, 1.0);
    float ti = asin(su);
    float tr = asin(clamp(su / n, 0.0, 1.0));
    float norm = tan(kHalfPi - asin(1.0 / n));
    return tan(ti - tr) / norm;
}

void main() {
    // 纹理空间里的位置（引擎坐标减去调用点给的校正量）。
    vec2 fragPx = FlutterFragCoord().xy - uOrigin;
    vec4 straight = texture(uTex, toUv(fragPx));

    // 模糊外扩是对称的，所以每边的 padding 就是两个尺寸之差的一半。
    // 没有外扩（比如将来把链序翻过来）时它是 0，行为与「uSize 就是容器」一致。
    vec2 pad = max((uSize - uContainer) * 0.5, vec2(0.0));

    // 几何一律在容器空间里算。容器退化（Dart 侧没灌上）时原样还回去。
    if (uContainer.x <= 0.0 || uContainer.y <= 0.0) {
        fragColor = straight;
        return;
    }
    vec2 px = fragPx - pad;

    vec2 halfSize = uContainer * 0.5;
    vec2 rel = px - halfSize;

    float field = boxField(rel, halfSize, uRadius);

    // 容器外、以及离边太远的地方一律原样还回去 —— 这是整条管线里最省的一笔：
    // 一个底栏只有边缘那一圈真的走下面的采样。
    if (field >= 0.0 || -field >= uBand) {
        fragColor = straight;
        return;
    }

    // 归一化的「侵入深度」：0 在容器边界上，1 在折射带的内缘。
    float depth = -field / uBand;
    float u = 1.0 - depth;

    // 法线：解析梯度，再按「玻璃有厚度」往中心拽一点。
    vec2 outward = boxGradient(rel, halfSize, uRadius);
    vec2 inward = normalize(rel + vec2(1.0e-6, 1.0e-6));
    vec2 dir = normalize(outward + uThickness * inward);

    // 位移剖面（绿通道定形状），三个波长再按柯西色散的方向分开：折射率随波长
    // 变短而变大，所以红折得比绿少、蓝比绿多。
    //
    // 幅度是夸张过的、方向不是：真实冕牌玻璃在这个尺度上（10dp 位移、20dp 带）
    // 三色的差只有亚像素，照物理值做出来等于没有（第一版就是这么死的）。
    // 所以比例按色散方向定、幅度按「看得见」定 —— uDispersion 是这个幅度。
    float pg = edgeProfile(u, uIor);
    vec2 bendG = dir * (pg * uBend);
    vec2 bendR = bendG * (1.0 - uDispersion);
    vec2 bendB = bendG * (1.0 + uDispersion);

    // 采样点在**纹理空间**里加位移（fragPx，不是容器空间的 px）—— 位移本身是
    // 设备像素量，两个空间只差一个平移，加到哪个上都对。
    vec3 col = vec3(
        texture(uTex, toUv(fragPx + bendR)).r,
        texture(uTex, toUv(fragPx + bendG)).g,
        texture(uTex, toUv(fragPx + bendB)).b);

    // Schlick 菲涅尔：掠射角处反射率趋近 1，所以贴边那道亮线是物理必然。
    // cos(入射角) 由球冠几何给出：sqrt(1 - u²)。
    float cosI = sqrt(max(0.0, 1.0 - u * u));
    float fresnel = kFresnel0 + (1.0 - kFresnel0) * pow(1.0 - cosI, 5.0);
    float face = 0.5 + 0.5 * dot(dir, uLight);
    col += vec3(fresnel * face * uRim);

    fragColor = vec4(col, straight.a);
}
