import UIKit
import CloudKit
import CoreLocation

// MARK: - モデル

/// 100日マップの1投稿。
struct SNSPost: Identifiable, Equatable {
    let id: String                 // CKRecord recordName
    let authorID: String
    let authorNick: String
    let coordinate: CLLocationCoordinate2D
    let placeName: String
    let comment: String
    let createdAt: Date
    let thumbFileURL: URL?         // CKAssetの一時ファイル(取得済みのみ)
    /// いいね数(地図クエリ時に一括取得。寿命計算に使う)。
    var likeCount: Int = 0

    /// 寿命(日): 基本100日+いいね1つで+7日(上限200日)。
    static func lifespanDays(likeCount: Int) -> Int {
        min(200, 100 + 7 * likeCount)
    }

    static func daysLeft(createdAt: Date, likeCount: Int) -> Int {
        let elapsed = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        return max(0, lifespanDays(likeCount: likeCount) - elapsed)
    }

    /// あと何日で消えるか(いいねによる延命込み)。
    var daysLeft: Int { Self.daysLeft(createdAt: createdAt, likeCount: likeCount) }

    static func == (l: SNSPost, r: SNSPost) -> Bool { l.id == r.id }
}

/// プロフィール。
struct SNSProfile {
    var nickname: String = ""
    var bio: String = ""
    var link1: String = ""
    var link2: String = ""
    var link3: String = ""
    var avatarFileURL: URL? = nil

    var links: [String] { [link1, link2, link3].filter { !$0.isEmpty } }
}

/// 投稿へのコメント。
struct SNSComment: Identifiable, Equatable {
    let id: String
    let postID: String
    let authorID: String
    let authorNick: String
    let text: String
    let createdAt: Date
}

/// エラー(日本語メッセージ)。
enum SNSError: LocalizedError {
    case notSignedIn
    case notFound
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "iCloudにサインインしていません。設定アプリでiCloudにサインインすると投稿・フォローできます。"
        case .notFound: return "見つかりませんでした。"
        case .network(let e): return "通信に失敗しました: " + e.localizedDescription
        }
    }
}

// MARK: - サービス

/// 100日マップのCloudKit通信(パブリックDB)。SerenDPのCloudRollServiceと同方式。
enum CloudSNSService {
    static let container = CKContainer(identifier: "iCloud.com.harasaki.CATcam")
    static var db: CKDatabase { container.publicCloudDatabase }
    static let baseLifespanDays = 100.0
    static let maxLifespanDays = 200.0   // いいね延命の上限

    /// クエリの下限は最大寿命ぶん遡る(実際の期限はいいね数で個別判定)。
    private static var cutoff: Date { Date(timeIntervalSinceNow: -maxLifespanDays * 86400) }

    // MARK: 自分のID・ローカル状態

