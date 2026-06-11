import Photos
import CoreLocation
import UIKit

enum PhotoSaver {
    /// EXIF GPS 入りの JPEG データをフォトライブラリに保存する。
    static func save(_ data: Data,
                     location: CLLocation?,
                     completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                request.location = location
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
        }
    }
}
