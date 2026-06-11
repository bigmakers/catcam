import SwiftUI

/// 近くのスポット(POI)の焼き込み設定シート。
/// ジャンルと件数は @AppStorage で永続化し、ContentView と整合する。
struct POISettingsView: View {
    @Environment(\.dismiss) private var dismiss

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
                Section {
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
            .navigationTitle("近くのスポット")
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