    /// 自分のユーザーID(iCloudアカウント由来。キャッシュあり)。
    static func myUserID() async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: "snsUserID") { return cached }
        guard (try? await container.accountStatus()) == .available else { throw SNSError.notSignedIn }
        let rid = try await container.userRecordID()
        UserDefaults.standard.set(rid.recordName, forKey: "snsUserID")
        return rid.recordName
    }

    static var cachedUserID: String? { UserDefaults.standard.string(forKey: "snsUserID") }

    /// ブロック済みユーザー / 通報して非表示にした投稿(ローカル)。
    static var blockedUsers: [String] {
        get { UserDefaults.standard.stringArray(forKey: "snsBlockedUsers") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "snsBlockedUsers") }
    }
    static var hiddenPosts: [String] {
        get { UserDefaults.standard.stringArray(forKey: "snsHiddenPosts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "snsHiddenPosts") }
    }
    static var hiddenComments: [String] {
        get { UserDefaults.standard.stringArray(forKey: "snsHiddenComments") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "snsHiddenComments") }
    }
    static var followingIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "snsFollowing") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "snsFollowing") }
    }

    // MARK: プロフィール

    static func fetchProfile(userID: String) async throws -> SNSProfile {
        let record: CKRecord
        do {
            record = try await db.record(for: CKRecord.ID(recordName: "profile-\(userID)"))
        } catch let e as CKError where e.code == .unknownItem {
            return SNSProfile()
        } catch { throw SNSError.network(error) }
        var p = SNSProfile()
        p.nickname = record["nickname"] as? String ?? ""
        p.bio = record["bio"] as? String ?? ""
        p.link1 = record["link1"] as? String ?? ""
        p.link2 = record["link2"] as? String ?? ""
        p.link3 = record["link3"] as? String ?? ""
        p.avatarFileURL = (record["avatar"] as? CKAsset)?.fileURL
        return p
    }

    static func saveMyProfile(_ p: SNSProfile, avatar: UIImage?) async throws {
        let me = try await myUserID()
        let rid = CKRecord.ID(recordName: "profile-\(me)")
        let record: CKRecord
        if let existing = try? await db.record(for: rid) {
            record = existing
        } else {
            record = CKRecord(recordType: "Profile", recordID: rid)
        }
        record["nickname"] = p.nickname
        record["bio"] = p.bio
        record["link1"] = p.link1
        record["link2"] = p.link2
        record["link3"] = p.link3
        var tempURL: URL?
        if let avatar, let data = downscaled(avatar, maxSide: 200)?.jpegData(compressionQuality: 0.8) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: url)
            record["avatar"] = CKAsset(fileURL: url)
            tempURL = url
        }
        defer { if let tempURL { try? FileManager.default.removeItem(at: tempURL) } }
        do { _ = try await db.modifyRecords(saving: [record], deleting: []) } catch { throw SNSError.network(error) }
        UserDefaults.standard.set(p.nickname, forKey: "snsMyNickname")
    }

    static var myNickname: String { UserDefaults.standard.string(forKey: "snsMyNickname") ?? "" }

    // MARK: 投稿

    /// 写真を100日マップに投稿する。coordinate はぼかし加工済みのものを渡すこと。
    static func post(imageData: Data, thumbnail: UIImage, coordinate: CLLocationCoordinate2D,
                     blurLevel: Int, placeName: String, comment: String) async throws {
        let me = try await myUserID()
        let record = CKRecord(recordType: "Post", recordID: CKRecord.ID(recordName: "post-\(UUID().uuidString)"))
        var tempURLs: [URL] = []
        defer { tempURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        // 本体(長辺1280)とサムネ(長辺400)
        if let img = UIImage(data: imageData),
           let photoData = downscaled(img, maxSide: 1280)?.jpegData(compressionQuality: 0.8) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try photoData.write(to: url); tempURLs.append(url)
            record["photo"] = CKAsset(fileURL: url)
        }
        if let thumbData = downscaled(thumbnail, maxSide: 400)?.jpegData(compressionQuality: 0.72) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try thumbData.write(to: url); tempURLs.append(url)
            record["thumb"] = CKAsset(fileURL: url)
        }
        record["location"] = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        record["blurLevel"] = blurLevel
        record["placeName"] = placeName
        record["comment"] = comment
        record["authorID"] = me
        record["authorNick"] = myNickname
        record["createdAt"] = Date()
        do { _ = try await db.save(record) } catch { throw SNSError.network(error) }
    }

    static func deletePost(id: String) async throws {
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id)) }
        catch let e as CKError where e.code == .unknownItem { }
        catch { throw SNSError.network(error) }
    }

    // MARK: クエリ

    private static let queryKeys = ["thumb", "location", "placeName", "comment", "authorID", "authorNick", "createdAt"]

    /// 地図の中心+半径で投稿を検索(100日以内のみ)。
    static func queryPosts(center: CLLocation, radiusMeters: Double) async throws -> [SNSPost] {
        let pred = NSPredicate(format: "distanceToLocation:fromLocation:(location, %@) < %f AND createdAt > %@",
                               center, radiusMeters, cutoff as NSDate)
        return try await runPostQuery(pred)
    }

    /// フォロー中の投稿(全域)。
    static func queryFollowedPosts() async throws -> [SNSPost] {
        let ids = followingIDs
        guard !ids.isEmpty else { return [] }
        let pred = NSPredicate(format: "authorID IN %@ AND createdAt > %@", ids, cutoff as NSDate)
        return try await runPostQuery(pred)
    }

    /// あるユーザーの投稿。
    static func queryUserPosts(authorID: String) async throws -> [SNSPost] {
        let pred = NSPredicate(format: "authorID == %@ AND createdAt > %@", authorID, cutoff as NSDate)
        return try await runPostQuery(pred)
    }

    private static func runPostQuery(_ predicate: NSPredicate) async throws -> [SNSPost] {
        let query = CKQuery(recordType: "Post", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let (results, _) = try await db.records(matching: query, desiredKeys: queryKeys, resultsLimit: 100)
            let blocked = Set(blockedUsers), hidden = Set(hiddenPosts)
            var posts = results.compactMap { (rid, result) -> SNSPost? in
                guard let record = try? result.get() else { return nil }
                guard let loc = record["location"] as? CLLocation,
                      let created = record["createdAt"] as? Date else { return nil }
                let author = record["authorID"] as? String ?? ""
                guard !blocked.contains(author), !hidden.contains(rid.recordName) else { return nil }
                return SNSPost(id: rid.recordName,
                               authorID: author,
                               authorNick: record["authorNick"] as? String ?? "?",
                               coordinate: loc.coordinate,
                               placeName: record["placeName"] as? String ?? "",
                               comment: record["comment"] as? String ?? "",
                               createdAt: created,
                               thumbFileURL: (record["thumb"] as? CKAsset)?.fileURL)
            }
            // いいね数を一括取得して延命を反映し、寿命切れを除外
            let counts = await batchLikeCounts(postIDs: posts.map(\.id))
            for i in posts.indices { posts[i].likeCount = counts[posts[i].id] ?? 0 }
            return posts.filter { $0.daysLeft > 0 }
        } catch { throw SNSError.network(error) }
    }

    /// 投稿の本体写真を取得(詳細表示用)。
    static func fetchPhoto(postID: String) async throws -> UIImage? {
        do {
            let record = try await db.record(for: CKRecord.ID(recordName: postID))
            guard let url = (record["photo"] as? CKAsset)?.fileURL else { return nil }
            return UIImage(contentsOfFile: url.path)
        } catch { throw SNSError.network(error) }
    }

    // MARK: フォロー

    static func follow(_ targetID: String) async throws {
        let me = try await myUserID()
        guard me != targetID else { return }
        let record = CKRecord(recordType: "Follow", recordID: CKRecord.ID(recordName: "follow-\(me)-\(targetID)"))
        record["follower"] = me
        record["target"] = targetID
        do { _ = try await db.modifyRecords(saving: [record], deleting: []) } catch { throw SNSError.network(error) }
        var ids = followingIDs
        if !ids.contains(targetID) { ids.append(targetID); followingIDs = ids }
    }

    static func unfollow(_ targetID: String) async throws {
        let me = try await myUserID()
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: "follow-\(me)-\(targetID)")) }
        catch let e as CKError where e.code == .unknownItem { }
        catch { throw SNSError.network(error) }
        followingIDs = followingIDs.filter { $0 != targetID }
    }

    /// サーバーからフォロー一覧を取り直してローカルへ同期。
    static func syncFollowing() async {
        guard let me = try? await myUserID() else { return }
        let pred = NSPredicate(format: "follower == %@", me)
        let query = CKQuery(recordType: "Follow", predicate: pred)
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return }
        let ids = results.compactMap { try? $0.1.get()["target"] as? String }
        followingIDs = ids
    }

    // MARK: いいね

    /// 複数投稿のいいね数を一括取得(カーソルで最大~2000件までページング)。
    static func batchLikeCounts(postIDs: [String]) async -> [String: Int] {
        guard !postIDs.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        let pred = NSPredicate(format: "postID IN %@", postIDs)
        let query = CKQuery(recordType: "Like", predicate: pred)
        do {
            var (results, cursor) = try await db.records(matching: query,
                                                         desiredKeys: ["postID"], resultsLimit: 400)
            var fetched = results.count
            while true {
                for (_, result) in results {
                    if let record = try? result.get(), let pid = record["postID"] as? String {
                        counts[pid, default: 0] += 1
                    }
                }
                guard let c = cursor, fetched < 2000 else { break }
                (results, cursor) = try await db.records(continuingMatchFrom: c, resultsLimit: 400)
                fetched += results.count
            }
        } catch { }
        return counts
    }

    /// いいねの状態(件数と自分が押したか)。
    static func likeState(postID: String) async -> (count: Int, mine: Bool) {
        var count = 0, mine = false
        let pred = NSPredicate(format: "postID == %@", postID)
        let query = CKQuery(recordType: "Like", predicate: pred)
        if let (results, _) = try? await db.records(matching: query, desiredKeys: [], resultsLimit: 500) {
            count = results.count
        }
        if let me = try? await myUserID() {
            mine = (try? await db.record(for: CKRecord.ID(recordName: "like-\(me)-\(postID)"))) != nil
        }
        return (count, mine)
    }

    static func like(postID: String) async throws {
        let me = try await myUserID()
        let record = CKRecord(recordType: "Like", recordID: CKRecord.ID(recordName: "like-\(me)-\(postID)"))
        record["postID"] = postID
        record["userID"] = me
        do { _ = try await db.modifyRecords(saving: [record], deleting: []) } catch { throw SNSError.network(error) }
    }

    static func unlike(postID: String) async throws {
        let me = try await myUserID()
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: "like-\(me)-\(postID)")) }
        catch let e as CKError where e.code == .unknownItem { }
        catch { throw SNSError.network(error) }
    }

    // MARK: コメント

    static func comments(postID: String) async throws -> [SNSComment] {
        let pred = NSPredicate(format: "postID == %@", postID)
        let query = CKQuery(recordType: "PostComment", predicate: pred)
        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 100)
            let blocked = Set(blockedUsers), hidden = Set(hiddenComments)
            return results.compactMap { (rid, result) -> SNSComment? in
                guard let record = try? result.get() else { return nil }
                let author = record["authorID"] as? String ?? ""
                guard !blocked.contains(author), !hidden.contains(rid.recordName) else { return nil }
                return SNSComment(id: rid.recordName,
                                  postID: postID,
                                  authorID: author,
                                  authorNick: record["authorNick"] as? String ?? "?",
                                  text: record["text"] as? String ?? "",
                                  createdAt: record["createdAt"] as? Date ?? Date())
            }
            .sorted { $0.createdAt < $1.createdAt }
        } catch { throw SNSError.network(error) }
    }

    static func addComment(postID: String, text: String) async throws -> SNSComment {
        let me = try await myUserID()
        let record = CKRecord(recordType: "PostComment", recordID: CKRecord.ID(recordName: "comment-\(UUID().uuidString)"))
        record["postID"] = postID
        record["authorID"] = me
        record["authorNick"] = myNickname
        record["text"] = text
        record["createdAt"] = Date()
        do { _ = try await db.save(record) } catch { throw SNSError.network(error) }
        return SNSComment(id: record.recordID.recordName, postID: postID, authorID: me,
                          authorNick: myNickname, text: text, createdAt: Date())
    }

    static func deleteComment(id: String) async throws {
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id)) }
        catch let e as CKError where e.code == .unknownItem { }
        catch { throw SNSError.network(error) }
    }

    /// コメントを通報して非表示にする。
    static func reportComment(id: String) async {
        let record = CKRecord(recordType: "PostReport")
        record["postID"] = id
        record["reason"] = "comment"
        record["reporterID"] = (try? await myUserID()) ?? "anonymous"
        _ = try? await db.save(record)
        var h = hiddenComments; h.append(id); hiddenComments = h
    }

    // MARK: 通報・ブロック

    static func report(postID: String, reason: String) async throws {
        let record = CKRecord(recordType: "PostReport")
        record["postID"] = postID
        record["reason"] = reason
        record["reporterID"] = (try? await myUserID()) ?? "anonymous"
        do { _ = try await db.save(record) } catch { throw SNSError.network(error) }
        var h = hiddenPosts; h.append(postID); hiddenPosts = h
    }

    static func block(userID: String) async {
        var b = blockedUsers
        if !b.contains(userID) { b.append(userID); blockedUsers = b }
        if let me = try? await myUserID() {
            let record = CKRecord(recordType: "Block", recordID: CKRecord.ID(recordName: "block-\(me)-\(userID)"))
            record["blocker"] = me
            record["target"] = userID
            _ = try? await db.modifyRecords(saving: [record], deleting: [])
        }
    }

    // MARK: 位置ぼかし

    /// blurLevel: 0=そのまま / 1=約300mランダムオフセット / 2=市区レベル(約1.1kmグリッドに丸め)
    static func blurred(_ coordinate: CLLocationCoordinate2D, level: Int) -> CLLocationCoordinate2D {
        switch level {
        case 1:
            let meters = 150.0 + Double.random(in: 0...150)
            let bearing = Double.random(in: 0..<(2 * .pi))
            let dLat = (meters * cos(bearing)) / 111_000.0
            let dLon = (meters * sin(bearing)) / (111_000.0 * cos(coordinate.latitude * .pi / 180))
            return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
        case 2:
            return CLLocationCoordinate2D(latitude: (coordinate.latitude * 100).rounded() / 100,
                                          longitude: (coordinate.longitude * 100).rounded() / 100)
        default:
            return coordinate
        }
    }

    // MARK: 内部

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
