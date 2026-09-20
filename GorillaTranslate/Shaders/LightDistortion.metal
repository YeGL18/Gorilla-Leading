#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// 液態玻璃光學扭曲 Shader
/// 純視覺效果，唔影響佈局位置
///
/// progress: 0.0 = 無效果, 1.0 = 最大扭曲
/// focalPoint: 扭曲中心點（歸一化座標 0-1）
/// radius: 扭曲影響範圍（歸一化）
[[ stitchable ]]
half4 lightDistortion(float2 position, SwiftUI::Layer layer, float progress, float2 focalPoint, float radius) {
    // 用 position 作為基礎計算（position 係像素座標）
    // 假設螢幕大約 400x900 points，用固定值做歸一化
    float2 uv = position / float2(400, 900);

    // 到焦點嘅距離
    float2 toFocal = uv - focalPoint;
    toFocal.x *= 400.0 / 900.0;  // 修正縱橫比
    float dist = length(toFocal);

    // 影響範圍：越近焦點效果越強
    float influence = smoothstep(radius, 0.0, dist);

    // 光學扭曲強度（最大 20 像素偏移）
    float strength = progress * 20.0 * influence;

    // 扭曲方向：向焦點方向折射（液態玻璃效果）
    float2 dir = normalize(toFocal + 0.0001);
    float2 offset = -dir * strength;

    // 加入微妙嘅波動（液態感）
    float wave = sin(uv.y * 40.0 + progress * 5.0) * cos(uv.x * 35.0 + progress * 4.0);
    offset += float2(wave * 2.0, wave * 1.5) * progress * influence;

    // 採樣扭曲後嘅像素
    float2 distortedPos = position + offset;
    distortedPos = clamp(distortedPos, float2(0), float2(400, 900));

    return layer.sample(distortedPos);
}
