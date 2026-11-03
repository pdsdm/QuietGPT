#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float threshold = 0.32;
constant float2 cellSize = float2(4.8, 8.0);

static float wax(float2 p, device const float *blobs, int count, float2 down, float time, thread float &heat) {
    float field = 0.0;
    float warm = 0.0;
    for (int i = 0; i + 5 < count; i += 6) {
        float2 center = float2(blobs[i], blobs[i + 1]);
        float radius = blobs[i + 2];
        float2 velocity = float2(blobs[i + 3], blobs[i + 4]);
        float2 d = p - center;
        float speed = length(velocity);
        float stretch = 1.0 + min(0.9, speed * 4.0);
        float2 along = speed > 1e-4 ? velocity / speed : float2(0.0, 1.0);
        float2 across = float2(-along.y, along.x);
        float wobble = 1.0 + 0.08 * sin(atan2(d.y, d.x) * 3.0 + time * 0.9 + float(i));
        float a = dot(d, along) / stretch;
        float b = dot(d, across) * sqrt(stretch);
        float reach = radius * 1.8 * wobble;
        float u = (a * a + b * b) / (reach * reach);
        if (u < 1.0) {
            float k = 1.0 - u;
            float contribution = k * k * k;
            field += contribution;
            warm += contribution * blobs[i + 5];
        }
    }

    heat = field > 1e-4 ? clamp(warm / field, 0.0, 1.0) : 0.0;
    return field;
}

static float shade(float2 cell, float2 point, float scale, device const float *blobs, int count, float2 down, float time) {
    float2 p = point / scale;
    float heat;
    float field = wax(p, blobs, count, down, time, heat);
    if (field < threshold) {
        bool grid = fmod(cell.x, 4.0) < 0.5 && fmod(cell.y, 3.0) < 0.5;
        return grid ? 0.1 : 0.0;
    }
    float e = 0.004;
    float unused;
    float2 gradient = float2(
        wax(p + float2(e, 0.0), blobs, count, down, time, unused) - wax(p - float2(e, 0.0), blobs, count, down, time, unused),
        wax(p + float2(0.0, e), blobs, count, down, time, unused) - wax(p - float2(0.0, e), blobs, count, down, time, unused)
    ) / (2.0 * e);
    float lift = sqrt(field - threshold + 0.015);
    float3 normal = normalize(float3(-gradient * 0.035 / lift, 1.0));
    float3 light = normalize(float3(-0.35 - down.x * 0.6, -down.y * 0.6 - 0.2, 0.75));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float diffuse = max(dot(normal, light), 0.0);
    float spec = pow(max(dot(normal, halfway), 0.0), 36.0);
    float rim = pow(1.0 - normal.z, 2.0);
    return clamp(0.16 + 0.4 * diffuse + 0.28 * rim + 0.6 * spec + 0.12 * heat, 0.0, 1.0);
}

[[ stitchable ]] half4 lavaLamp(
    float2 position,
    half4 color,
    float2 origin,
    float scale,
    float time,
    device const float *blobs,
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
    float value = shade(cell, (cell + 0.5) * cellSize + origin, scale, blobs, count, down, time);
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
