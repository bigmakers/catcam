import SwiftUI

/// 使い方ヘルプシート
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(helpItems) { item in
                        HelpRow(item: item)
                        if item.id != helpItems.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.12))
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("CATcam の使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { Haptics.tick(); dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - コンテンツ定義

    private let helpItems: [HelpItem] = [
        HelpItem(
            icon: "pawprint.fill",
            title: "猫を検出",
            description: "カメラに写った猫を自動で数えて、プレビューに頭数を表示します。撮影するとその頭数が写真に記録されます。"
        ),
        HelpItem(
            icon: "speaker.wave.2.fill",
            title: "猫を呼ぶ",
            description: "ボタンを押すと猫の注意を引く音が鳴ります。チュチュ・チチチ・ニャーから選べます。猫がこちらを向いた瞬間にシャッターを。マナーモードでも鳴ります。"
        ),
        HelpItem(
            icon: "map",
            title: "国境アウトライン地図",
            description: "写真の右下に国境線と現在地マーカーが焼き込まれます。プレビューの地図をピンチすると 1〜8 倍でズーム調整できます。地図ボタンで表示のオン/オフを切り替えられます。"
        ),
        HelpItem(
            icon: "arrow.triangle.2.circlepath.camera",
            title: "レンズ切替",
            description: "1x(広角)・3x(望遠)・5x・前面カメラを切り替えられます。"
        ),
        HelpItem(
            icon: "fork.knife",
            title: "近くのスポット",
            description: "撮影地点の近くのお店などの名前と距離を写真に焼き込みます。ジャンルと件数は設定から変更できます。"
        ),
        HelpItem(
            icon: "text.bubble",
            title: "コメント",
            description: "シャッター上の入力欄に書いた文字が、写真の見出しの下にタイポグラフィとして入ります。"
        ),
        HelpItem(
            icon: "circle.lefthalf.filled",
            title: "フィルタ強度",
            description: "黒が引き立つフィルム調フィルタの強さをスライダーで調整します。0% で無効です。"
        ),
        HelpItem(
            icon: "square",
            title: "Polaroid モード",
            description: "真四角にクロップして白フチを付けたポラロイド風になります。地名と日時は下の余白に入ります。"
        ),
        HelpItem(
            icon: "mappin.and.ellipse",
            title: "位置情報の焼き込み",
            description: "地名(アルファベット表記)・座標・日時・地名3文字の見出しが写真左上に入ります。保存される写真の EXIF にも GPS が記録されます。"
        ),
        HelpItem(
            icon: "photo.on.rectangle",
            title: "ギャラリー",
            description: "左下のサムネイルをタップすると写真アプリが開きます。"
        ),
    ]
}

// MARK: - モデル

private struct HelpItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// MARK: - 行コンポーネント

private struct HelpRow: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(item.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

#Preview {
    HelpView()
}
