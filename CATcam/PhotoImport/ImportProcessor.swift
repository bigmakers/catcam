import CoreLocation
import MapKit
import Photos
import UIKit

/// フォトライブラリから選んだ写真に CATcam の加工を適用して保存する。
enum ImportProcessor {

    /// メインの処理エントリポイント。
    /// - Parameters:
    ///   - image: 選択・正立済みの UIImage
    ///   - location: PHAsset / EXIF から取得した撮影位置 (nil 可)
    ///   - date: PHAsset / EXIF から取得した撮影日時 (nil 可)
    ///   - polaroid: ポラロイドモード
    ///   - intensity: ノワール強度 0–1
    ///   - mapZoom: 地図ズーム倍率
    ///   - mapEnabled: 地図オーバーレイ有効か
    ///   - comment: 焼き込みコメント
    ///   - poiGenre: 周辺 POI ジャンル
    ///   - poiCount: 周辺 POI 表示件数
    ///   - showPlaceName: 地名を焼き込むか
    ///   - showCoordinates: 座標を焼き込むか
    ///   - showDateTime: 日時を焼き込むか
    ///   - infoOnRight: 焼き込み情報を右端に寄せるか
    /// - Returns: 保存後のサムネイル用 UIImage（失敗時 nil）
    static func process(
        image: UIImage,
        location: CLLocation?,
        date: Date?,
        polaroid: Bool,
        intensity: Double,
        mapZoom: Double,
        mapEnabled: Bool,
        comment: String,
        poiGenre: POIGenre,
        poiCount: Int,
        showPlaceName: Bool = true,
        showCoordinates: Bool = true,
        showDateTime: Bool = true,
        infoOnRight: Bool = false
    ) async -> UIImage? {
        let resolvedDate = date ?? Date()

        // location がある場合のみ逆ジオコーディング・POI 検索を行う
        var placeName = ""
        var nearbyPlaces: [String] = []
        var effectiveMapEnabled = false

        if let loc = location {
            effectiveMapEnabled = mapEnabled
            // 逆ジオコーディング
            placeName = await reverseGeocode(location: loc)
            // POI 検索
            if poiGenre != .none {
                nearbyPlaces = await fetchNearbyPlaces(
                    location: loc, genre: poiGenre, count: poiCount)
            }
        }

        let options = CaptureOptions(
            polaroid: polaroid,
            intensity: intensity,
            location: location,
            placeName: placeName,
            date: resolvedDate,
            mapZoom: mapZoom,
            mapEnabled: effectiveMapEnabled,
            comment: comment,
            nearbyPlaces: nearbyPlaces,
            showPlaceName: showPlaceName,
            showCoordinates: showCoordinates,
            showDateTime: showDateTime,
            infoOnRight: infoOnRight
        )

        // レンダリング(バックグラウンドスレッドで)
        let renderTask = Task.detached(priority: .userInitiated) {
            PhotoRenderer.shared.render(image: image, options: options)
        }
        guard let data = await renderTask.value else {
            return nil
        }

        // フォトライブラリへ保存
        let saved = await withCheckedContinuation { continuation in
            PhotoSaver.save(data, location: location) { success in
                continuation.resume(returning: success)
            }
        }

        guard saved else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 逆ジオコーディング (LocationManager と同一ロジック)

    private static func reverseGeocode(location: CLLocation) async -> String {
        await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "en_US")
            ) { placemarks, _ in
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: "")
                    return
                }
                let city = placemark.locality ?? placemark.subAdministrativeArea
                var parts: [String] = []
                for part in [city, placemark.administrativeArea, placemark.country] {
                    if let part, parts.last != part, !parts.contains(part) {
                        parts.append(part)
                    }
                }
                continuation.resume(returning: parts.joined(separator: ", "))
            }
        }
    }

    // MARK: - 周辺 POI 検索 (NearbyPlacesManager と同一ロジック)

    private static func fetchNearbyPlaces(
        location: CLLocation,
        genre: POIGenre,
        count: Int
    ) async -> [String] {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500)
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        if let categories = genre.categories {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let nearby = response.mapItems.compactMap { item -> NearbyPlace? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let distance = item.placemark.location?.distance(from: location)
                    ?? .greatestFiniteMagnitude
                return NearbyPlace(name: name, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            return Array(nearby.prefix(count)).map(\.display)
        } catch {
            return []
        }
    }
}
