#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float threshold = 0.3;

static void addDrop(float2 p, float2 center, float radius, thread float &field, thread float2 &gradient) {
    float reach = radius * 1.75;
    float2 d = p - center;
    float u = dot(d, d) / (reach * reach);
    if (u >= 1.0) { return; }
    float k = 1.0 - u;
    field += k * k * k;
    gradient += -6.0 * k * k * d / (reach * reach);
}

static float shade(float2 p, float2 center, float radius) {
    float reach = radius * 1.75;
    float2 d = p - center;
    float k = max(0.0, 1.0 - dot(d, d) / (reach * reach));
    return k * k * k;
}

static float dots(float2 q, float density) {
    float2 cell = fract(q * density) - 0.5;
    return smoothstep(0.17, 0.05, length(cell));
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
    float scale = min(size.x, size.y);
    float2 p = (position - size * 0.5) / scale;
    float tall = size.y / scale;

    float field = 0.0;
    float shadow = 0.0;
    float2 gradient = float2(0.0);
    float2 offset = float2(0.012, 0.03);

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float depth = 0.35 + 0.65 * fract(fi * 0.618);
        float t = time * energy;
        float2 center = float2(
            0.36 * sin(t * (0.11 + 0.03 * fi) + fi * 2.1),
            0.44 * tall * sin(t * (0.07 + 0.02 * fi) + fi * 1.3)
        );
        center *= mix(1.0, 0.3, gather);
        center += tilt * 0.03 * depth;
        float radius = 0.1 + 0.045 * sin(fi * 3.7 + t * 0.23);
        radius *= 1.0 + 0.12 * gather * sin(time * 1.6 + fi * 1.1);
        addDrop(p, center, radius, field, gradient);
        shadow += shade(p - offset, center, radius);
    }

    if (touch.z > 0.001) {
        float2 center = (touch.xy - size * 0.5) / scale;
        addDrop(p, center, 0.12 * touch.z, field, gradient);
        shadow += shade(p - offset, center, 0.12 * touch.z);
    }

    float glass = smoothstep(threshold - 0.015, threshold + 0.015, field);
    float lift = sqrt(max(field - threshold, 0.0) + 0.012);
    float3 normal = normalize(float3(-gradient * 0.045 / lift, 1.0));

    float3 light = normalize(float3(-0.5, -0.7, 0.8));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(normal, halfway), 0.0), 90.0);
    float sheen = pow(max(dot(normal, halfway), 0.0), 8.0);
    float fresnel = pow(1.0 - normal.z, 2.5);

    float background = dark > 0.5 ? 0.0 : 1.0;
    float ink = 1.0 - background;
    float2 drift = tilt * 0.004;

    float outside = background + (ink - background) * dots(p + drift, 24.0) * 0.05;
    outside -= (1.0 - dark) * smoothstep(threshold * 0.4, threshold * 1.3, shadow) * 0.05;

    float2 bent = (p + drift) * 0.86 + normal.xy * 0.06;
    float body = background + (ink - background) * (dark > 0.5 ? 0.06 : 0.05);
    float inside = body + (ink - background) * dots(bent, 24.0) * 0.12;
    inside += (ink - background) * fresnel * 0.5;
    inside += spec * (dark > 0.5 ? 0.9 : 0.8) + sheen * 0.06;

    float value = clamp(mix(outside, inside, glass), 0.0, 1.0);
    return half4(half3(value), 1.0);
}
