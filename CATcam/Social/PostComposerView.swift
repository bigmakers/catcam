import SwiftUI
import CoreLocation

/// 撮影後の「100日マップに残す」投稿シート。
/// 初回投稿時はニックネーム設定と利用ルール同意をここで行う。
struct PostComposerView: View {
    let imageData: Data
    let thumbnail: UIImage
    let location: CLLocation
    let placeName: String
    let initialComment: String
    let onClose: () -> Void
    let onPosted: () -> Void

    @AppStorage("snsMyNickname") private var myNickname = ""
    @AppStorage("snsAgreedTerms") private var agreedTerms = false

    @State private var blurLevel = 1           // 初期値=約300mぼかす
    @State private var comment: String
    @State private var nicknameInput = ""
    @State private var posting = false
    @State private var errorMessage: String?

    init(imageData: Data, thumbnail: UIImage, location: CLLocation, placeName: String,
         initialComment: String, onClose: @escaping () -> Void, onPosted: @escaping () -> Void) {
        self.imageData = imageData
        self.thumbnail = thumbnail
        self.location = location
        self.placeName = placeName
        self.initialComment = initialComment
        self.onClose = onClose
        self.onPosted = onPosted
        _comment = State(initialValue: initialComment)
    }

    private var isFirstTime: Bool { myNickname.isEmpty || !agreedTerms }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(uiImage: thumbnail)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 13))
                        Text(placeName.isEmpty ? "現在地" : placeName).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("100日で消えます(👍で延命)").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    .foregroundStyle(.white.opacity(0.85))

                    // 位置ぼかし
                    VStack(alignment: .leading, spacing: 8) {
                        Text("位置の表示").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Picker("", selection: $blurLevel) {
                            Text("そのまま").tag(0)
                            Text("約300mぼかす").tag(1)
                            Text("市区レベル").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Text(blurDescription)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    // コメント
                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント(写真と一緒に表示・任意)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        TextField("例: 夕方の散歩道", text: $comment, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.black).tint(.blue)
                    }

                    if isFirstTime { firstTimeSection }

                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: post) {
                        Group {
                            if posting {
                                HStack(spacing: 10) { ProgressView().tint(.black); Text("投稿中…") }
                            } else {
                                Label("100日マップに残す", systemImage: "mappin.and.ellipse")
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(canPost ? Color.orange : Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(canPost ? .black : .white.opacity(0.5))
                    }
                    .disabled(!canPost || posting)
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("100日マップに投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("とじる") { Haptics.tick(); onClose() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear { nicknameInput = myNickname }
    }

    private var blurDescription: String {
        switch blurLevel {
        case 0: return "撮影地点がそのまま地図に表示されます。自宅など特定されたくない場所では「ぼかす」をおすすめします。"
        case 1: return "実際の場所から約300mずらした位置に表示されます(おすすめ)。"
        default: return "おおよその市区レベル(約1km単位)に丸めた位置に表示されます。"
        }
    }

    private var firstTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("はじめての投稿").font(.system(size: 14, weight: .heavy)).foregroundStyle(.orange)
            Text("ニックネーム(投稿者名として表示されます)")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            TextField("例: だいさく", text: $nicknameInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.black).tint(.blue)
            Text("・投稿した写真と位置(ぼかし加工後)・ニックネームは誰でも見られます\n・写真は100日後に地図から消えます\n・他人を傷つける投稿、権利を侵害する投稿、不適切な投稿は禁止です\n・通報された投稿は削除されます")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Toggle("ルールに同意する", isOn: $agreedTerms)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.6), lineWidth: 1.5))
    }

    private var canPost: Bool {
        agreedTerms && !(myNickname.isEmpty && nicknameInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func post() {
        Haptics.tick()
        posting = true
        errorMessage = nil
        let nick = nicknameInput.trimmingCharacters(in: .whitespaces)
        let coord = CloudSNSService.blurred(location.coordinate, level: blurLevel)
        Task {
            do {
                // 初回はニックネームをプロフィールに保存
                if myNickname.isEmpty, !nick.isEmpty {
                    var p = SNSProfile(); p.nickname = nick
                    try await CloudSNSService.saveMyProfile(p, avatar: nil)
                }
                try await CloudSNSService.post(imageData: imageData, thumbnail: thumbnail,
                                               coordinate: coord, blurLevel: blurLevel,
                                               placeName: placeName, comment: comment)
                await MainActor.run {
                    posting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onPosted()
                }
            } catch {
                await MainActor.run {
                    posting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
