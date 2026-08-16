#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

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
