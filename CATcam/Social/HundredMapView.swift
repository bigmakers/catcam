import SwiftUI
import MapKit
import CoreLocation

/// 100日マップ: 投稿写真が地図上に並ぶメイン画面。
struct HundredMapView: View {
    let myLocation: CLLocation?
    let onClose: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var posts: [SNSPost] = []
    @State private var mode = 0                    // 0=みんな 1=フォロー中
    @State private var loading = false
    @State private var selectedPost: SNSPost?
    @State private var showMyProfile = false
    @State private var errorMessage: String?
    @State private var queryTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(posts) { post in
                    Annotation("", coordinate: post.coordinate) {
                        PinThumbView(post: post)
                            .onTapGesture {
                                Haptics.tick()
                                selectedPost = post
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                scheduleQuery()
            }
            .ignoresSafeArea()

            VStack {
                topBar
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.top, 6)
                }
                Spacer()
                if posts.isEmpty && !loading {
                    emptyHint
                }
            }
        }
        .onAppear {
            if let loc = myLocation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            }
            Task { await CloudSNSService.syncFollowing() }
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post) {
                selectedPost = nil
                scheduleQuery()   // 通報/ブロック/削除の反映
            }
        }
        .sheet(isPresented: $showMyProfile) {
            if let me = CloudSNSService.cachedUserID {
                ProfileView(userID: me, isMe: true) { showMyProfile = false }
            } else {
                VStack(spacing: 14) {
                    Text("プロフィールを作るには、まず1枚投稿してください")
                        .font(.system(size: 14)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("とじる") { showMyProfile = false }
                }
                .padding(30)
                .presentationDetents([.height(180)])
                .preferredColorScheme(.dark)
            }
        }
    }

    // MARK: - 上部バー

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { Haptics.tick(); onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Picker("", selection: $mode) {
                Text("みんな").tag(0)
                Text("フォロー中").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .onChange(of: mode) { _, _ in scheduleQuery() }

            if loading { ProgressView().tint(.white) }

            Spacer()

            Button { Haptics.tick(); showMyProfile = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var emptyHint: some View {
        Text(mode == 0 ? "このあたりにはまだ写真がありません。\nこの街の最初の1枚を残しましょう!"
                       : "フォロー中の投稿はまだありません。\n気になる人をフォローしてみましょう")
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 40)
    }

    // MARK: - クエリ(デバウンス)

    private func scheduleQuery() {
        queryTask?.cancel()
        queryTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await runQuery()
        }
    }

    @MainActor
    private func runQuery() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            if mode == 1 {
                posts = try await CloudSNSService.queryFollowedPosts()
            } else if let region = visibleRegion {
                let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                let radius = max(1000.0, min(region.span.latitudeDelta * 111_000 / 2 * 1.4, 300_000.0))
                posts = try await CloudSNSService.queryPosts(center: center, radiusMeters: radius)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - サムネイルピン

/// 地図上の写真ピン(白フチのサムネイル+尖り)。
struct PinThumbView: View {
    let post: SNSPost
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.gray)
                }
            }
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 7)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .onAppear {
            guard image == nil, let url = post.thumbFileURL else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let img = UIImage(contentsOfFile: url.path)
                DispatchQueue.main.async { image = img }
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
