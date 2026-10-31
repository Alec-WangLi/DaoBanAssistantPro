#version 460 core

// 玻璃容器边缘的逐像素折射。
//
// 输入是「已经模糊过的背景」（由 BackdropFilter 的 filter 链在上游提供），
// 这一层只做位移，不做模糊，也不做染色 —— 染色仍在 Dart 侧用渐变叠。
//
// 坐标：FlutterFragCoord() 给的是图层内坐标，单位是设备像素；[uOrigin] 用来
// 把那套坐标搬到「容器左上角为原点」，于是容器内部就是 [0,uSize]。
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 容器宽高（设备像素）
uniform vec2 uOrigin;    // 图层原点到容器左上角的偏移（设备像素）
uniform float uRadius;   // 容器圆角半径（设备像素）
uniform float uBand;     // 折射带宽度（设备像素）：只有这一圈会弯
uniform float uBend;     // 折射带外缘的最大位移（设备像素）
uniform float uSpread;   // 三波长色散比例，0 = 无色散
uniform sampler2D uTex;  // 上游模糊过的背景

out vec4 fragColor;

// 圆角矩形的有符号距离：内部为负。
// 没有用「梯度解析式 + 放大半径」那一套，法线在下面用四点差分拿。
float boxField(vec2 p, vec2 halfSize, float rad) {
    vec2 q = abs(p) - halfSize + vec2(rad);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

void main() {
    vec2 px = FlutterFragCoord().xy - uOrigin;
    vec2 uv = px / uSize;
    vec4 straight = texture(uTex, uv);

    vec2 halfSize = uSize * 0.5;
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
    float r = texture(uTex, (px + bend * (1.0 + uSpread)) / uSize).r;
    float g = texture(uTex, (px + bend) / uSize).g;
    float b = texture(uTex, (px + bend * (1.0 - uSpread)) / uSize).b;

    fragColor = vec4(r, g, b, straight.a);
}
