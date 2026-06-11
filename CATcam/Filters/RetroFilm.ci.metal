#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// レトロ・フィルム風(退色プリント/写ルンです調)フィルタ。
// 黒を温かいグレーへ持ち上げ、全体にアンバーのキャストを乗せ、
// ハイライトを柔らかくロールオフしてクリーム色に寄せる。彩度はやや低め。
extern "C" float4 retroFilm(coreimage::sample_t s, float intensity)
{
    float3 x = clamp(s.rgb, 0.0, 1.0);

    float luma = dot(x, float3(0.2126, 0.7152, 0.0722));

    // --- 黒の持ち上げ(lifted blacks)---
    // 出力レンジを [lift, 1] に圧縮し、純黒を暗い温かいグレーにする。
    // R を最も持ち上げ、B は控えめにしてシャドウをアンバー寄りに。
    float3 lift = float3(0.055, 0.045, 0.030);
    float3 graded = lift + x * (1.0 - lift);

    // --- コントラストを軽く下げる(中間トーンを平坦化)---
    // 0.5 を軸にゲインを 0.88 まで落として、なだらかな印象に。
    graded = (graded - 0.5) * 0.88 + 0.5;

    // --- ハイライトの柔らかいロールオフ ---
    // 明部ほど 1.0 へ漸近させ、白飛びを抑えてクリーム色に。
    float3 rolled = 1.0 - (1.0 - graded) * (1.0 - graded);
    float hi = smoothstep(0.55, 1.0, luma);
    graded = mix(graded, rolled, hi * 0.5);

    // --- 退色のスプリットトーン ---
    // シャドウにわずかに緑〜オリーブ、ハイライトに黄を入れる。
    float shadow = 1.0 - smoothstep(0.0, 0.5, luma);
    graded += float3(-0.010, 0.012, -0.014) * shadow;   // シャドウ: 緑/オリーブ寄り
    graded += float3(0.030, 0.018, -0.030) * hi;          // ハイライト: 黄/アンバー

    // --- 全体の温かいアンバーキャスト ---
    graded += float3(0.022, 0.010, -0.018);

    // --- 彩度をやや落とす(色あせ)---
    float3 gray = float3(dot(graded, float3(0.2126, 0.7152, 0.0722)));
    graded = mix(gray, graded, 0.82);

    float3 result = mix(x, clamp(graded, 0.0, 1.0), intensity);
    return float4(result, s.a);
}
