import AVFoundation
import CoreImage
import CoreLocation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct CaptureOptions {
    var polaroid: Bool
    var intensity: Double
    var location: CLLocation?
    var placeName: String
    var date: Date
    var mapZoom: Double = 1
    /// 地図表示オン/オフ
    var mapEnabled: Bool = true
    /// 見出し下に焼き込むコメント(空なら描画しない)
    var comment: String = ""
    /// 近くのスポット(display 済みの "名前 120m" 文字列)
    var nearbyPlaces: [String] = []
    /// 撮影瞬間に検出した猫の頭数(0 のとき焼き込まない)
    var catCount: Int = 0
}

/// 撮影した写真にフィルタ・オーバーレイ・ポラロイド枠を適用し、
/// EXIF GPS 付きの JPEG データを生成する。
final class PhotoRenderer {
    static let shared = PhotoRenderer()

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()

    func render(photo: AVCapturePhoto, options: CaptureOptions) -> Data? {
        guard let data = photo.fileDataRepresentation(),
              var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }

        image = RetroFilmFilter.shared.apply(to: image, intensity: options.intensity)
        image = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y))

        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        let filtered = UIImage(cgImage: cgImage)

        let composed = options.polaroid
            ? composePolaroid(filtered, options: options)
            : composeOverlay(filtered, options: options)

        return encodeJPEG(composed, options: options)
    }

    // MARK: - 通常モード: 写真の左上に Passage 風のオーバーレイ

    private func composeOverlay(_ image: UIImage, options: CaptureOptions) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))

            let u = size.width / 1000.0
            let pad = 44 * u
            var y = pad

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 10 * u
            shadow.shadowOffset = CGSize(width: 0, height: 2 * u)

            func draw(_ text: String, font: UIFont, color: UIColor) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .shadow: shadow,
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                attributed.draw(at: CGPoint(x: pad, y: y))
                y += attributed.size().height + 8 * u
            }

            // 空港コード風の大見出し(地名の先頭3文字)
            if let code = Self.placeCode(from: options.placeName) {
                draw(code,
                     font: .systemFont(ofSize: 84 * u, weight: .heavy),
                     color: .white)
            }
            // コメント(見出しの直下)
            if !options.comment.isEmpty {
                draw(options.comment,
                     font: .systemFont(ofSize: 44 * u, weight: .heavy),
                     color: .white)
            }
            // 猫の頭数(地名の前。「ここで猫を N 匹見つけた」記録)
            if options.catCount > 0 {
                draw("🐾 \(options.catCount)匹",
                     font: .systemFont(ofSize: 34 * u, weight: .heavy),
                     color: .white)
            }
            if !options.placeName.isEmpty {
                draw("📍 " + options.placeName,
                     font: .systemFont(ofSize: 36 * u, weight: .bold),
                     color: .white)
            }
            if let coordinate = options.location?.coordinate {
                draw(coordinate.displayString,
                     font: .monospacedSystemFont(ofSize: 30 * u, weight: .semibold),
                     color: .white)
            }
            draw(Self.displayDateFormatter.string(from: options.date),
                 font: .systemFont(ofSize: 30 * u, weight: .medium),
                 color: UIColor.white.withAlphaComponent(0.92))

            // 近くのスポット(日時の下)
            for place in options.nearbyPlaces {
                draw("・" + place,
                     font: .systemFont(ofSize: 26 * u, weight: .semibold),
                     color: UIColor.white.withAlphaComponent(0.9))
            }

            // 左上情報の下に国境アウトライン地図を焼き込む(オフ時はスキップ)
            if options.mapEnabled, let coordinate = options.location?.coordinate {
                let mapSide = size.width * 0.36
                if let map = MapOutlineRenderer.image(for: coordinate, sidePx: mapSide, zoom: options.mapZoom) {
                    map.draw(in: CGRect(x: pad, y: y + 12 * u,
                                        width: mapSide, height: mapSide))
                }
            }
        }
    }

    // MARK: - ポラロイドモード: 真四角クロップ + 白フチ + 下帯キャプション

    private func composePolaroid(_ image: UIImage, options: CaptureOptions) -> UIImage {
        let squared = centerCropSquare(image)
        let side = squared.size.width

        let margin = side * 0.06
        let bottomBand = side * 0.24
        let canvasSize = CGSize(width: side + margin * 2,
                                height: side + margin + bottomBand)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            UIColor(white: 0.97, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            squared.draw(in: CGRect(x: margin, y: margin, width: side, height: side))

            let u = side / 1000.0
            let mapPad = side * 0.05
            var poiY = margin + mapPad

            // 写真領域(白フチ内の正方形)左上に国境アウトライン地図を焼き込む(オフ時はスキップ)
            if options.mapEnabled, let coordinate = options.location?.coordinate {
                let mapSide = side * 0.34
                if let map = MapOutlineRenderer.image(for: coordinate, sidePx: mapSide, zoom: options.mapZoom) {
                    let origin = CGPoint(x: margin + mapPad,
                                         y: margin + mapPad)
                    map.draw(in: CGRect(origin: origin,
                                        size: CGSize(width: mapSide, height: mapSide)))
                    poiY = origin.y + mapSide + 12 * u
                }
            }

            // 近くのスポットを写真上(地図の下)に焼き込む。白文字 + 影で視認性を確保
            if !options.nearbyPlaces.isEmpty {
                let poiShadow = NSShadow()
                poiShadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
                poiShadow.shadowBlurRadius = 8 * u
                poiShadow.shadowOffset = CGSize(width: 0, height: 2 * u)
                let poiFont = UIFont.systemFont(ofSize: 26 * u, weight: .semibold)
                for place in options.nearbyPlaces.prefix(6) {
                    let attributed = NSAttributedString(string: "・" + place, attributes: [
                        .font: poiFont,
                        .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                        .shadow: poiShadow,
                    ])
                    attributed.draw(at: CGPoint(x: margin + mapPad, y: poiY))
                    poiY += attributed.size().height + 6 * u
                }
            }
            let textX = margin + 8 * u
            var y = margin + side + 30 * u
            let ink = UIColor(white: 0.22, alpha: 1)
            let hasComment = !options.comment.isEmpty

            // コメント有無で左列のフォント・行間を切り替える(帯 240u に収めるため)
            let codeSize: CGFloat = hasComment ? 56 * u : 64 * u
            let placeSize: CGFloat = hasComment ? 30 * u : 36 * u
            let subtitleSize: CGFloat = hasComment ? 24 * u : 27 * u
            let leftLineGap: CGFloat = hasComment ? 8 * u : 10 * u

            func draw(_ text: String, font: UIFont, color: UIColor) {
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: color,
                ])
                attributed.draw(at: CGPoint(x: textX, y: y))
                y += attributed.size().height + leftLineGap
            }

            // 空港コード風の大見出し(地名の先頭3文字)
            if let code = Self.placeCode(from: options.placeName) {
                draw(code,
                     font: .systemFont(ofSize: codeSize, weight: .heavy),
                     color: ink)
            }
            // コメント(見出しの直下)
            if hasComment {
                draw(options.comment,
                     font: .systemFont(ofSize: 32 * u, weight: .bold),
                     color: ink)
            }
            if !options.placeName.isEmpty {
                draw("📍 " + options.placeName,
                     font: .systemFont(ofSize: placeSize, weight: .bold),
                     color: ink)
            }
            // 猫の頭数(地名の直後。下帯に収めるため place より小さめ)
            if options.catCount > 0 {
                draw("🐾 \(options.catCount)匹",
                     font: .systemFont(ofSize: subtitleSize * 1.05, weight: .heavy),
                     color: ink)
            }
            var subtitle = Self.displayDateFormatter.string(from: options.date)
            if let coordinate = options.location?.coordinate {
                subtitle += "   " + coordinate.displayString
            }
            draw(subtitle,
                 font: .monospacedSystemFont(ofSize: subtitleSize, weight: .regular),
                 color: ink.withAlphaComponent(0.65))
        }
    }

    /// 地名の先頭要素(市区町村)から英字のみ抜き出し、先頭3文字を大文字化した
    /// 空港コード風の見出し(例: "Setagaya, Tokyo, Japan" → "SET")
    static func placeCode(from placeName: String) -> String? {
        guard let first = placeName.split(separator: ",").first else { return nil }
        let letters = first.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }
        return String(letters.prefix(3)).uppercased()
    }

    private func centerCropSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let rect = CGRect(x: (width - side) / 2,
                          y: (height - side) / 2,
                          width: side, height: side)
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    // MARK: - EXIF GPS 付き JPEG エンコード

    private func encodeJPEG(_ image: UIImage, options: CaptureOptions) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }

        let exifDate = Self.exifDateFormatter.string(from: options.date)
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: exifDate,
                kCGImagePropertyExifDateTimeDigitized: exifDate,
            ],
        ]
        if let location = options.location {
            properties[kCGImagePropertyGPSDictionary] = gpsDictionary(for: location)
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func gpsDictionary(for location: CLLocation) -> [CFString: Any] {
        let coordinate = location.coordinate
        var gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef: coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSTimeStamp: Self.gpsTimeFormatter.string(from: location.timestamp),
            kCGImagePropertyGPSDateStamp: Self.gpsDateFormatter.string(from: location.timestamp),
        ]
        if location.verticalAccuracy > 0 {
            gps[kCGImagePropertyGPSAltitude] = abs(location.altitude)
            gps[kCGImagePropertyGPSAltitudeRef] = location.altitude >= 0 ? 0 : 1
        }
        return gps
    }

    // MARK: - Formatters

    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    private static let gpsTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let gpsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
