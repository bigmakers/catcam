import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// フィルムシミュレーションのプリセット。
///
/// 名称はすべて自前(Fujifilm 等の登録商標は使わない)。
/// 見た目の狙いだけをパラメータで表現している。
enum FilmSimulation: String, CaseIterable, Identifiable {
    // 毛並みフィルタ(猫の毛を立てる主役プリセット群。ダイヤル先頭に出す)
    case steel
    case titanium
    case chromeMetal
    case gunmetal
    case copper
    // フィルムシリーズ
    case standard
    case vivid
    case soft
    case chrome
    case negStd
    case negHi
    case nostalgic
    case cinema
    case mono
    case monoRed
    case sepia

    var id: String { rawValue }

    /// 撮影画面のダイヤルに出す短い名前(英字・大文字)
    var name: String {
        switch self {
        case .standard:  return "STANDARD"
        case .vivid:     return "VIVID"
        case .soft:      return "SOFT"
        case .chrome:    return "CLASSIC"
        case .negStd:    return "NEG. STD"
        case .negHi:     return "NEG. HI"
        case .nostalgic: return "NOSTALGIC"
        case .cinema:    return "CINEMA"
        case .mono:      return "MONO"
        case .monoRed:   return "MONO+R"
        case .sepia:     return "SEPIA"
        case .steel:     return "SILVER"
        case .titanium:  return "SMOKE"
        case .chromeMetal: return "TSUYA"
        case .gunmetal:  return "KURO"
        case .copper:    return "CHATORA"
        }
    }

    /// 設定画面などで出す一言説明
    var caption: String {
        switch self {
        case .standard:  return "自然な発色。迷ったらこれ"
        case .vivid:     return "青と緑が締まる高彩度。風景向き"
        case .soft:      return "発色は豊かなまま階調は軟らかい。人物・日常向き"
        case .chrome:    return "彩度を抑えて影を締めた渋い発色"
        case .negStd:    return "平坦で忠実。肌がきれいに出る"
        case .negHi:     return "ネガ調のままコントラストを上げた"
        case .nostalgic: return "琥珀のハイライトと深い影"
        case .cinema:    return "低彩度・低コントラストの映画調"
        case .mono:      return "滑らかな階調の白黒"
        case .monoRed:   return "赤フィルター白黒。空が沈む"
        case .sepia:     return "褪せた古写真のセピア"
        case .steel:     return "銀・サバトラ向き。寒色で毛並みの一本一本が立つ"
        case .titanium:  return "灰・ロシアンブルー向き。柔らかい銀毛と豊かな中間調"
        case .chromeMetal: return "黒猫の艶毛向き。強い毛艶と深い黒"
        case .gunmetal:  return "黒猫を重厚に。青灰のトーンで沈める"
        case .copper:    return "茶トラ・キジトラ向き。赤茶の深みと毛先のハイライト"
        }
    }

    /// 白黒系かどうか(UI で色温度スライダを無効化する判定に使う)
    var isMonochrome: Bool {
        switch self {
        case .mono, .monoRed, .sepia: return true
        default: return false
        }
    }

    /// 毛並みフィルタ(旧METAL系。金属質感=毛艶の強調に転用)かどうか。ダイヤルの色分けに使う。
    var isMetal: Bool {
        switch self {
        case .steel, .titanium, .chromeMetal, .gunmetal, .copper: return true
        default: return false
        }
    }

