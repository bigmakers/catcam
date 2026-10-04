import CoreGraphics

/// 出力アスペクト比。縦持ち前提で幅:高さ比を定義する。
/// polaroid だけは比率ではなく「真四角クロップ+白フチ+下帯」の額装モード。
enum CropAspect: String, CaseIterable {
    case r43  = "r43"
    case r169 = "r169"
    case r11  = "r11"
    case polaroid = "polaroid"

    /// 表示ラベル
    var label: String {
        switch self {
        case .r43:  return "4:3"
        case .r169: return "16:9"
        case .r11:  return "1:1"
        case .polaroid: return "Polaroid"
        }
    }

    /// 幅(portrait: 幅 < 高さ)。polaroid は真四角クロップの基準。
    var w: CGFloat {
        switch self {
        case .r43:  return 3
        case .r169: return 9
        case .r11, .polaroid: return 1
        }
    }

    /// 高さ
    var h: CGFloat {
        switch self {
        case .r43:  return 4
        case .r169: return 16
        case .r11, .polaroid: return 1
        }
    }

    /// SwiftUI .aspectRatio(previewRatio, contentMode:) に渡す値(= 幅/高さ)。
    /// polaroid は composePolaroid のキャンバス比(side*1.12 : side*1.30)。
    var previewRatio: CGFloat {
        switch self {
        case .polaroid: return 1.12 / 1.30
        default: return w / h
        }
    }
}
