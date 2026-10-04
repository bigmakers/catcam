import SwiftUI
import UIKit

/// コメント焼き込みの書体スタイル(雑誌風)。設定で選択し、
/// 焼き込み(PhotoRenderer/UIKit)とライブプレビュー(SwiftUI)で共通に使う。
enum CommentFont: String, CaseIterable, Identifiable {
    case minchoEditorial   // 明朝(エディトリアル)
    case gothicFashion     // ゴシック(ファッション誌)
    case minchoDelicate    // 明朝(繊細)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minchoEditorial: return "明朝(エディトリアル)"
        case .gothicFashion:   return "ゴシック(ファッション誌)"
        case .minchoDelicate:  return "明朝(繊細)"
        }
    }

    var isSerif: Bool {
        switch self {
        case .gothicFashion: return false
        default:             return true
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .minchoEditorial: return .semibold
        case .gothicFashion:   return .heavy
        case .minchoDelicate:  return .regular
        }
    }

    var swiftWeight: Font.Weight {
        switch self {
        case .minchoEditorial: return .semibold
        case .gothicFashion:   return .heavy
        case .minchoDelicate:  return .regular
        }
    }

    var design: Font.Design { isSerif ? .serif : .default }

    /// 字間(フォントサイズに対する比率)。ファッション誌は広め。
    var trackingRatio: CGFloat {
        switch self {
        case .minchoEditorial: return 0.04
        case .gothicFashion:   return 0.12
        case .minchoDelicate:  return 0.10
        }
    }

    /// UIKit フォント生成(セリフ適用)。
    func uiFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight)
        guard isSerif, let d = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: d, size: size)
    }

    static func resolve(_ raw: String) -> CommentFont {
        CommentFont(rawValue: raw) ?? .minchoEditorial
    }
}