    /// カーネルに渡すパラメータ一式。
    var params: Params {
        switch self {
        case .standard:
            return Params(contrast: 0.18, lift: 0.0, rolloff: 0.02, saturation: 1.06,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: .zero, highlightTint: .zero,
                          grain: 0.55, vignette: 0.55,
                          satCompress: 0.30, highlightDesat: 0.15)
        case .vivid:
            // Velvia の性格のうち「青空がわずかにマゼンタへ転ぶ」を hueTint で再現。
            // 青(hueCenter 0.60)の近傍にだけ赤を足し、緑・肌には波及させない。
            return Params(contrast: 0.55, lift: 0.0, rolloff: 0.0, saturation: 1.45,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(-0.010, -0.004, 0.014),
                          highlightTint: RGB(0.010, 0.004, -0.006),
                          hueTint: RGB(0.110, -0.012, 0.028), hueCenter: 0.60, hueWidth: 0.08,
                          grain: 0.45, vignette: 0.95,
                          satCompress: 0.60, highlightDesat: 0.25, hueLuma: -0.14)
        case .soft:
            // ASTIA の思想は「標準より彩度は高く、コントラストだけ軟らかい」。
            // 軟調=地味と取り違えないよう、彩度は STANDARD(1.06)より上に置く。
            return Params(contrast: -0.22, lift: 0.022, rolloff: 0.05, saturation: 1.30,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.008, 0.004, 0.006),
                          highlightTint: RGB(0.006, 0.003, 0.0),
                          grain: 0.45, vignette: 0.35,
                          satCompress: 0.70, highlightDesat: 0.30)
        case .chrome:
            // CLASSIC CHROME は ETERNA に次ぐ低彩度が本来の序列。
            // S字コントラストがクロマを押し戻すので、狙いよりも深く下げておく。
            return Params(contrast: 0.34, lift: 0.012, rolloff: 0.03, saturation: 0.63,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(-0.016, 0.0, 0.024),
                          highlightTint: RGB(0.018, 0.008, -0.010),
                          hueCenter: 0.10, hueWidth: 0.14,
                          grain: 0.80, vignette: 0.85,
                          satCompress: 0.40, highlightDesat: 0.35, hueLuma: -0.10)
        case .negStd:
            // 最軟調は CINEMA(ETERNA)の役どころ。それより平坦にならない範囲で軟らかく。
            return Params(contrast: -0.22, lift: 0.038, rolloff: 0.07, saturation: 0.90,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.004, 0.004, 0.010),
                          highlightTint: .zero,
                          grain: 0.40, vignette: 0.25,
                          satCompress: 0.50, highlightDesat: 0.20)
        case .negHi:
            return Params(contrast: 0.24, lift: 0.014, rolloff: 0.03, saturation: 0.90,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.0, 0.002, 0.008),
                          highlightTint: RGB(0.006, 0.004, 0.0),
                          grain: 0.55, vignette: 0.60,
                          satCompress: 0.50, highlightDesat: 0.20)
        case .nostalgic:
            // Nostalgic Neg. は「高彩度なのに階調は軟らかい」。深い影はトーンで出す。
            return Params(contrast: 0.08, lift: 0.026, rolloff: 0.04, saturation: 1.15,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.006, -0.002, -0.014),
                          highlightTint: RGB(0.034, 0.016, -0.020),
                          grain: 0.85, vignette: 0.90,
                          satCompress: 0.50, highlightDesat: 0.20)
        case .cinema:
            return Params(contrast: -0.28, lift: 0.034, rolloff: 0.10, saturation: 0.66,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(-0.006, 0.006, 0.020),
                          highlightTint: RGB(0.012, 0.008, -0.004),
                          grain: 0.75, vignette: 0.65,
                          satCompress: 0.50, highlightDesat: 0.45)
        case .mono:
            // ACROS の核は「深い黒と世界最細粒」。caption の「滑らかな階調」と
            // 矛盾しないよう、粒は控えめ・黒はリフトせず沈める。
            return Params(contrast: 0.30, lift: 0.0, rolloff: 0.03, saturation: 1.0,
                          monoAmount: 1, monoWeights: RGB(0.30, 0.59, 0.11), tint: .white,
                          shadowTint: .zero, highlightTint: .zero,
                          grain: 0.70, vignette: 0.75)
        case .monoRed:
            return Params(contrast: 0.44, lift: 0.0, rolloff: 0.02, saturation: 1.0,
                          monoAmount: 1, monoWeights: RGB(0.64, 0.28, 0.08), tint: .white,
                          shadowTint: .zero, highlightTint: .zero,
                          grain: 1.15, vignette: 0.95)
        case .sepia:
            return Params(contrast: 0.22, lift: 0.030, rolloff: 0.06, saturation: 1.0,
                          monoAmount: 1, monoWeights: RGB(0.34, 0.55, 0.11),
                          tint: RGB(1.10, 0.96, 0.76),
                          shadowTint: RGB(0.010, 0.004, -0.010),
                          highlightTint: RGB(0.020, 0.010, -0.016),
                          grain: 1.0, vignette: 0.90)

        // ── 毛並みフィルタ(MapCam の METAL 系を毛艶向けに転用)──
        // 局所コントラスト(clarity)=毛の流れ、マイクロコントラスト(texture)=毛の一本一本、
        // スペキュラ強調(gloss)=毛艶、の組み合わせで毛並みを立てる。
        case .steel:
            // 低彩度・寒色・黒を締める・ハイライトを強く残す。lift 負値で黒を沈める。
            return Params(contrast: 0.30, lift: -0.020, rolloff: 0.06, saturation: 0.35,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.0, 0.004, 0.014),
                          highlightTint: RGB(-0.004, 0.002, 0.010),
                          grain: 0.25, vignette: 0.50,
                          clarity: 0.80, texture: 0.90, gloss: 0.70)
        case .titanium:
            // STEEL よりコントラストを落とし中間調を残す。わずかに青紫へ。
            return Params(contrast: 0.08, lift: 0.012, rolloff: 0.09, saturation: 0.32,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.004, 0.0, 0.010),
                          highlightTint: RGB(0.004, 0.002, 0.008),
                          grain: 0.20, vignette: 0.35,
                          clarity: 0.45, texture: 0.65, gloss: 0.35)
        case .chromeMetal:
            // 鏡面。高コントラスト・深い黒・最強の gloss で反射境界を立てる。
            return Params(contrast: 0.55, lift: -0.030, rolloff: 0.05, saturation: 0.30,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(-0.004, 0.0, 0.010),
                          highlightTint: .zero,
                          grain: 0.15, vignette: 0.60,
                          clarity: 0.90, texture: 0.55, gloss: 1.0)
        case .gunmetal:
            // 黒中心のトーン。シャドウは潰しきらず、ハイライトだけ鋭く。
            return Params(contrast: 0.26, lift: -0.012, rolloff: 0.12, saturation: 0.28,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.002, 0.006, 0.016),
                          highlightTint: RGB(-0.002, 0.002, 0.008),
                          grain: 0.30, vignette: 0.85,
                          clarity: 0.60, texture: 0.80, gloss: 0.85, exposure: 0.80)
        case .copper:
            // 赤橙+深いブラウン、黄色寄りのハイライト。彩度は上げすぎない。
            return Params(contrast: 0.20, lift: 0.012, rolloff: 0.07, saturation: 0.75,
                          monoAmount: 0, monoWeights: .gray, tint: .white,
                          shadowTint: RGB(0.012, -0.004, -0.016),
                          highlightTint: RGB(0.030, 0.018, -0.014),
                          grain: 0.50, vignette: 0.70,
                          clarity: 0.50, texture: 0.60, gloss: 0.50)
        }
    }

    struct RGB {
        var r: Double, g: Double, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        static let zero = RGB(0, 0, 0)
        static let white = RGB(1, 1, 1)
        static let gray = RGB(0.2126, 0.7152, 0.0722)
        var vector: CIVector { CIVector(x: r, y: g, z: b) }
    }

    struct Params {
        var contrast: Double
        var lift: Double
        var rolloff: Double
        var saturation: Double
        var monoAmount: Double
        var monoWeights: RGB
        var tint: RGB
        var shadowTint: RGB
        var highlightTint: RGB
        /// 特定の色相にだけ足す色(既定は無効)。青空だけマゼンタに、のような色相選択トーン
        var hueTint: RGB = .zero
        /// hueTint を効かせる色相(0..1)。青空 ≒ 0.60
        var hueCenter: Double = 0
        /// hueTint の効き幅(0..1)。0 で無効
        var hueWidth: Double = 0
        /// グレイン量の倍率(1.0 が基準)
        var grain: Double
        /// 周辺減光の倍率(1.0 が基準)
        var vignette: Double
        /// 局所コントラスト(クラリティ)。大きめ半径のアンシャープで凹凸・面の起伏を立てる
        var clarity: Double = 0
        /// マイクロコントラスト。小半径のアンシャープでヘアライン・傷などの微細質感を立てる
        var texture: Double = 0
        /// スペキュラ強調。明部の階調を立てて照り返し・反射境界を際立たせる
        var gloss: Double = 0
        /// 全体ゲイン。1=そのまま。黒中心のトーン(GUNMETAL等)は 1 未満で沈める
        var exposure: Double = 1
        /// 彩度の飽和カーブ(0..1)。淡い色は豊かに、濃い色はそれ以上飽和させない
        var satCompress: Double = 0
        /// ハイライトの脱色(0..1)。白に近づくほど色を抜く
        var highlightDesat: Double = 0
        /// hueCenter/hueWidth で選んだ色相の明度を動かす(±)。青空を沈める等
        var hueLuma: Double = 0

        /// filmSim カーネルへ渡す引数一式。
        /// アプリ本体と検証ツール(contact sheet / analyze)が必ず同じ並びを使うための一元化。
        func kernelArguments(input: CIImage, intensity: Double) -> [Any] {
            [input,
             Float(intensity),
             Float(contrast),
             Float(lift),
             Float(rolloff),
             Float(saturation),
             Float(monoAmount),
             monoWeights.vector,
             tint.vector,
             shadowTint.vector,
             highlightTint.vector,
             hueTint.vector,
             Float(hueCenter),
             Float(hueWidth),
             Float(gloss),
             Float(exposure),
             Float(satCompress),
             Float(highlightDesat),
             Float(hueLuma)]
        }
    }
}

