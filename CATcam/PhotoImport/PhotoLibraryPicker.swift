import CoreLocation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// PHPickerViewController をラップした UIViewControllerRepresentable。
/// 選択完了時に `(UIImage, CLLocation?, Date?)` をコールバックで返す。
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage, CLLocation?, Date?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        // assetIdentifier を取得するために photoLibrary ベースの設定が必要
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (UIImage, CLLocation?, Date?) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping (UIImage, CLLocation?, Date?) -> Void,
             onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        /// 完了/キャンセルは PhotoKit のバックグラウンドコールバックから呼ばれるため、
        /// SwiftUI 状態を触る呼び出し側のためにメインスレッドへ集約する。
        private func finish(_ image: UIImage, _ location: CLLocation?, _ date: Date?) {
            DispatchQueue.main.async { self.onPicked(image, location, date) }
        }

        private func cancel() {
            DispatchQueue.main.async { self.onCancel() }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 手動 dismiss は行わない(シート内シートで外側ごと閉じる罠)。
            // 表示側の SwiftUI @State(isPresented)で閉じること。
            guard let result = results.first else {
                cancel()
                return
            }
            loadAsset(from: result)
        }

        // MARK: - Asset loading

        private func loadAsset(from result: PHPickerResult) {
            // まず PHAsset 経由でフル解像度 + メタデータを試みる
            if let assetId = result.assetIdentifier {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                    if status == .authorized || status == .limited {
                        self?.fetchFromPHAsset(identifier: assetId, fallback: result)
                    } else {
                        // 権限なし → itemProvider 経由 (位置は取れないかもしれない)
                        self?.loadViaItemProvider(result: result)
                    }
                }
            } else {
                loadViaItemProvider(result: result)
            }
        }

        private func fetchFromPHAsset(identifier: String, fallback: PHPickerResult) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = assets.firstObject else {
                loadViaItemProvider(result: fallback)
                return
            }

            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: requestOptions
            ) { [weak self] data, _, orientation, _ in
                guard let self, let data else {
                    self?.loadViaItemProvider(result: fallback)
                    return
                }
                // 位置・日時はまず PHAsset から。欠けていれば実データの EXIF で補完する。
                var location = asset.location
                var date = asset.creationDate
                if location == nil || date == nil,
                   let src = CGImageSourceCreateWithData(data as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                    if location == nil { location = Self.extractGPS(from: props) }
                    if date == nil { date = Self.extractDate(from: props) }
                }
                if let image = UIImage(data: data)?.normalized() {
                    self.finish(image, location, date)
                } else {
                    self.loadViaItemProvider(result: fallback)
                }
            }
        }

        // MARK: - itemProvider 経由のフォールバック (EXIF から位置・日時を取得)

        private func loadViaItemProvider(result: PHPickerResult) {
            let provider = result.itemProvider
            // typeIdentifier は public.image を優先し、なければ最初のもの
            let typeId = provider.registeredTypeIdentifiers.first(where: {
                $0 == "public.jpeg" || $0 == "public.png" || $0 == "public.heic"
            }) ?? provider.registeredTypeIdentifiers.first ?? "public.image"

            provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, error in
                guard let self, let url, error == nil else {
                    // ファイル表現が取れない場合は UIImage だけ試みる
                    self?.loadUIImageOnly(result: result)
                    return
                }

                // EXIF を ImageIO で読む
                var location: CLLocation? = nil
                var date: Date? = nil
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                    location = Self.extractGPS(from: props)
                    date = Self.extractDate(from: props)
                }

                if let image = UIImage(contentsOfFile: url.path)?.normalized() {
                    self.finish(image, location, date)
                } else {
                    self.loadUIImageOnly(result: result)
                }
            }
        }

        private func loadUIImageOnly(result: PHPickerResult) {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let self, let image = obj as? UIImage else { return }
                self.finish(image.normalized(), nil, nil)
            }
        }

        // MARK: - EXIF GPS 解析

        private static func extractGPS(from props: [CFString: Any]) -> CLLocation? {
            guard let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
                  let latVal = gps[kCGImagePropertyGPSLatitude] as? CLLocationDegrees,
                  let lonVal = gps[kCGImagePropertyGPSLongitude] as? CLLocationDegrees else {
                return nil
            }
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            let lat = latRef == "S" ? -latVal : latVal
            let lon = lonRef == "W" ? -lonVal : lonVal
            guard lat != 0 || lon != 0 else { return nil }
            return CLLocation(latitude: lat, longitude: lon)
        }

        private static func extractDate(from props: [CFString: Any]) -> Date? {
            // EXIF の DateTimeOriginal を解析
            guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                  let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
                return nil
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: dateStr)
        }
    }
}

// MARK: - UIImage orientation normalize

extension UIImage {
    /// EXIF orientation を画素に焼き込んで正立した UIImage を返す。
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
