import SwiftUI

/// 表示設定シート。
/// 焼き込む情報のオン/オフ(地名・座標・日時)と、近くのスポットのジャンル/件数を設定する。
/// @AppStorage のキーは ContentView と共通なので自動同期される。
struct POISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // 焼き込む情報トグル
    @AppStorage("showPlaceName") private var showPlaceName = true
    @AppStorage("showCoordinates") private var showCoordinates = true
    @AppStorage("showDateTime") private var showDateTime = true
    @AppStorage("infoOnRight") private var infoOnRight = false

    // 近くのスポット設定
    @AppStorage("poiGenre") private var poiGenreRaw = POIGenre.food.rawValue
    @AppStorage("poiCount") private var poiCount = 3

    /// rawValue 文字列と POIGenre の橋渡し
    private var genreBinding: Binding<POIGenre> {
        Binding(
            get: { POIGenre(rawValue: poiGenreRaw) ?? .food },
            set: { poiGenreRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("焼き込む情報") {
                    Toggle("地名", isOn: $showPlaceName)
                    Toggle("座標(GPS)", isOn: $showCoordinates)
                    Toggle("日時", isOn: $showDateTime)
                    Picker("情報の位置", selection: $infoOnRight) {
                        Text("左").tag(false)
                        Text("右").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("近くのスポット") {
                    Picker("ジャンル", selection: genreBinding) {
                        ForEach(POIGenre.allCases) { genre in
                            Text(genre.label).tag(genre)
                        }
                    }
                    .pickerStyle(.menu)

                    Stepper("表示件数: \(poiCount)件", value: $poiCount, in: 1...6)
                }

                Section {
                    Text("撮影地点の近くのスポット名と距離が写真に焼き込まれます。ジャンル『なし』で無効になります。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("表示設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { Haptics.tick(); dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    POISettingsView()
}