/// 局所コントラストとマイクロコントラスト。
///
/// METAL 系プリセットの「金属感」の土台。単なるシャープではなく、
/// - clarity: 大きめ半径のアンシャープマスクで面の起伏・明暗のうねりを立てる
/// - texture: 小半径のアンシャープマスクでヘアライン・傷・加工跡だけを立てる
/// の2層で作る(周波数分離の簡易版)。
/// 半径は基準幅 1440px からの倍率でスケールさせ、プレビューと保存で見え方を揃える。
enum LocalContrast {
    private static let referenceWidth: CGFloat = 1440

    static func apply(to image: CIImage, clarity: Double, texture: Double) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0 else { return image }
        let k = max(0.5, extent.width / referenceWidth)
        var output = image

        if clarity > 0.001 {
            let f = CIFilter.unsharpMask()
            f.inputImage = output
            f.radius = Float(28 * k)                 // 大半径 = 局所コントラスト
            f.intensity = Float(0.35 * clarity)
            if let o = f.outputImage { output = o.cropped(to: extent) }
        }
        if texture > 0.001 {
            let f = CIFilter.unsharpMask()
            f.inputImage = output
            f.radius = Float(max(1.2, 3.0 * k))      // 小半径 = マイクロコントラスト
            f.intensity = Float(0.60 * texture)
            if let o = f.outputImage { output = o.cropped(to: extent) }
        }
        return output
    }
}

