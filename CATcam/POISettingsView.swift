import SwiftUI

/// 表示設定シート。
/// 焼き込む情報のオン/オフ(地名・座標・日時)と、近くのスポットのジャンル/件数を設定する。
/// @AppStorage のキーは ContentView と共通なので自動同期される。
struct POISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // 焼き込む情報トグル
    @AppStorage("showPlaceName") private var showPlaceName = false
    @AppStorage("showCoordinates") private var showCoordinates = false
    @AppStorage("showDateTime") private var showDateTime = false
    @AppStorage("infoOnRight") private var infoOnRight = false

    // 近くのスポット設定
    @AppStorage("poiGenre") private var poiGenreRaw = POIGenre.none.rawValue
    @AppStorage("poiCount") private var poiCount = 3

    // 色温度(ContentView と同一キーで自動同期)
    @AppStorage("coolness") private var coolness = 0.35

    // フィルム強度(コントラスト/グレイン/減光。ContentView と同一キーで自動同期)
    @AppStorage("filmIntensity") private var intensity = 0.8

    // フィルムシミュレーション(ContentView と同一キー)
    @AppStorage("filmSim") private var filmSimRaw = FilmSimulation.standard.rawValue
    private var filmSimBinding: Binding<FilmSimulation> {
        Binding(get: { FilmSimulation(rawValue: filmSimRaw) ?? .standard },
                set: { filmSimRaw = $0.rawValue })
    }

    // 猫を呼ぶ音(ContentView と同一キー)
    @AppStorage("catSound") private var catSoundRaw = CatCaller.Sound.squeak.rawValue
    @StateObject private var catCaller = CatCaller()
    private var catSoundBinding: Binding<CatCaller.Sound> {
        Binding(get: { CatCaller.Sound(rawValue: catSoundRaw) ?? .squeak },
                set: { catSoundRaw = $0.rawValue })
    }

    // コメント書体(ContentView と同一キー)
    @AppStorage("commentFont") private var commentFontRaw = CommentFont.minchoEditorial.rawValue
    private var commentFontBinding: Binding<CommentFont> {
        Binding(get: { CommentFont.resolve(commentFontRaw) },
                set: { commentFontRaw = $0.rawValue })
    }

    /// rawValue 文字列と POIGenre の橋渡し
    private var genreBinding: Binding<POIGenre> {
        Binding(
            get: { POIGenre(rawValue: poiGenreRaw) ?? .none },
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

                    Stepper("表示件数: \(poiCount)件", value: $poiCount, in: 1...10)
                }

                Section {
                    Text("撮影地点の近くのスポット名と距離が写真に焼き込まれます。ジャンル『なし』で無効になります。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    // OpenPOI API の利用条件(出典表記)
                    Link(destination: URL(string: "https://openpoiapi.com/attribution.html")!) {
                        Text("スポットデータ出典: OpenPOI API")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                }

                Section("猫を呼ぶ音") {
                    Picker("音の種類", selection: catSoundBinding) {
                        ForEach(CatCaller.Sound.allCases) { sound in
                            Label(sound.label, systemImage: sound.symbol).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        Haptics.tick()
                        catCaller.play(catSoundBinding.wrappedValue)
                    } label: {
                        Label("試しに鳴らす", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                    }
                }

                Section("コメント書体") {
                    Picker("書体", selection: commentFontBinding) {
                        ForEach(CommentFont.allCases) { font in
                            Text(font.label).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("フィルムシミュレーション") {
                    Picker("フィルム", selection: filmSimBinding) {
                        ForEach(FilmSimulation.allCases) { sim in
                            Text(sim.name).tag(sim)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(filmSimBinding.wrappedValue.caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("効果の強さ")
                            .font(.system(size: 14))
                        HStack {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Slider(value: $intensity, in: 0...1)
                            Text(String(format: "%.0f%%", intensity * 100))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("色味") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("色温度(寒色)")
                            .font(.system(size: 14))
                        HStack {
                            Text("標準")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Slider(value: $coolness, in: 0...1)
                                .tint(.cyan)
                            Text("寒色")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if filmSimBinding.wrappedValue.isMonochrome {
                            Text("白黒系のフィルムでは色温度は効きません")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(filmSimBinding.wrappedValue.isMonochrome)
                    .padding(.vertical, 4)
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
