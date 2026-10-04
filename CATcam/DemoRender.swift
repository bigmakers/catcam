#if targetEnvironment(simulator)
import CoreLocation
import UIKit

/// シミュレータ専用の開発ハーネス。
/// 環境変数 DEMO_RENDER_DIR にホスト側ディレクトリを渡して起動すると、
/// その中の入力画像に「海外で撮った体」の焼き込み(逆ジオコーディング・地図・座標)を
/// 実パイプライン(PhotoRenderer)で適用して書き出す。ストア用デモ画像の生成に使う。
/// targetEnvironment(simulator) ガードにより実機・提出ビルドには一切含まれない。
enum DemoRender {
    struct Case {
        let file: String
        let out: String
        let lat: Double
        let lon: Double
        let sim: FilmSimulation
        let aspectW: CGFloat
        let aspectH: CGFloat
    }

    static func runIfRequested() async {
        guard let dir = ProcessInfo.processInfo.environment["DEMO_RENDER_DIR"] else { return }
        print("DEMO start dir=\(dir)")
        CountryShapes.shared.loadIfNeeded()

        let cases: [Case] = [
            .init(file: "in_nyc.jpg", out: "demo_newyork.jpg",
                  lat: 40.7580, lon: -73.9855, sim: .standard, aspectW: 1, aspectH: 1),
            .init(file: "in_sf.jpg", out: "demo_sanfrancisco.jpg",
                  lat: 37.7749, lon: -122.4194, sim: .chromeMetal, aspectW: 1, aspectH: 1),
            .init(file: "in_chi.jpg", out: "demo_chicago.jpg",
                  lat: 41.8781, lon: -87.6298, sim: .nostalgic, aspectW: 3, aspectH: 4),
        ]
        // OpenPOI 検証用: 天文館(鹿児島)で飲食スポットを取得して焼き込む
        if let img = UIImage(contentsOfFile: dir + "/in_nyc.jpg") {
            let loc = CLLocation(latitude: 31.5903, longitude: 130.5540)
            let placeName = await ImportProcessor.reverseGeocode(location: loc)
            let pois = await OpenPOIService.fetchNearby(location: loc, genre: .food, count: 10)
            print("DEMO openpoi hits=\(pois.count): \(pois.map(\.display))")
            let options = CaptureOptions(
                aspectW: 1, aspectH: 1,
                intensity: 0.4, coolness: 0, sim: .standard,
                commentFont: .minchoEditorial,
                infoOnRight: true,
                location: loc, placeName: placeName, date: Date(),
                mapZoom: 2.5, mapEnabled: true,
                comment: "", nearbyPlaces: pois.map(\.display),
                showPlaceName: true, showCoordinates: false, showDateTime: false)
            if let data = await Task.detached(operation: { PhotoRenderer.shared.render(image: img, options: options) }).value {
                try? data.write(to: URL(fileURLWithPath: dir + "/demo_tenmonkan_poi.jpg"))
                print("DEMO wrote demo_tenmonkan_poi.jpg")
            }
        }

        for c in cases {
            guard let img = UIImage(contentsOfFile: dir + "/" + c.file) else {
                print("DEMO 入力なし: \(c.file)"); continue
            }
            let loc = CLLocation(latitude: c.lat, longitude: c.lon)
            let placeName = await ImportProcessor.reverseGeocode(location: loc)
            let options = CaptureOptions(
                aspectW: c.aspectW, aspectH: c.aspectH,
                intensity: 0.5, coolness: 0, sim: c.sim,
                commentFont: .minchoEditorial,
                infoOnRight: true,
                location: loc, placeName: placeName, date: Date(),
                mapZoom: 2.5, mapEnabled: true,
                comment: "", nearbyPlaces: [],
                showPlaceName: true, showCoordinates: true, showDateTime: false)
            let data = await Task.detached { PhotoRenderer.shared.render(image: img, options: options) }.value
            if let data {
                try? data.write(to: URL(fileURLWithPath: dir + "/" + c.out))
                print("DEMO wrote \(c.out) place=\(placeName)")
            } else {
                print("DEMO render 失敗: \(c.file)")
            }
        }
        print("DEMO done")
    }
}
#endif