/// フィルムグレインの合成。
///
/// `CIRandomGenerator` は 1px 単位のノイズなので、そのまま重ねると
/// **粒の大きさが画像サイズに追従しない**。プレビュー(約1440px)では見えていた粒が、
/// 12MP(4032px)で保存すると半分、24MP では 1/4 の強さに落ちて消えてしまう。
/// そこで基準幅ぶんの領域でノイズを作ってから画像サイズまで拡大し、
/// **どの解像度でも同じ大きさ・同じ強さの粒**になるようにする。
enum FilmGrain {
    /// 粒の大きさの基準となる幅。プレビューの実解像度に近い値。
    private static let referenceWidth: CGFloat = 1440
    /// 拡大時の bilinear 補間で粒のコントラストが落ちるぶんの補正(実測で決めた値)。
    /// tools/analyze_grain.swift で各解像度の粒の強さが揃うことを確認している。
    private static let upscaleCompensation: CGFloat = 1.25

    /// - Parameter amount: 粒の量。1.0 が基準
    static func apply(to image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return image }

        // 基準幅より大きい画像ほど、低い解像度でノイズを作ってから引き伸ばす
        let k = max(1, extent.width / referenceWidth)
        let noiseExtent = CGRect(x: 0, y: 0,
                                 width: (extent.width / k).rounded(.up),
                                 height: (extent.height / k).rounded(.up))

        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?
            .cropped(to: noiseExtent) else { return image }

