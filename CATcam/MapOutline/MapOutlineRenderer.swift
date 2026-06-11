import CoreLocation
import UIKit

/// 国境アウトライン + 現在地マーカーを透明背景の正方形画像として焼き込む。
/// Passage 風の白い国境線オーバーレイ。純粋関数でメインスレッド要件なし。
enum MapOutlineRenderer {

    /// 緯度を ±85° にクランプしたメルカトル Y 座標。
    private static func mercatorY(_ latDeg: Double) -> Double {
        let lat = min(max(latDeg, -85), 85) * .pi / 180
        return log(tan(.pi / 4 + lat / 2))
    }

    /// 国境アウトライン + 現在地マーカーを透明背景の正方形 UIImage で返す。
    /// zoom > 1 で現在地中心にズームする(1=国全体フィット, 最大 8 倍)。
    static func image(for coordinate: CLLocationCoordinate2D, sidePx: CGFloat, zoom: Double = 1) -> UIImage? {
        let shapes = CountryShapes.shared
        shapes.loadIfNeeded()

        guard let base = shapes.country(containing: coordinate)
            ?? shapes.nearestCountry(to: coordinate) else {
            return nil
        }

        var xLo: Double, xHi: Double, yMin: Double, yMax: Double, span: Double

        // ビューポート: 基準国の bbox を現在地を含むよう拡張 → 8% パディング
        var minLon = min(base.bbox.minLon, coordinate.longitude)
        var maxLon = max(base.bbox.maxLon, coordinate.longitude)
        var minLat = min(base.bbox.minLat, coordinate.latitude)
        var maxLat = max(base.bbox.maxLat, coordinate.latitude)

        let padLon = (maxLon - minLon) * 0.08
        let padLat = (maxLat - minLat) * 0.08
        minLon -= padLon; maxLon += padLon
        minLat -= padLat; maxLat += padLat

        // メルカトル投影空間で正方形にフィット(短辺側を中央寄せで広げる)
        let xMin = minLon * .pi / 180
        let xMax = maxLon * .pi / 180
        var yMinF = mercatorY(minLat)
        var yMaxF = mercatorY(maxLat)

        var spanX = xMax - xMin
        var spanY = yMaxF - yMinF
        guard spanX > 0 || spanY > 0 else { return nil }

        var xLoF = xMin, xHiF = xMax
        if spanX > spanY {
            let extra = (spanX - spanY) / 2
            yMinF -= extra; yMaxF += extra
        } else if spanY > spanX {
            let extra = (spanY - spanX) / 2
            xLoF -= extra; xHiF += extra
        }
        spanX = xHiF - xLoF
        spanY = yMaxF - yMinF
        var s = max(spanX, spanY, 1e-9)

        // ズーム: 国全体フィットのスパン S を z で割り、現在地を中心に取り直す
        let z = min(max(zoom, 1), 8)
        if z > 1.001 {
            s /= z
            let cx = coordinate.longitude * .pi / 180
            let cy = mercatorY(coordinate.latitude)
            xLoF = cx - s / 2
            xHiF = cx + s / 2
            yMinF = cy - s / 2
            yMaxF = cy + s / 2
        }
        xLo = xLoF; xHi = xHiF; yMin = yMinF; yMax = yMaxF; span = s

        // 投影座標 → ピクセル(Y は上下反転)
        func project(_ lon: Double, _ lat: Double) -> CGPoint {
            let x = (lon * .pi / 180 - xLo) / span * Double(sidePx)
            let y = (1 - (mercatorY(lat) - yMin) / span) * Double(sidePx)
            return CGPoint(x: x, y: y)
        }

        // ビューポート bbox に交差する全国を取得。
        // 正方形化で広がった範囲を逆メルカトルで緯度経度に戻してから判定する。
        func inverseMercatorLat(_ y: Double) -> Double {
            (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
        }
        let viewport = CountryShapes.BBox(minLon: xLo * 180 / .pi,
                                          minLat: inverseMercatorLat(yMin),
                                          maxLon: xHi * 180 / .pi,
                                          maxLat: inverseMercatorLat(yMax))
        let visible = shapes.countries(intersecting: viewport)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: sidePx, height: sidePx), format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            cg.setLineWidth(sidePx * 0.007)

            // 黒の soft shadow で写真上でも視認できるように
            cg.setShadow(offset: .zero, blur: sidePx * 0.02,
                         color: UIColor.black.withAlphaComponent(0.5).cgColor)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)

            for country in visible {
                for ring in country.polys {
                    guard ring.count >= 2 else { continue }
                    var started = false
                    var prevLon = 0.0
                    for point in ring {
                        let lon = point.x, lat = point.y
                        // 経度の不連続(±180跨ぎ)対策: 線を切る
                        if started, abs(lon - prevLon) > 180 {
                            cg.strokePath()
                            started = false
                        }
                        let p = project(lon, lat)
                        if started {
                            cg.addLine(to: p)
                        } else {
                            cg.move(to: p)
                            started = true
                        }
                        prevLon = lon
                    }
                    if started { cg.strokePath() }
                }
            }

            // 現在地マーカー: 白い外リング + オレンジ塗り円 + 中心の白点
            cg.setShadow(offset: .zero, blur: sidePx * 0.02,
                         color: UIColor.black.withAlphaComponent(0.5).cgColor)
            let center = project(coordinate.longitude, coordinate.latitude)
            let r = sidePx * 0.05
            let outer = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: outer)

            cg.setShadow(offset: .zero, blur: 0, color: nil)
            let ri = r * 0.72
            let inner = CGRect(x: center.x - ri, y: center.y - ri, width: ri * 2, height: ri * 2)
            cg.setFillColor(UIColor(red: 1.0, green: 0.35, blue: 0.18, alpha: 1).cgColor)
            cg.fillEllipse(in: inner)

            let rd = r * 0.26
            let dot = CGRect(x: center.x - rd, y: center.y - rd, width: rd * 2, height: rd * 2)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: dot)
        }
    }
}
