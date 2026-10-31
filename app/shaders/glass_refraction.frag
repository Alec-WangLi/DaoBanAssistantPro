#version 460 core

// 玻璃容器边缘的逐像素折射。
//
// 输入是「已经模糊过的背景」（由 BackdropFilter 的 filter 链在上游提供），
// 这一层只做位移，不做模糊，也不做染色 —— 染色仍在 Dart 侧用渐变叠。
//
// ## 坐标：为什么容器尺寸要单独传一份
//
// `FlutterFragCoord()` 给的是**输入纹理**内的坐标（单位设备像素），而这条链的
// 输入是上游那层高斯模糊的输出 —— 模糊会把自己的 coverage 按 `ceil(√3·σ)` 对称
// 外扩（Impeller `sigma.h` 的 `kKernelRadiusPerSigma`），σ=24 时每边多出约 42dp。
// 所以：
//
// * `uSize` 是**纹理**尺寸 —— 而且它不是我们灌的：`ImageFilter.shader` 的文档
//   明写「The first uniform value must be a vec2, this will be set by the engine
//   to the size of the bound texture」，引擎在 `RuntimeEffectFilterContents`
//   里用输入快照的纹理尺寸覆写 floats 0/1。Dart 侧再 setFloat(0/1, …) 是空操作。
// * `uContainer` 才是容器自己的宽高（floats 8/9，引擎不碰）。
//
// 两者之差就是模糊外扩出来的 padding，除以 2 即每边。几何（SDF / 法线 / 位移）
// 在**容器空间**里算，采样留在**纹理空间**里 —— 混用会让折射带整条落在容器外面，
// 于是容器内每一个像素都走 early return、看起来跟没挂一样（这正是 v0.12.8 第一版
// 的 bug：`uSize` 当容器用，`uBand` 20dp 对 42dp 的外扩，全军覆没）。
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 输入纹理尺寸（设备像素，**由引擎覆写**，见上）
uniform vec2 uOrigin;    // 图层原点到容器左上角的偏移（设备像素）
uniform float uRadius;   // 容器圆角半径（设备像素）
uniform float uBand;     // 折射带宽度（设备像素）：只有这一圈会弯
uniform float uBend;     // 折射带外缘的最大位移（设备像素）
uniform float uSpread;   // 三波长色散比例，0 = 无色散
// 容器自己的宽高（设备像素）。放在 uSpread 之后 = floats 8/9 —— 引擎只覆写
// floats 0/1（那个 vec2），所以这一份是我们真正说了算的。
uniform vec2 uContainer;
uniform sampler2D uTex;  // 上游模糊过的背景

out vec4 fragColor;

// 圆角矩形的有符号距离：内部为负。
// 没有用「梯度解析式 + 放大半径」那一套，法线在下面用四点差分拿。
float boxField(vec2 p, vec2 halfSize, float rad) {
    vec2 q = abs(p) - halfSize + vec2(rad);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
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
// 漏了这三行不会崩、也不会报错，只是**整块玻璃的折射上下镜像** —— Vulkan 机型上
// 完全看不出来，只有 GLES 机型（无 Vulkan 的老机 / 驱动黑名单机）才会。
vec2 toUv(vec2 p) {
    vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return uv;
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
    // 厚度剖面用三次 Hermite（边缘最厚、内缘归零），代替圆弧那套几何。
    float depth = -field / uBand;
    float rise = 1.0 - depth;
    float bulk = rise * rise * (3.0 - 2.0 * rise);

    // 法线：四点中心差分。step 取 1 像素足够，画面里没有比它更细的结构。
    const float E = 1.0;
    vec2 slope = vec2(
        boxField(rel + vec2(E, 0.0), halfSize, uRadius) -
            boxField(rel - vec2(E, 0.0), halfSize, uRadius),
        boxField(rel + vec2(0.0, E), halfSize, uRadius) -
            boxField(rel - vec2(0.0, E), halfSize, uRadius));
    vec2 dir = normalize(slope + vec2(1.0e-6, 1.0e-6));

    vec2 bend = dir * (bulk * uBend);

    // 三波长各走各的：红偏得最多、蓝偏得最少。一个像素只多采两次。
    // 采样点在**纹理空间**里加位移（fragPx，不是容器空间的 px）—— 位移本身是
    // 设备像素量，两个空间只差一个平移，加到哪个上都对，但加到 fragPx 上少一次
    // pad 回加，读起来也不容易错。
    float r = texture(uTex, toUv(fragPx + bend * (1.0 + uSpread))).r;
    float g = texture(uTex, toUv(fragPx + bend)).g;
    float b = texture(uTex, toUv(fragPx + bend * (1.0 - uSpread))).b;

    fragColor = vec4(r, g, b, straight.a);
}
