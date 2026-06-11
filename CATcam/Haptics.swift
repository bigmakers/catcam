import UIKit

/// 軽い触覚フィードバック。時計の秒針のような「カチッ」とした感触。
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()

    /// ボタンタップ時に鳴らす。
    static func tick() {
        selection.selectionChanged()
        selection.prepare()  // 次のタップの遅延を減らす
    }
}
