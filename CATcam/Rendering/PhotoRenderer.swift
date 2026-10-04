import AVFoundation
import CoreImage
import CoreLocation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct CaptureOptions {
    var aspectW: CGFloat = 9
    var aspectH: CGFloat = 16
    /// ポラロイド額装モード(真四角クロップ+白フチ+下帯キャプション)。true のとき aspectW/H は使わない。
    var polaroid: Bool = false
    var intensity: Double
    var coolness: Double = 0
    var sim: FilmSimulation = .standard
    var commentFont: CommentFont = .minchoEditorial
    /// 出力画像を端末の向きに合わせて回す量(時計回りの90°単位)。横持ち撮影で横向き出力に。
    var quarterTurns: Int = 0
    /// 焼き込み情報を右端に寄せるか(false=左端)。
    var infoOnRight: Bool = false
    var location: CLLocation?
    var placeName: String
    var date: Date
    var mapZoom: Double = 1
    /// 地図表示オン/オフ
    var mapEnabled: Bool = false
    /// 見出し下に焼き込むコメント(空なら描画しない)
    var comment: String = ""
    /// 近くのスポット(display 済みの "名前 120m" 文字列)
    var nearbyPlaces: [String] = []
    /// 地名(コード見出し + 📍行)を焼き込むか
    var showPlaceName: Bool = false
    /// 座標を焼き込むか
    var showCoordinates: Bool = false
    /// 日時を焼き込むか
    var showDateTime: Bool = false
    /// フロントカメラで撮影したか(iOS26で静止画が横向きに届く問題の補正用)
    var isFront: Bool = false
}

/// 撮影した写真にフィルタ・オーバーレイを適用し、
/// EXIF GPS 付きの JPEG データを生成する。
final class PhotoRenderer {
    static let shared = PhotoRenderer()

    private let ciContext: CIContext = {
        // 作業色空間を sRGB に固定する(既定のリニアだとフィルムの階調カーブが
        // 意図と別物になり、黒が浮いて暗部が色被りする)。最終出力も sRGB JPEG なので
        // ここを sRGB にしても失うものはなく、プレビューと保存が一致する。
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()

    func render(photo: AVCapturePhoto, options: CaptureOptions) -> Data? {
        guard let data = photo.fileDataRepresentation(),
              var ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }

        // フロントは iOS26 で videoRotationAngle が効かず、EXIF 正立後もまだ横向きで届く。
        // 実機検証: .leftMirrored=正立だが左右反転 / .left=上下逆さま / .right=正立かつ非反転。
        if options.isFront, ciImage.extent.width > ciImage.extent.height {
            ciImage = ciImage.oriented(.right)
            ciImage = ciImage.transformed(by: CGAffineTransform(
                translationX: -ciImage.extent.origin.x,
                y: -ciImage.extent.origin.y))
        }

        ciImage = FilmSimulationFilter.shared.apply(to: ciImage, sim: options.sim, intensity: options.intensity, coolness: options.coolness)
        ciImage = ciImage.transformed(by: CGAffineTransform(
            translationX: -ciImage.extent.origin.x,
            y: -ciImage.extent.origin.y))

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let filtered = UIImage(cgImage: cgImage)
        return renderUIImage(filtered, options: options)
    }

    /// フォトライブラリから選んだ UIImage に同じ加工を適用する。
    func render(image: UIImage, options: CaptureOptions) -> Data? {
        // 呼び出し側(PhotoLibraryPicker.normalized())で正立済みの前提。
        guard let cgInput = image.cgImage else { return nil }
        var ciImage = CIImage(cgImage: cgInput)

        ciImage = FilmSimulationFilter.shared.apply(to: ciImage, sim: options.sim, intensity: options.intensity, coolness: options.coolness)
        ciImage = ciImage.transformed(by: CGAffineTransform(
            translationX: -ciImage.extent.origin.x,
            y: -ciImage.extent.origin.y))

        guard let cgFiltered = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let filtered = UIImage(cgImage: cgFiltered)
        return renderUIImage(filtered, options: options)
    }

    /// UIImage に対してオーバーレイ合成 → JPEG エンコードを行う共通本体。
    private func renderUIImage(_ filtered: UIImage, options: CaptureOptions) -> Data? {
        let composed = options.polaroid
            ? composePolaroid(filtered, options: options)
            : composeOverlay(filtered, options: options)
        return encodeJPEG(composed, options: options)
    }

