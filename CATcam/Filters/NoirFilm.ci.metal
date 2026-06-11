#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// 黒が引き立つフィルム調フィルタ。
// シャドウを深く沈めつつ、暗部の彩度を落として冷たいトーンに寄せる。
extern "C" float4 noirFilm(coreimage::sample_t s, float intensity)
{
    float3 x = clamp(s.rgb, 0.0, 1.0);

    // ゆるい S 字カーブでコントラストを上げる
    float3 curved = x * x * (3.0 - 2.0 * x);
    float3 graded = mix(x, curved, 0.85);

    // 暗部を滑らかに沈める(黒つぶれの一歩手前で止める)
    float luma  = dot(graded, float3(0.2126, 0.7152, 0.0722));
    float crush = smoothstep(0.0, 0.38, luma);
    graded *= mix(0.55, 1.0, crush);

    // 暗部ほど彩度を落とし、わずかに青へ転がす
    float3 gray = float3(dot(graded, float3(0.2126, 0.7152, 0.0722)));
    graded = mix(gray, graded, mix(0.7, 1.0, crush));
    graded += float3(-0.012, 0.0, 0.018) * (1.0 - crush);

    // ハイライトはわずかに温かく残してフィルムらしさを出す
    float highlight = smoothstep(0.7, 1.0, luma);
    graded += float3(0.015, 0.006, -0.008) * highlight;

    float3 result = mix(x, clamp(graded, 0.0, 1.0), intensity);
    return float4(result, s.a);
}
