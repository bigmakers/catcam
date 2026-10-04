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
            icon: "camera.aperture",
            title: "3つの焦点距離",
            description: "中央のボタンで 28mm / 52mm / 120mm(35mm換算)を切り替えます。ズームではなく単焦点を持ち替える感覚の3段切替です。望遠レンズ搭載機では 120mm は自動的に実レンズで撮影します。前面カメラ使用中は切り替えられません。"
        ),
        HelpItem(
            icon: "rectangle.ratio.16.to.9",
            title: "アスペクト比・ポラロイド",
            description: "右下のボタンで 4:3 / 16:9 / 1:1 / Polaroid を切り替えます。Polaroid は真四角の写真を白フチで額装し、下帯に地名・コメント・日時を印字します。横向きに構えると写真も横位置で出力されます(Polaroid 以外)。"
        ),
        HelpItem(
            icon: "mappin.and.ellipse",
            title: "焼き込み情報(既定オフ)",
            description: "地名(アルファベット)・座標・日時・地名3文字の見出しを写真の左上に焼き込みます。表示設定で項目ごとにオン/オフでき、初期状態はすべてオフです。保存写真の EXIF にも GPS が記録されます。"
        ),
        HelpItem(
            icon: "map",
            title: "地図アウトライン",
            description: "都道府県/州レベルの輪郭と現在地マーカーを焼き込みます。プレビューをピンチすると 1〜8 倍でズームできます(地図表示中のみ)。"
        ),
        HelpItem(
            icon: "film.stack",
            title: "フィルムシミュレーション(16種)",
            description: "撮影画面のいちばん上のダイヤルで切り替えます。先頭は毛並みを立てる「毛並みフィルタ」5種(SILVER / SMOKE / TSUYA / KURO / CHATORA)、続いてフィルム11種(STANDARD / VIVID / SOFT / CLASSIC / NEG. STD / NEG. HI / NOSTALGIC / CINEMA / MONO / MONO+R / SEPIA)。プレビューにそのまま反映され、見たままが保存されます。"
        ),
        HelpItem(
            icon: "pawprint.fill",
            title: "毛並みフィルタ",
            description: "猫の毛並みを立てるためのプリセット群です。局所コントラストとマイクロコントラストで毛の一本一本の流れを強調し、明部の階調を立てて毛艶を際立たせます。SILVER=銀・サバトラ / SMOKE=灰・ロシアンブルー / TSUYA=黒猫の艶毛 / KURO=黒猫を重厚に / CHATORA=茶トラ・キジトラ。"
        ),
        HelpItem(
            icon: "eye",
            title: "Before / After 比較",
            description: "プレビューを長押ししている間はフィルタが外れて素の映像(ORIGINAL)になります。指を離すと元に戻ります。効果のかかり方を確認したいときに。"
        ),
        HelpItem(
            icon: "slider.horizontal.3",
            title: "効果の強さ・色温度",
            description: "表示設定で、フィルムの効き(階調・彩度・粒状・周辺減光)の強さと、色温度(寒色)を調整できます。強さ 0% で素の写真に戻ります。色温度は白黒系のフィルムでは効きません。"
        ),
        HelpItem(
            icon: "text.bubble",
            title: "コメント(最大10行)",
            description: "入力欄のコメントを地図の下に焼き込みます。改行で最大10行、行数に応じて自動縮小。書体は表示設定で明朝/ゴシックを選べます。完了またはプレビュータップでキーボードを閉じます。"
        ),
        HelpItem(
            icon: "bell.fill",
            title: "猫を呼ぶ音",
            description: "画面上部の猫ボタンで、猫を振り向かせる短い音(チュチュ/チチチ/ニャー)を鳴らせます。音の種類は表示設定から選べます。マナーモードでも鳴るので周囲にはご配慮を。"
        ),
        HelpItem(
            icon: "pawprint",
            title: "猫ログ",
            description: "撮った一枚は自動でアプリ内の「猫ログ」にも記録されます(端末内のみ・外部送信なし)。左下のサムネイルをタップすると、いつどこで撮った猫かを一覧で振り返れます。"
        ),
        HelpItem(
            icon: "fork.knife",
            title: "近くのスポット",
            description: "撮影地点の近くのお店などの名前と距離を焼き込みます。ジャンルと件数は表示設定から変更できます。国内のスポットデータは OpenPOI API(約337万件)、海外や駅・交通は Apple の地図サービスを利用します。"
        ),
        HelpItem(
            icon: "photo.on.rectangle.angled",
            title: "ギャラリー取り込み・プレビュー",
            description: "左下の取り込みボタンでフォトライブラリの写真に同じ加工を適用できます。サムネイルをタップすると直近の結果を全画面でプレビューできます。"
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
