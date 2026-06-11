import CoreLocation
import Foundation

/// バンドル同梱の countries.min.json を読み込み、座標から国を引くためのストア。
/// 1.4MB の JSON を扱うため Codable ではなく JSONSerialization で読む。
final class CountryShapes {
    static let shared = CountryShapes()

    struct BBox {
        var minLon, minLat, maxLon, maxLat: Double

        var area: Double { (maxLon - minLon) * (maxLat - minLat) }

        func contains(lon: Double, lat: Double) -> Bool {
            lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat
        }

        func intersects(_ other: BBox) -> Bool {
            minLon <= other.maxLon && maxLon >= other.minLon &&
                minLat <= other.maxLat && maxLat >= other.minLat
        }
    }

    struct Country {
        let iso: String
        let name: String
        let bbox: BBox
        let polys: [[SIMD2<Double>]]
    }

    private(set) var countries: [Country] = []
    private(set) var isLoaded = false

    private let lock = NSLock()

    /// バンドルの countries.min.json を一度だけ読み込む。スレッドセーフ・二重ロード防止。
    /// 失敗時は空配列のまま黙って続行する。
    func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "countries", withExtension: "min.json")
            ?? Bundle.main.url(forResource: "countries.min", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCountries = root["countries"] as? [[String: Any]] else {
            return
        }

        var result: [Country] = []
        result.reserveCapacity(rawCountries.count)

        for entry in rawCountries {
            guard let iso = entry["iso"] as? String,
                  let name = entry["name"] as? String,
                  let bboxArray = entry["bbox"] as? [Double], bboxArray.count == 4,
                  let rawPolys = entry["polys"] as? [[[Double]]] else {
                continue
            }
            let bbox = BBox(minLon: bboxArray[0], minLat: bboxArray[1],
                            maxLon: bboxArray[2], maxLat: bboxArray[3])
            let polys: [[SIMD2<Double>]] = rawPolys.map { ring in
                ring.compactMap { point in
                    point.count == 2 ? SIMD2<Double>(point[0], point[1]) : nil
                }
            }
            result.append(Country(iso: iso, name: name, bbox: bbox, polys: polys))
        }

        countries = result
    }

    /// 座標を内包する国。bbox プリフィルタ → 外輪に対する偶奇判定。
    /// 複数ヒット時は bbox 面積が最小の国を返す(飛び地内包対策)。
    func country(containing coord: CLLocationCoordinate2D) -> Country? {
        let lon = coord.longitude, lat = coord.latitude
        var best: Country?
        for country in countries {
            guard country.bbox.contains(lon: lon, lat: lat) else { continue }
            guard country.polys.contains(where: { ringContains($0, lon: lon, lat: lat) }) else { continue }
            if best == nil || country.bbox.area < best!.bbox.area {
                best = country
            }
        }
        return best
    }

    /// bbox 中心との距離(経度は cos(lat) 補正)が最小の国。
    func nearestCountry(to coord: CLLocationCoordinate2D) -> Country? {
        let lon = coord.longitude, lat = coord.latitude
        let cosLat = cos(lat * .pi / 180)
        var best: Country?
        var bestDist = Double.greatestFiniteMagnitude
        for country in countries {
            let cLon = (country.bbox.minLon + country.bbox.maxLon) / 2
            let cLat = (country.bbox.minLat + country.bbox.maxLat) / 2
            let dLon = (cLon - lon) * cosLat
            let dLat = cLat - lat
            let dist = dLon * dLon + dLat * dLat
            if dist < bestDist {
                bestDist = dist
                best = country
            }
        }
        return best
    }

    /// 指定 bbox に交差する全ての国。
    func countries(intersecting bbox: BBox) -> [Country] {
        countries.filter { $0.bbox.intersects(bbox) }
    }

    // MARK: - レイキャスティング(偶奇判定)

    private func ringContains(_ ring: [SIMD2<Double>], lon: Double, lat: Double) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].x, yi = ring[i].y
            let xj = ring[j].x, yj = ring[j].y
            if (yi > lat) != (yj > lat) {
                let slope = (xj - xi) / (yj - yi)
                let crossLon = xi + (lat - yi) * slope
                if lon < crossLon { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
