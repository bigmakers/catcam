import CoreLocation
import Foundation

/// バンドル同梱の states.min.json(admin-1: 都道府県/州)を読み込み、
/// 座標から該当する州・都道府県を引くためのストア。CountryShapes の admin-1 版。
/// 国境だけより細かい単位の地図アウトラインを描くために使う。
final class StateShapes {
    static let shared = StateShapes()

    /// 1 つの州・都道府県(外輪リングのみ保持)。
    struct Region {
        let name: String
        let admin: String           // 所属国名
        let bbox: CountryShapes.BBox
        let polys: [[SIMD2<Double>]]
    }

    private(set) var regions: [Region] = []
    private(set) var isLoaded = false
    private let lock = NSLock()

    /// states.min.json を一度だけ読み込む。スレッドセーフ・失敗時は空のまま続行。
    func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "states", withExtension: "min.json")
            ?? Bundle.main.url(forResource: "states.min", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["states"] as? [[String: Any]] else {
            return
        }

        var result: [Region] = []
        result.reserveCapacity(raw.count)
        for entry in raw {
            guard let name = entry["name"] as? String,
                  let bboxArray = entry["bbox"] as? [Double], bboxArray.count == 4,
                  let rawPolys = entry["polys"] as? [[[Double]]] else {
                continue
            }
            let admin = entry["admin"] as? String ?? ""
            let bbox = CountryShapes.BBox(minLon: bboxArray[0], minLat: bboxArray[1],
                                          maxLon: bboxArray[2], maxLat: bboxArray[3])
            let polys: [[SIMD2<Double>]] = rawPolys.map { ring in
                ring.compactMap { p in p.count == 2 ? SIMD2<Double>(p[0], p[1]) : nil }
            }
            result.append(Region(name: name, admin: admin, bbox: bbox, polys: polys))
        }
        regions = result
    }

    /// 座標を内包する州・都道府県。複数ヒット時は bbox 面積最小を返す。
    func region(containing coord: CLLocationCoordinate2D) -> Region? {
        let lon = coord.longitude, lat = coord.latitude
        var best: Region?
        for r in regions {
            guard r.bbox.contains(lon: lon, lat: lat) else { continue }
            guard r.polys.contains(where: { ringContains($0, lon: lon, lat: lat) }) else { continue }
            if best == nil || r.bbox.area < best!.bbox.area {
                best = r
            }
        }
        return best
    }

    /// bbox 中心との距離(経度は cos(lat) 補正)が最小の州・都道府県。
    func nearestRegion(to coord: CLLocationCoordinate2D) -> Region? {
        let lon = coord.longitude, lat = coord.latitude
        let cosLat = cos(lat * .pi / 180)
        var best: Region?
        var bestDist = Double.greatestFiniteMagnitude
        for r in regions {
            let cLon = (r.bbox.minLon + r.bbox.maxLon) / 2
            let cLat = (r.bbox.minLat + r.bbox.maxLat) / 2
            let dLon = (cLon - lon) * cosLat
            let dLat = cLat - lat
            let dist = dLon * dLon + dLat * dLat
            if dist < bestDist { bestDist = dist; best = r }
        }
        return best
    }

    /// 指定 bbox に交差する全ての州・都道府県。
    func regions(intersecting bbox: CountryShapes.BBox) -> [Region] {
        regions.filter { $0.bbox.intersects(bbox) }
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