        // ノイズをグレースケール化(色付きグレインを防ぐ)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        let w = (r: CGFloat(0.299), g: CGFloat(0.587), b: CGFloat(0.114))
        mono.rVector = CIVector(x: w.r, y: w.g, z: w.b, w: 0)
        mono.gVector = CIVector(x: w.r, y: w.g, z: w.b, w: 0)
        mono.bVector = CIVector(x: w.r, y: w.g, z: w.b, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let grayNoise = mono.outputImage?.cropped(to: noiseExtent) else { return image }

        // 中間グレー基準にスケール。拡大するぶんは補正して強さを揃える。
        // k=1 で 1.0、k=2 以上で上限になるよう繋いで、境目で粒が飛ばないようにする。
        let comp = 1 + (upscaleCompensation - 1) * min(1, k - 1)
        let strength = CGFloat(0.10 * amount) * comp
        let scale = CIFilter.colorMatrix()
        scale.inputImage = grayNoise
        let s = strength * 2
        scale.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        scale.gVector = CIVector(x: 0, y: s, z: 0, w: 0)
        scale.bVector = CIVector(x: 0, y: 0, z: s, w: 0)
        scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        scale.biasVector = CIVector(x: 0.5 - strength, y: 0.5 - strength, z: 0.5 - strength, w: 0)
        guard let scaled = scale.outputImage?.cropped(to: noiseExtent) else { return image }

        // 画像サイズまで引き伸ばす(bilinear で粒の角が取れ、フィルムらしい粒になる)
        let grain = scaled
            .transformed(by: CGAffineTransform(scaleX: k, y: k))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)

        let blend = CIFilter(name: "CISoftLightBlendMode")
        blend?.setValue(grain, forKey: kCIInputImageKey)
        blend?.setValue(image, forKey: kCIInputBackgroundImageKey)
        return blend?.outputImage?.cropped(to: extent) ?? image
    }
}

/// フィルムシミュレーションを Core Image パイプラインに適用する。
///
/// 手順は 局所/マイクロコントラスト → 階調・彩度・スプリットトーン・スペキュラ(Metal 1パス)
/// → 周辺減光 → グレイン → 色温度。プレビューと保存で同じ経路を通すので、見たままが保存される。
final class FilmSimulationFilter {
    static let shared = FilmSimulationFilter()

    private let kernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "filmSim", fromMetalLibraryData: data)
    }()

    /// - Parameters:
    ///   - sim: 適用するフィルムシミュレーション
    ///   - intensity: 効果の強さ 0–1。0 なら素通し
    ///   - coolness: 色温度(寒色)0–1。白黒系プリセットでは無視する
    func apply(to image: CIImage,
               sim: FilmSimulation,
               intensity: Double,
               coolness: Double = 0) -> CIImage {
        guard intensity > 0.001 else {
            return coolness > 0.001 && !sim.isMonochrome
                ? applyCoolness(to: image, coolness: coolness) : image
        }

        let p = sim.params
        var output = image

        // 局所コントラスト+マイクロコントラスト(METAL系)。色付けの前に質感を立てる。
        if p.clarity > 0.001 || p.texture > 0.001 {
            output = LocalContrast.apply(to: output,
                                         clarity: p.clarity * intensity,
                                         texture: p.texture * intensity)
        }

        if let kernel,
           let graded = kernel.apply(extent: output.extent,
                                     arguments: p.kernelArguments(input: output, intensity: intensity)) {
            output = graded
        }

        // 周辺減光(プリセットごとに効き方を変える)
        if p.vignette > 0.001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = output
            vignette.intensity = Float(1.1 * intensity * p.vignette)
            vignette.radius = 1.9
            if let vignetted = vignette.outputImage { output = vignetted }
        }

        // フィルムグレイン
        if p.grain > 0.001 {
            output = FilmGrain.apply(to: output, amount: intensity * p.grain)
        }

        // 色温度は白黒系では効かせない
        if coolness > 0.001 && !sim.isMonochrome {
            output = applyCoolness(to: output, coolness: coolness)
        }

        return output
    }

    /// チャンネルゲインで寒色に振る。
    private func applyCoolness(to image: CIImage, coolness: Double) -> CIImage {
        let k = max(0, min(coolness, 1))
        let m = CIFilter.colorMatrix()
        m.inputImage = image
        m.rVector = CIVector(x: CGFloat(1.0 - 0.10 * k), y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: CGFloat(1.0 + 0.12 * k), w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return m.outputImage ?? image
    }
}
