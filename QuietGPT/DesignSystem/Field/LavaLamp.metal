#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float threshold = 0.32;
constant float2 cellSize = float2(4.8, 8.0);

static float surface(float2 p, device const float *beads, int count, float time, thread float2 &slope, thread float &height) {
    float2 warp = float2(
        sin(p.y * 9.0 + time * 0.23) + 0.5 * sin(p.y * 17.0 - p.x * 7.0 - time * 0.31),
        sin(p.x * 11.0 - time * 0.19) + 0.5 * sin(p.x * 19.0 + p.y * 6.0 + time * 0.27)
    ) * 0.012;
    float2 q = p + warp;
    float field = 0.0;
    height = 0.0;
    slope = float2(0.0);
    for (int i = 0; i + 5 < count; i += 6) {
        float2 d = q - float2(beads[i], beads[i + 1]);
        float2 velocity = float2(beads[i + 3], beads[i + 4]);
        float speed = length(velocity);
        float stretch = 1.0 + min(0.9, speed * 4.0);
        float2 along = speed > 1e-4 ? velocity / speed : float2(0.0, 1.0);
        float2 across = float2(-along.y, along.x);
        float thin = sqrt(stretch);
        float a = dot(d, along) / stretch;
        float b = dot(d, across) * thin;
        float reach = beads[i + 2] * 1.8;
        float u = (a * a + b * b) / (reach * reach);
        if (u < 1.0) {
            float k = 1.0 - u;
            float k3 = k * k * k;
            float lobe = 0.55 + 0.45 * beads[i + 5];
            field += k3;
            height += lobe * k3 * k3;
            float2 change = 2.0 * (along * a / stretch + across * b * thin) / (reach * reach);
            slope -= change * lobe * 6.0 * k3 * k * k;
        }
    }
    return field;
}

static float shade(float2 cell, float2 point, float scale, device const float *beads, int count, float2 down, float time) {
    float2 slope;
    float height;
    float field = surface(point / scale, beads, count, time, slope, height);
    if (field < threshold) {
        bool grid = fmod(cell.x, 4.0) < 0.5 && fmod(cell.y, 3.0) < 0.5;
        return grid ? 0.1 : 0.0;
    }
    float3 normal = normalize(float3(-slope * 0.022, 1.0));
    float3 light = normalize(float3(-0.45 - down.x * 0.5, -down.y * 0.55 - 0.25, 0.7));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float diffuse = max(dot(normal, light), 0.0);
    float gloss = pow(max(dot(normal, halfway), 0.0), 14.0);
    float crease = smoothstep(0.08, 0.75, height);
    return clamp(0.12 + crease * (0.18 + 0.42 * diffuse) + 0.4 * gloss * crease, 0.0, 1.0);
}

[[ stitchable ]] half4 lavaLamp(
    float2 position,
    half4 color,
    float2 origin,
    float scale,
    float time,
    device const float *beads,
    int count,
    float2 down,
    float dark,
    texture2d<half> atlas,
    float glyphs
) {
    float background = dark > 0.5 ? 0.0 : 1.0;
    float ink = 1.0 - background;

    float2 cell = floor(position / cellSize);
    float2 local = (position - cell * cellSize) / cellSize;
    float value = shade(cell, (cell + 0.5) * cellSize + origin, scale, beads, count, down, time);
    int index = clamp(int(value * (glyphs - 0.01)), 0, int(glyphs) - 1);
    if (index == 0) {
        return half4(half3(background), 1.0);
    }
    constexpr sampler linear(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = float2((float(index) + local.x) / glyphs, local.y);
    float coverage = float(atlas.sample(linear, uv).a);
    float alpha = coverage * (0.12 + 0.32 * value);
    return half4(half3(mix(background, ink, alpha)), 1.0);
}
