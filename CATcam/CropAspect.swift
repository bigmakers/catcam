import CoreGraphics

/// 出力アスペクト比(枠なし)。縦持ち前提で幅:高さ比を定義する。
enum CropAspect: String, CaseIterable {
    case r43  = "r43"
    case r169 = "r169"
    case r11  = "r11"

    /// 表示ラベル
    var label: String {
        switch self {
        case .r43:  return "4:3"
        case .r169: return "16:9"
        case .r11:  return "1:1"
        }
    }

    /// 幅(portrait: 幅 < 高さ)
    var w: CGFloat {
        switch self {
        case .r43:  return 3
        case .r169: return 9
        case .r11:  return 1
        }
    }

    /// 高さ
    var h: CGFloat {
        switch self {
        case .r43:  return 4
        case .r169: return 16
        case .r11:  return 1
        }
    }

    /// SwiftUI .aspectRatio(previewRatio, contentMode:) に渡す値(= 幅/高さ)
    var previewRatio: CGFloat { w / h }
}
