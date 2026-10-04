import Foundation
import ImageIO
import UIKit

/// 猫ログの1件。撮影した写真(加工済みJPEG)と、いつ・どこで撮ったか。
struct NekoLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    /// NekoLog ディレクトリ内のファイル名
    let filename: String
    let date: Date
    /// 撮影地の地名(位置情報オフなら空)
    let place: String
}

/// アプリ内ギャラリー「猫ログ」の保存庫。
///
/// 撮影・取り込みで保存した一枚を Documents/NekoLog/ にも複製して記録する。
/// **端末内のみ**で完結し、外部送信は一切ない(100日マップの後継だが CloudKit は使わない)。
/// 一覧は index.json で管理する(新しい順)。
final class NekoLogStore: ObservableObject {
    static let shared = NekoLogStore()

    @Published private(set) var entries: [NekoLogEntry] = []

    private let directory: URL
    private let indexURL: URL
    private let io = DispatchQueue(label: "catcam.nekolog")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("NekoLog", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 追加・削除

    /// 加工済み JPEG データを猫ログへ追加する。
    func add(data: Data, date: Date, place: String) {
        let entry = NekoLogEntry(id: UUID(),
                                 filename: "neko-\(Int(date.timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).jpg",
                                 date: date,
                                 place: place)
        io.async {
            do {
                try data.write(to: self.directory.appendingPathComponent(entry.filename))
            } catch {
                return
            }
            DispatchQueue.main.async {
                self.entries.insert(entry, at: 0)
                self.persist()
            }
        }
    }

    func delete(_ entry: NekoLogEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        let url = imageURL(for: entry)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    func imageURL(for entry: NekoLogEntry) -> URL {
        directory.appendingPathComponent(entry.filename)
    }

    // MARK: - サムネイル

    /// グリッド用の縮小画像を ImageIO で読む(12MP をそのまま並べるとメモリが飛ぶため)。
    func thumbnail(for entry: NekoLogEntry, maxPixel: CGFloat) -> UIImage? {
        let url = imageURL(for: entry)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * UIScreen.main.scale,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([NekoLogEntry].self, from: data) else { return }
        // 実ファイルが消えているエントリは除く
        entries = list.filter {
            FileManager.default.fileExists(atPath: imageURL(for: $0).path)
        }
    }

    private func persist() {
        let list = entries
        io.async {
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: self.indexURL)
            }
        }
    }
}
