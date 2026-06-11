import MapKit

/// 最寄りスポット検索のジャンル。Picker と @AppStorage("poiGenre") に対応。
enum POIGenre: String, CaseIterable, Identifiable {
    case none, all, food, cafe, sightseeing, transport

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "なし"
        case .all: return "すべて"
        case .food: return "飲食店"
        case .cafe: return "カフェ"
        case .sightseeing: return "観光"
        case .transport: return "駅・交通"
        }
    }

    /// MKLocalPointsOfInterestRequest に渡すカテゴリ。
    /// none→nil(検索しない)、all→nil(フィルタなし)。
    var categories: [MKPointOfInterestCategory]? {
        switch self {
        case .none, .all:
            return nil
        case .food:
            return [.restaurant, .cafe, .bakery, .foodMarket]
        case .cafe:
            return [.cafe, .bakery]
        case .sightseeing:
            return [.museum, .park, .aquarium, .zoo, .amusementPark, .beach, .stadium, .theater]
        case .transport:
            return [.publicTransport, .airport]
        }
    }
}

/// 焼き込み用の最寄りスポット 1 件(名前 + 距離)。
struct NearbyPlace {
    let name: String
    let distance: CLLocationDistance

    /// "名前 120m" / 1km 以上は "名前 1.2km"
    var display: String {
        if distance >= 1000 {
            return String(format: "%@ %.1fkm", name, distance / 1000)
        }
        return String(format: "%@ %.0fm", name, distance)
    }
}

/// 撮影地点周辺の POI を MapKit で検索し、距離順に保持する。
final class NearbyPlacesManager: ObservableObject {
    @Published private(set) var places: [NearbyPlace] = []

    /// 前回取得した位置・条件(重複取得のスキップ判定用)
    private var lastFetchLocation: CLLocation?
    private var lastGenre: POIGenre?
    private var lastCount: Int?

    /// 進行中の検索(次の update でキャンセルする)
    private var search: MKLocalSearch?

    /// 指定位置・ジャンル・件数で周辺スポットを更新する。
    /// genre == .none は無効化。前回取得位置から 200m 未満かつ条件不変ならスキップ。
    func update(for location: CLLocation, genre: POIGenre, count: Int) {
        guard genre != .none else {
            search?.cancel()
            search = nil
            lastFetchLocation = nil
            lastGenre = POIGenre.none
            lastCount = count
            if !places.isEmpty { places = [] }
            return
        }

        // 近距離かつ条件不変なら再取得しない
        if let last = lastFetchLocation,
           location.distance(from: last) < 200,
           lastGenre == genre,
           lastCount == count {
            return
        }

        lastFetchLocation = location
        lastGenre = genre
        lastCount = count

        let region = MKCoordinateRegion(center: location.coordinate,
                                        latitudinalMeters: 500,
                                        longitudinalMeters: 500)
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        if let categories = genre.categories {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }

        // 進行中の検索を打ち切ってから新規検索
        search?.cancel()
        let search = MKLocalSearch(request: request)
        self.search = search
        search.start { [weak self] response, _ in
            guard let self else { return }
            let items = response?.mapItems ?? []
            let nearby = items.compactMap { item -> NearbyPlace? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let distance = item.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                return NearbyPlace(name: name, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            let top = Array(nearby.prefix(count))
            DispatchQueue.main.async {
                self.places = top
            }
        }
    }
}
