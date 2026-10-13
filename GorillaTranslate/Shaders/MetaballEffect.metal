#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Static one-pixel noise is only used by the opt-in Canvas renderer.
[[ stitchable ]]
half4 orbDither(float2 position, half4 color, float displayScale) {
    float2 pixel = floor(position * displayScale);
    float noise = fract(52.9829189f * fract(dot(pixel, float2(0.06711056f, 0.00583715f))));
    float delta = (noise - 0.5f) * (2.0f / 255.0f);
    float alpha = float(color.a);
    float3 rgb = clamp(float3(color.rgb) + delta * alpha, float3(0.0f), float3(alpha));
    return half4(half3(rgb), color.a);
}

/// 融球閾值 Shader：alpha > 0.5 → 保留像素（修正 premultiplied alpha），否則丟棄
/// 配合前置 .blur() 使用，模糊重疊區域自然融合成液態形態
[[ stitchable ]]
half4 alphaThreshold(float2 position, SwiftUI::Layer layer) {
    half4 color = layer.sample(position);
    half alpha = color.a;
    if (alpha > 0.5) {
        return half4(color.rgb / alpha, 1.0);
    } else {
        return half4(0, 0, 0, 0);
    }
}
