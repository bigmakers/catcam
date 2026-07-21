import SwiftUI

/// 投稿詳細シート: 写真全体+作者+残り日数+フォロー/通報/ブロック。
struct PostDetailView: View {
    let post: SNSPost
    let onClose: () -> Void

    @State private var photo: UIImage?
    @State private var isFollowing = false
    @State private var likeCount = 0
    @State private var liked = false
    @State private var likeWorking = false
    @State private var comments: [SNSComment] = []
    @State private var commentText = ""
    @State private var sendingComment = false
    @State private var commentNickInput = ""
    @AppStorage("snsMyNickname") private var myNickname = ""
    @AppStorage("snsAgreedTerms") private var agreedTerms = false
    @State private var working = false
    @State private var showProfile = false
    @State private var showReportConfirm = false
    @State private var showBlockConfirm = false
    @State private var errorMessage: String?

    private var isMine: Bool { CloudSNSService.cachedUserID == post.authorID }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 写真
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
                            .aspectRatio(3.0/4.0, contentMode: .fit)
                        if let photo {
                            Image(uiImage: photo)
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            ProgressView().tint(.white)
                        }
                    }

                    // 作者行
                    Button {
                        Haptics.tick(); showProfile = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorNick.isEmpty ? "?" : post.authorNick)
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                Text(post.placeName)
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            if !isMine {
                                followButton
                            }
                        }
                    }

                    // 👍いいね
                    HStack(spacing: 12) {
                        Button {
                            Haptics.tick()
                            toggleLike()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("\(likeCount)")
                                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(liked ? Color.orange : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(liked ? .black : .white)
                        }
                        .disabled(likeWorking)
                        Text("👍1つで保存が7日のびる")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.9))
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left")
                            Text("\(comments.count)")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    }

                    // コメント・日付・残り日数
                    if !post.comment.isEmpty {
                        Text(post.comment)
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text(post.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Label("あと\(SNSPost.daysLeft(createdAt: post.createdAt, likeCount: likeCount))日", systemImage: "hourglass")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundStyle(.red)
                    }

                    commentsSection

                    if isMine {
                        Button(role: .destructive) {
                            deleteMyPost()
                        } label: {
                            Label("この投稿を削除", systemImage: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                        .disabled(working)
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("100日マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isMine {
                        Menu {
                            Button(role: .destructive) { showReportConfirm = true } label: {
                                Label("この投稿を通報", systemImage: "exclamationmark.bubble")
                            }
                            Button(role: .destructive) { showBlockConfirm = true } label: {
                                Label("この人をブロック", systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("とじる") { Haptics.tick(); onClose() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear {
            isFollowing = CloudSNSService.followingIDs.contains(post.authorID)
            commentNickInput = myNickname
            likeCount = post.likeCount
            Task {
                let img = try? await CloudSNSService.fetchPhoto(postID: post.id)
                await MainActor.run { photo = img }
            }
            Task {
                let state = await CloudSNSService.likeState(postID: post.id)
                await MainActor.run { likeCount = state.count; liked = state.mine }
            }
            Task {
                let list = (try? await CloudSNSService.comments(postID: post.id)) ?? []
                await MainActor.run { comments = list }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(userID: post.authorID, isMe: isMine) { showProfile = false }
        }
        .confirmationDialog("この投稿を通報しますか?", isPresented: $showReportConfirm, titleVisibility: .visible) {
            Button("不適切な内容として通報", role: .destructive) { reportPost() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("\(post.authorNick) さんをブロックしますか?\nこの人の投稿が表示されなくなります", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("ブロック", role: .destructive) { blockAuthor() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var followButton: some View {
        Button {
            Haptics.tick()
            toggleFollow()
        } label: {
            Text(isFollowing ? "フォロー中" : "フォロー")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isFollowing ? Color.white.opacity(0.15) : Color.orange, in: Capsule())
                .foregroundStyle(isFollowing ? .white : .black)
        }
        .disabled(working)
    }

    // MARK: - コメントUI

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("コメント(\(comments.count))")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))

            ForEach(comments) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.authorNick.isEmpty ? "?" : c.authorNick)
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.orange)
                        Text(c.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    }
                    Text(c.text)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if c.authorID == CloudSNSService.cachedUserID {
                        Button(role: .destructive) {
                            Task {
                                try? await CloudSNSService.deleteComment(id: c.id)
                                await MainActor.run { comments.removeAll { $0.id == c.id } }
                            }
                        } label: { Label("削除", systemImage: "trash") }
                    } else {
                        Button(role: .destructive) {
                            Task {
                                await CloudSNSService.reportComment(id: c.id)
                                await MainActor.run { comments.removeAll { $0.id == c.id } }
                            }
                        } label: { Label("通報して非表示", systemImage: "exclamationmark.bubble") }
                    }
                }
            }

            // 入力(初回はニックネーム+ルール同意)
            if myNickname.isEmpty || !agreedTerms {
                VStack(alignment: .leading, spacing: 8) {
                    if myNickname.isEmpty {
                        Text("ニックネーム(コメントに表示されます)")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        TextField("例: だいさく", text: $commentNickInput)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.black).tint(.blue)
                    }
                    if !agreedTerms {
                        Toggle("ルールに同意する(誹謗中傷・不適切な内容の禁止)", isOn: $agreedTerms)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.5), lineWidth: 1))
            }

            HStack(spacing: 8) {
                TextField("コメントを書く…", text: $commentText, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black).tint(.blue)
                Button {
                    Haptics.tick()
                    sendComment()
                } label: {
                    Group {
                        if sendingComment { ProgressView().tint(.black) }
                        else { Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .bold)) }
                    }
                    .frame(width: 42, height: 40)
                    .background(canSendComment ? Color.orange : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(canSendComment ? .black : .white.opacity(0.5))
                }
                .disabled(!canSendComment || sendingComment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSendComment: Bool {
        agreedTerms &&
        !commentText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !(myNickname.isEmpty && commentNickInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func sendComment() {
        let text = commentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sendingComment = true
        let nick = commentNickInput.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                if myNickname.isEmpty, !nick.isEmpty {
                    var p = SNSProfile(); p.nickname = nick
                    try await CloudSNSService.saveMyProfile(p, avatar: nil)
                }
                let c = try await CloudSNSService.addComment(postID: post.id, text: text)
                await MainActor.run {
                    comments.append(c)
                    commentText = ""
                    sendingComment = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    sendingComment = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func toggleLike() {
        likeWorking = true
        Task {
            do {
                if liked { try await CloudSNSService.unlike(postID: post.id) }
                else { try await CloudSNSService.like(postID: post.id) }
                await MainActor.run {
                    liked.toggle()
                    likeCount = max(0, likeCount + (liked ? 1 : -1))
                    likeWorking = false
                }
            } catch {
                await MainActor.run {
                    likeWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func toggleFollow() {
        working = true
        Task {
            do {
                if isFollowing { try await CloudSNSService.unfollow(post.authorID) }
                else { try await CloudSNSService.follow(post.authorID) }
                await MainActor.run { isFollowing.toggle(); working = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; working = false }
            }
        }
    }

    private func reportPost() {
        working = true
        Task {
            try? await CloudSNSService.report(postID: post.id, reason: "inappropriate")
            await MainActor.run { working = false; onClose() }
        }
    }

    private func blockAuthor() {
        working = true
        Task {
            await CloudSNSService.block(userID: post.authorID)
            await MainActor.run { working = false; onClose() }
        }
    }

    private func deleteMyPost() {
        working = true
        Task {
            try? await CloudSNSService.deletePost(id: post.id)
            await MainActor.run { working = false; onClose() }
        }
    }
}
