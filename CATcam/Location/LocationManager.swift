import CoreLocation
import Foundation

final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    /// 「Selangor, Malaysia」のような表示用地名
    @Published var placeName: String = ""
    @Published var authorized = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorized = true
            manager.startUpdatingLocation()
        default:
            authorized = false
        }
    }

    private func reverseGeocodeIfNeeded(_ location: CLLocation) {
        // 200m 以上動いたときだけジオコーディングし直す
        if let last = lastGeocodedLocation, location.distance(from: last) < 200 { return }
        lastGeocodedLocation = location

        // 地名は端末ロケールに依らずアルファベット表記にする
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            // 市区町村 → 都道府県/州 → 国 の順。重複(都市州など)は除く
            let city = placemark.locality ?? placemark.subAdministrativeArea
            var parts: [String] = []
            for part in [city, placemark.administrativeArea, placemark.country] {
                if let part, parts.last != part, !parts.contains(part) {
                    parts.append(part)
                }
            }
            let name = parts.joined(separator: ", ")
            DispatchQueue.main.async {
                self?.placeName = name
            }
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            authorized = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorized = false
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        reverseGeocodeIfNeeded(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension CLLocationCoordinate2D {
    /// 「2.7456°N, 101.6889°E」形式
    var displayString: String {
        let latRef = latitude >= 0 ? "N" : "S"
        let lonRef = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f°%@, %.4f°%@",
                      abs(latitude), latRef, abs(longitude), lonRef)
    }
}