    // MARK: - 通常モード: 写真の左上に Passage 風のオーバーレイ

    private func composeOverlay(_ rawImage: UIImage, options: CaptureOptions) -> UIImage {
        // 1) 縦の作業空間で選択アスペクト比にクロップ → 2) 端末の向きに合わせて画像ごと回転。
        //    これで横持ち撮影は横向き出力になり、情報は最終画像の左上に普通に描けば消えない。
        let cropped = centerCrop(rawImage, aspectW: options.aspectW, aspectH: options.aspectH)
        let image = rotatedImage(cropped, quarterTurnsCW: options.quarterTurns)
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))

            // 情報サイズは短辺基準にして向きに依らず一定にする
            let u = min(size.width, size.height) / 1000.0
            let pad = 44 * u
            var y = pad

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 10 * u
            shadow.shadowOffset = CGSize(width: 0, height: 2 * u)

            // 左端=pad、右端=幅 - pad - 要素幅。
            func startX(_ w: CGFloat) -> CGFloat {
                options.infoOnRight ? size.width - pad - w : pad
            }
            func draw(_ text: String, font: UIFont, color: UIColor) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .shadow: shadow,
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                attributed.draw(at: CGPoint(x: startX(attributed.size().width), y: y))
                y += attributed.size().height + 8 * u
            }

            // 空港コード風の大見出し(地名の先頭3文字)
            if options.showPlaceName, let code = Self.placeCode(from: options.placeName) {
                draw(code,
                     font: .systemFont(ofSize: 84 * u, weight: .heavy),
                     color: .white)
            }
            if options.showPlaceName && !options.placeName.isEmpty {
                draw("📍 " + options.placeName,
                     font: .systemFont(ofSize: 36 * u, weight: .bold),
                     color: .white)
            }
            if options.showCoordinates, let coordinate = options.location?.coordinate {
                draw(coordinate.displayString,
                     font: .monospacedSystemFont(ofSize: 30 * u, weight: .semibold),
                     color: .white)
            }
            if options.showDateTime {
                draw(Self.displayDateFormatter.string(from: options.date),
                     font: .systemFont(ofSize: 30 * u, weight: .medium),
                     color: UIColor.white.withAlphaComponent(0.92))
            }

            // 近くのスポット(日時の下)
            for place in options.nearbyPlaces {
                draw("・" + place,
                     font: .systemFont(ofSize: 26 * u, weight: .semibold),
                     color: UIColor.white.withAlphaComponent(0.9))
            }

            // 左上情報の下に国境アウトライン地図を焼き込む(オフ時はスキップ)
            if options.mapEnabled, let coordinate = options.location?.coordinate {
                let mapSide = min(size.width, size.height) * 0.36
                if let map = MapOutlineRenderer.image(for: coordinate, sidePx: mapSide, zoom: options.mapZoom) {
                    let mapTop = y + 12 * u
                    map.draw(in: CGRect(x: startX(mapSide), y: mapTop, width: mapSide, height: mapSide))
                    y = mapTop + mapSide   // コメントを地図の下に置く
                }
            }

            // コメント(地図の下)。改行ごとに 1 行ずつ描く(最大 10 行)。
            // 行数が多いほどフォントを縮小(1行=44u 〜 10行=22u)。
            if !options.comment.isEmpty {
                y += 14 * u
                let lines = options.comment.split(separator: "\n", omittingEmptySubsequences: false).prefix(10)
                let n = max(1, lines.count)
                let t = CGFloat(n - 1) / 9.0
                // 設定で選んだ雑誌風書体 + 字間。
                let cSize = (44 - t * 22) * u
                let style = options.commentFont
                let commentFont = style.uiFont(size: cSize)
                let kern = style.trackingRatio * cSize
                for line in lines {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: commentFont,
                        .foregroundColor: UIColor.white,
                        .shadow: shadow,
                        .kern: kern,
                    ]
                    let a = NSAttributedString(string: String(line), attributes: attrs)
                    a.draw(at: CGPoint(x: startX(a.size().width), y: y))
                    y += a.size().height + 8 * u
                }
            }
        }
    }

    // MARK: - ポラロイドモード: 真四角クロップ + 白フチ + 下帯キャプション

    private func composePolaroid(_ image: UIImage, options: CaptureOptions) -> UIImage {
        // 横持ち撮影は先に回してから真四角に切る(被写体が正立した正方形になる)
        let squared = centerCropSquare(rotatedImage(image, quarterTurnsCW: options.quarterTurns))
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
            // 写真領域(白フチ内の正方形 [margin, margin+side])内で、指定インセットの左右起点 x。
            func photoStartX(_ w: CGFloat, inset: CGFloat) -> CGFloat {
                options.infoOnRight ? margin + side - inset - w : margin + inset
            }

            // 写真領域上部に国境アウトライン地図を焼き込む(オフ時はスキップ)
            if options.mapEnabled, let coordinate = options.location?.coordinate {
                let mapSide = side * 0.34
                if let map = MapOutlineRenderer.image(for: coordinate, sidePx: mapSide, zoom: options.mapZoom) {
                    let origin = CGPoint(x: photoStartX(mapSide, inset: mapPad),
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
                for place in options.nearbyPlaces {
                    let attributed = NSAttributedString(string: "・" + place, attributes: [
                        .font: poiFont,
                        .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                        .shadow: poiShadow,
                    ])
                    attributed.draw(at: CGPoint(x: photoStartX(attributed.size().width, inset: mapPad), y: poiY))
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

            func draw(_ text: String, font: UIFont, color: UIColor, kern: CGFloat = 0) {
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .kern: kern,
                ])
                let x = options.infoOnRight ? margin + side - 8 * u - attributed.size().width : textX
                attributed.draw(at: CGPoint(x: x, y: y))
                y += attributed.size().height + leftLineGap
            }

            // 空港コード風の大見出し(地名の先頭3文字)
            if options.showPlaceName, let code = Self.placeCode(from: options.placeName) {
                draw(code,
                     font: .systemFont(ofSize: codeSize, weight: .heavy),
                     color: ink)
            }
            // コメント(見出しの直下)。設定の雑誌風書体で、行が増えるほど縮小(最大4行)。
            if hasComment {
                let lines = options.comment
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(4)
                let n = max(1, lines.count)
                let cSize = (32 - CGFloat(n - 1) * 5) * u
                let style = options.commentFont
                draw(lines.joined(separator: "\n"),
                     font: style.uiFont(size: cSize),
                     color: ink,
                     kern: style.trackingRatio * cSize)
            }
            if options.showPlaceName && !options.placeName.isEmpty {
                draw("📍 " + options.placeName,
                     font: .systemFont(ofSize: placeSize, weight: .bold),
                     color: ink)
            }
            // subtitle: 日時 + 座標をトグルで出し分け、両方 OFF なら行ごとスキップ
            var subtitleParts: [String] = []
            if options.showDateTime {
                subtitleParts.append(Self.displayDateFormatter.string(from: options.date))
            }
            if options.showCoordinates, let coordinate = options.location?.coordinate {
                subtitleParts.append(coordinate.displayString)
            }
            if !subtitleParts.isEmpty {
                draw(subtitleParts.joined(separator: "   "),
                     font: .monospacedSystemFont(ofSize: subtitleSize, weight: .regular),
                     color: ink.withAlphaComponent(0.65))
            }
        }
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

    /// 画像を時計回りに 90°×k 回転した UIImage を返す(向き補正用)。
    private func rotatedImage(_ image: UIImage, quarterTurnsCW k: Int) -> UIImage {
        let turns = ((k % 4) + 4) % 4
        guard turns != 0 else { return image }
        let swap = (turns % 2 == 1)
        let newSize = swap ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = image.scale
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: CGFloat(turns) * .pi / 2)
            cg.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
            image.draw(at: .zero)
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

    /// 指定アスペクト比(aspectW:aspectH = 幅:高さ)に中央クロップする。
    private func centerCrop(_ image: UIImage, aspectW: CGFloat, aspectH: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let targetRatio = aspectW / aspectH          // 幅/高さ
        let currentRatio = width / height
        var cropW = width
        var cropH = height
        if currentRatio > targetRatio {
            // 横が広すぎる → 幅を削る
            cropW = height * targetRatio
        } else {
            // 縦が高すぎる → 高さを削る
            cropH = width / targetRatio
        }
        let rect = CGRect(x: (width - cropW) / 2,
                          y: (height - cropH) / 2,
                          width: cropW, height: cropH)
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
