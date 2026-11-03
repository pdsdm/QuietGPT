#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float threshold = 0.3;
constant float2 cellSize = float2(6.0, 10.0);

constant uchar glyphs[10][7] = {
    { 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0, 4 },
    { 0, 0, 4, 0, 0, 4, 0 },
    { 0, 0, 0, 14, 0, 0, 0 },
    { 0, 0, 31, 0, 31, 0, 0 },
    { 0, 4, 4, 31, 4, 4, 0 },
    { 0, 21, 14, 31, 14, 21, 0 },
    { 10, 31, 10, 10, 31, 10, 0 },
    { 25, 26, 2, 4, 8, 11, 19 },
    { 14, 17, 23, 21, 23, 16, 14 }
};

static void addDrop(float2 p, float2 center, float radius, thread float &field, thread float2 &gradient) {
    float reach = radius * 1.75;
    float2 d = p - center;
    float u = dot(d, d) / (reach * reach);
    if (u >= 1.0) { return; }
    float k = 1.0 - u;
    field += k * k * k;
    gradient += -6.0 * k * k * d / (reach * reach);
}

static float scene(float2 point, float2 cell, float2 size, float time, float2 tilt, float3 touch, float energy, float gather) {
    float scale = min(size.x, size.y);
    float2 p = (point - size * 0.5) / scale;
    float tall = size.y / scale;

    float field = 0.0;
    float2 gradient = float2(0.0);

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float depth = 0.3 + 0.7 * fract(fi * 0.618);
        float t = time * energy;
        float2 center = float2(
            0.36 * sin(t * (0.11 + 0.03 * fi) + fi * 2.1),
            0.44 * tall * sin(t * (0.07 + 0.02 * fi) + fi * 1.3)
        );
        center *= mix(1.0, 0.3, gather);
        center += tilt * (0.12 + 0.3 * depth);
        float radius = (0.1 + 0.045 * sin(fi * 3.7 + t * 0.23)) * (0.85 + 0.3 * depth);
        radius *= 1.0 + 0.12 * gather * sin(time * 1.6 + fi * 1.1);
        addDrop(p, center, radius, field, gradient);
    }

    if (touch.z > 0.001) {
        float2 center = (touch.xy - size * 0.5) / scale;
        addDrop(p, center, 0.13 * touch.z, field, gradient);
    }

    if (field < threshold) {
        float2 shifted = cell + floor(tilt * float2(9.0, 6.0));
        bool grid = fmod(abs(shifted.x), 3.0) < 0.5 && fmod(abs(shifted.y), 2.0) < 0.5;
        return grid ? 0.12 : 0.0;
    }

    float lift = sqrt(field - threshold + 0.012);
    float3 normal = normalize(float3(-gradient * 0.045 / lift, 1.0));
    float3 light = normalize(float3(-0.5 + tilt.x * 1.4, -0.7 + tilt.y * 1.4, 0.8));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float diffuse = max(dot(normal, light), 0.0);
    float spec = pow(max(dot(normal, halfway), 0.0), 40.0);
    float fresnel = pow(1.0 - normal.z, 2.0);
    return clamp(0.2 + 0.45 * diffuse + 0.3 * fresnel + 0.7 * spec, 0.0, 1.0);
}

[[ stitchable ]] half4 liquidGlass(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float2 tilt,
    float3 touch,
    float dark,
    float energy,
    float gather
) {
    float background = dark > 0.5 ? 0.0 : 1.0;
    float ink = 1.0 - background;

    float2 cell = floor(position / cellSize);
    float2 local = position - cell * cellSize;
    int column = int(floor(local.x - 0.5));
    int row = int(floor(local.y - 1.5));
    if (column < 0 || column > 4 || row < 0 || row > 6) {
        return half4(half3(background), 1.0);
    }

    float value = scene((cell + 0.5) * cellSize, cell, size, time, tilt, touch, energy, gather);
    int index = clamp(int(value * 9.99), 0, 9);
    bool lit = ((glyphs[index][row] >> (4 - column)) & 1) != 0;
    float alpha = lit ? 0.2 + 0.6 * value : 0.0;
    return half4(half3(mix(background, ink, alpha)), 1.0);
}
