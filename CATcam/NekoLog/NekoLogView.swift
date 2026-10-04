import SwiftUI

/// アプリ内ギャラリー「猫ログ」。撮った猫を3列グリッドで振り返る(端末内のみ)。
struct NekoLogView: View {
    @ObservedObject private var store = NekoLogStore.shared
    let onClose: () -> Void

    /// 詳細表示中のエントリ
    @State private var selected: NekoLogEntry?

    private let columns = [GridItem(.flexible(), spacing: 2),
                           GridItem(.flexible(), spacing: 2),
                           GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "pawprint")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("まだ猫がいません")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("撮影した一枚が自動でここに記録されます")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.entries) { entry in
                                NekoLogCell(entry: entry)
                                    .onTapGesture {
                                        Haptics.tick()
                                        selected = entry
                                    }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("猫ログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("とじる") { Haptics.tick(); onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.entries.count)匹ぶん")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .fullScreenCover(item: $selected) { entry in
                NekoLogDetailView(entry: entry) { selected = nil }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// グリッドの1マス(正方形サムネイル)。
private struct NekoLogCell: View {
    let entry: NekoLogEntry
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.opacity(0.06)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            if image == nil {
                let thumb = await Task.detached(priority: .utility) {
                    NekoLogStore.shared.thumbnail(for: entry, maxPixel: 160)
                }.value
                image = thumb
            }
        }
    }
}

/// 詳細: 全画面表示 + 日付・場所 + 共有・削除。
private struct NekoLogDetailView: View {
    let entry: NekoLogEntry
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var confirmDelete = false

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: entry.date)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Button { Haptics.tick(); onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    Spacer()
                }
                .padding(16)

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText)
                            .font(.system(size: 13, weight: .bold))
                        if !entry.place.isEmpty {
                            Text("📍 \(entry.place)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("CATcam", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                    }
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(10)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
            }
        }
        .task {
            image = UIImage(contentsOfFile: NekoLogStore.shared.imageURL(for: entry).path)
        }
        .confirmationDialog("この一枚を猫ログから削除しますか?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                NekoLogStore.shared.delete(entry)
                onClose()
            }
        } message: {
            Text("フォトライブラリに保存済みの写真はそのまま残ります。")
        }
    }
}
