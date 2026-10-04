#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// フィルムシミュレーション本体。
// プリセットごとのパラメータを受け取り、1パスで階調・彩度・スプリットトーンを作る。
// 最後に intensity で元画像とブレンドするので、白黒プリセットでも「効果の強さ」が効く。
//
//  contrast     : 正=S字でコントラストを上げる / 負=中間へ寄せてフラットにする (-1..1)
//  lift         : シャドウの持ち上げ量。ネガ調の眠い黒を作る (0..0.1 程度)
//  rolloff      : ハイライトを寝かせる量。飛びにくい映画調に (0..0.15 程度)
//  saturation   : 1=そのまま, 0=無彩色, >1=高彩度
//  monoAmount   : 1 で完全白黒。monoWeights がカラーフィルタ相当の重み
//  tint         : 白黒化した後に掛ける色(セピア用)。カラー時は (1,1,1)
//  shadowTint   : 暗部に足す色。負値も可
//  highlightTint: 明部に足す色
//  hueTint      : 特定の色相にだけ足す色(青空だけマゼンタに寄せる、など)
//  hueCenter    : 効かせたい色相。0..1 に正規化(青空 ≒ 0.60)
//  hueWidth     : 色相の効き幅。0 で色相選択そのものを切る
//  gloss        : スペキュラ強調。明部の階調を立てて金属の照り返し・反射境界を際立たせる (0..1)
//  exposure     : 全体ゲイン。1=そのまま。GUNMETAL のような「黒中心のトーン」は 1 未満で沈める
//  satCompress  : 彩度の飽和カーブ (0..1)。淡い色は豊かに、濃い色はそれ以上飽和させない。
//                 富士の LUT が持つ「色が濃いのにケバくない」非線形の再現
//  highlightDesat: ハイライトの脱色 (0..1)。白に近づくほど色を抜き、印画紙のような清潔な白へ
//  hueLuma      : hueCenter/hueWidth で選んだ色相の「明度」を動かす (±)。
//                 Velvia の青空の沈み、Classic Chrome の暖色の沈みのような色相別トーン
extern "C" float4 filmSim(coreimage::sample_t s,
                          float intensity,
                          float contrast,
                          float lift,
                          float rolloff,
                          float saturation,
                          float monoAmount,
                          float3 monoWeights,
                          float3 tint,
                          float3 shadowTint,
                          float3 highlightTint,
                          float3 hueTint,
                          float hueCenter,
                          float hueWidth,
                          float gloss,
                          float exposure,
                          float satCompress,
                          float highlightDesat,
                          float hueLuma)
{
    float3 x = clamp(s.rgb, 0.0, 1.0);
    float3 c = x * exposure;

    // 1. 白黒化(重みでカラーフィルタ効果 — 赤重ねなら空が沈む)
    if (monoAmount > 0.0) {
        float wsum = max(monoWeights.r + monoWeights.g + monoWeights.b, 1e-4);
        float g = dot(c, monoWeights / wsum);
        c = mix(c, float3(g), monoAmount);
        c *= mix(float3(1.0), tint, monoAmount);
    }

    // 2. 階調
    if (contrast >= 0.0) {
        float3 sc = c * c * (3.0 - 2.0 * c);              // S 字
        c = mix(c, sc, contrast);
    } else {
        float3 flat = 0.5 + (c - 0.5) * 0.75;             // 中間に寄せる
        c = mix(c, flat, -contrast);
    }
    c = lift + c * (1.0 - lift);                          // 黒を浮かせる
    c = c - rolloff * c * c * c;                          // 白を寝かせる

    // 3. 彩度
    // 2.5 スペキュラ強調(METAL系用): 明部だけ階調の傾きを立て、
    //     照り返しと地の境界を鋭くする。rolloff の後に置くことで白飛びは招かない。
    if (gloss > 0.0) {
        float gl = dot(c, float3(0.2126, 0.7152, 0.0722));
        float k = smoothstep(0.45, 0.9, gl);
        c = mix(c, 0.5 + (c - 0.5) * 1.45, k * gloss);
    }

    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = mix(float3(luma), c, saturation);

    // 3.5 彩度の飽和カーブ: クロマ 0.35 を境に、淡い色は増幅・濃い色は圧縮する。
    //     一律の saturation 倍率と違い、飽和済みの色が塗り絵にならない。
    if (satCompress > 0.0) {
        float l2 = dot(c, float3(0.2126, 0.7152, 0.0722));
        float d2 = max3(c.r, c.g, c.b) - min3(c.r, c.g, c.b);
        float a = 1.2 * satCompress;
        float sscale = (1.0 + 0.35 * a) / (1.0 + a * d2);
        c = float3(l2) + (c - float3(l2)) * sscale;
    }

    // 4. スプリットトーン(暗部と明部で別方向に転がす)
    float sh = 1.0 - smoothstep(0.0, 0.5, luma);
    float hi = smoothstep(0.45, 1.0, luma);
    c += shadowTint * sh + highlightTint * hi;

    // 5. 色相選択トーン(Velvia の「青空だけマゼンタに寄る」用)。
    //    彩度が低い画素(グレー)には効かせず、色相が hueCenter に近いほど強く足す。
    if (hueWidth > 1e-4) {
        float mx = max3(c.r, c.g, c.b);
        float mn = min3(c.r, c.g, c.b);
        float d = mx - mn;
        if (d > 1e-4) {
            float h;
            if (mx == c.r)      h = fmod((c.g - c.b) / d + 6.0, 6.0);
            else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
            else                h = (c.r - c.g) / d + 4.0;
            h /= 6.0;                                        // 0..1
            float dist = min(abs(h - hueCenter), 1.0 - abs(h - hueCenter));
            float w = 1.0 - smoothstep(0.0, hueWidth, dist); // 色相の近さ
            float chroma = smoothstep(0.06, 0.25, d);        // 無彩色には効かせない
            c += hueTint * (w * chroma);
            c *= 1.0 + hueLuma * (w * chroma);               // 色相別の明度(青空を沈める等)
        }
    }

    // 6. ハイライトの脱色: 白に近いほど色を抜く。ネオンのような色付きの白を作らない。
    if (highlightDesat > 0.0) {
        float l3 = dot(c, float3(0.2126, 0.7152, 0.0722));
        float k3 = smoothstep(0.7, 1.0, l3);
        c = mix(c, float3(l3), k3 * highlightDesat);
    }

    float3 result = mix(x, clamp(c, 0.0, 1.0), intensity);
    return float4(result, s.a);
}
