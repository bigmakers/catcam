import SwiftUI

/// プロフィール表示/編集。他SNSへのリンク(最大3つ)を置ける=外部SNSへの誘導口。
struct ProfileView: View {
    let userID: String
    let isMe: Bool
    let onClose: () -> Void

    @State private var profile = SNSProfile()
    @State private var avatar: UIImage?
    @State private var newAvatar: UIImage?
    @State private var posts: [SNSPost] = []
    @State private var loading = true
    @State private var saving = false
    @State private var isFollowing = false
    @State private var showAvatarPicker = false
    @State private var errorMessage: String?
    @State private var selectedPost: SNSPost?

    private let cols = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // アバター+名前
                    VStack(spacing: 10) {
                        Button {
                            if isMe { Haptics.tick(); showAvatarPicker = true }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                avatarView
                                if isMe {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.orange)
                                        .background(Color.black, in: Circle())
                                }
                            }
                        }
                        .disabled(!isMe)

                        if isMe {
                            Text("ニックネーム(投稿に表示される名前)")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                            TextField("ニックネーム", text: $profile.nickname)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 18, weight: .bold))
                                .textFieldStyle(.plain)
                                .padding(.vertical, 8).padding(.horizontal, 14)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.black).tint(.blue)
                                .frame(maxWidth: 240)
                            Text("ひとこと(自己紹介・任意)")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                                .padding(.top, 6)
                            TextField("例: 散歩しながら撮ってます", text: $profile.bio, axis: .vertical)
                                .lineLimit(1...2)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 13))
                                .textFieldStyle(.plain)
                                .padding(.vertical, 8).padding(.horizontal, 14)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.black).tint(.blue)
                        } else {
                            Text(profile.nickname.isEmpty ? "?" : profile.nickname)
                                .font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                            if !profile.bio.isEmpty {
                                Text(profile.bio)
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }

                    // SNSリンク
                    if isMe {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SNSリンク(最大3つ・プロフィールに表示)")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                            linkField("https://instagram.com/...", text: $profile.link1)
                            linkField("https://x.com/...", text: $profile.link2)
                            linkField("その他のURL", text: $profile.link3)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    } else if !profile.links.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(profile.links, id: \.self) { link in
                                Button {
                                    openLink(link)
                                } label: {
                                    HStack {
                                        Image(systemName: linkIcon(link))
                                        Text(linkLabel(link)).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                                }
                            }
                        }
                    }

                    // フォロー / 保存
                    if isMe {
                        Button(action: save) {
                            Group {
                                if saving { ProgressView().tint(.black) }
                                else { Text("プロフィールを保存").font(.system(size: 15, weight: .bold)) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.black)
                        }
                        .disabled(saving || profile.nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            Haptics.tick(); toggleFollow()
                        } label: {
                            Text(isFollowing ? "フォロー中" : "フォローする")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(isFollowing ? Color.white.opacity(0.15) : Color.orange, in: Capsule())
                                .foregroundStyle(isFollowing ? .white : .black)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundStyle(.red)
                    }

                    // 投稿グリッド
                    VStack(alignment: .leading, spacing: 8) {
                        Text("100日マップの投稿(\(posts.count))")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        if posts.isEmpty && !loading {
                            Text("まだ投稿がありません")
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: cols, spacing: 6) {
                                ForEach(posts) { post in
                                    Button { selectedPost = post } label: {
                                        PostThumbCell(post: post)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isMe ? "マイプロフィール" : "プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("とじる") { Haptics.tick(); onClose() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear(perform: load)
        .sheet(isPresented: $showAvatarPicker) {
            PhotoLibraryPicker { image, _, _ in
                showAvatarPicker = false
                newAvatar = image
                avatar = image
            } onCancel: { showAvatarPicker = false }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post) { selectedPost = nil }
        }
    }

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(8)
            }
        }
        .frame(width: 84, height: 84)
        .background(Color.white.opacity(0.1))
        .clipShape(Circle())
    }

    private func linkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.black).tint(.blue)
    }

    private func linkIcon(_ link: String) -> String {
        let l = link.lowercased()
        if l.contains("instagram") { return "camera" }
        if l.contains("x.com") || l.contains("twitter") { return "bubble.left" }
        if l.contains("youtube") { return "play.rectangle" }
        return "globe"
    }

    private func linkLabel(_ link: String) -> String {
        link.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    private func openLink(_ link: String) {
        var s = link
        if !s.hasPrefix("http") { s = "https://" + s }
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }

    private func load() {
        Task {
            let p = try? await CloudSNSService.fetchProfile(userID: userID)
            let userPosts = (try? await CloudSNSService.queryUserPosts(authorID: userID)) ?? []
            await MainActor.run {
                if let p {
                    profile = p
                    if let url = p.avatarFileURL { avatar = UIImage(contentsOfFile: url.path) }
                }
                posts = userPosts
                isFollowing = CloudSNSService.followingIDs.contains(userID)
                loading = false
            }
        }
    }

    private func save() {
        Haptics.tick()
        saving = true
        errorMessage = nil
        Task {
            do {
                try await CloudSNSService.saveMyProfile(profile, avatar: newAvatar)
                await MainActor.run {
                    saving = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onClose()
                }
            } catch {
                await MainActor.run { saving = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private func toggleFollow() {
        Task {
            do {
                if isFollowing { try await CloudSNSService.unfollow(userID) }
                else { try await CloudSNSService.follow(userID) }
                await MainActor.run { isFollowing.toggle() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

/// プロフィール内の投稿サムネセル。
struct PostThumbCell: View {
    let post: SNSPost
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("\(post.daysLeft)日")
                .font(.system(size: 9, weight: .heavy))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.orange)
                .padding(4)
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
