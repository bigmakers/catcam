#!/usr/bin/env swift
// CATcam app icon renderer.
// Generates a 1024x1024 fully-opaque PNG using AppKit / CoreGraphics.
// Concept: retro/film-tinted camera LENS + a CAT (ear silhouette + location mark)
// over a faint map of the Japan area.
// Usage: swift tools/render_app_icon.swift  (run from repo root)

import AppKit
import CoreGraphics
import Foundation

// MARK: - Configuration

let size: CGFloat = 1024
let outDir = "CATcam/Assets.xcassets/AppIcon.appiconset"
let outPath = "\(outDir)/icon1024.png"
let countriesPath = "CATcam/Resources/countries.min.json"

// MARK: - Helpers

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Context setup

guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    // noneSkipLast => opaque RGB, no alpha channel (App Store requirement)
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create CGContext")
}

// CoreGraphics is bottom-left origin. Our design coordinates in the spec are
// top-left origin (y down). Flip Y so we can use spec coords directly.
func toCG(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size - p.y) }
func toCGY(_ y: CGFloat) -> CGFloat { size - y }

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

// MARK: - 1. Background gradient (warm retro / faded film)
// A low-contrast parchment-to-caramel field keeps attention on the silhouette.

do {
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0xF5E7CE), color(0xDFC29A), color(0xBE936C), color(0x997356)] as CFArray,
        locations: [0.0, 0.42, 0.78, 1.0]
    )!
    // top of image in CG coords is y = size
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // Soft warm vignette to give it a faded-film feel and keep corners darker.
    ctx.saveGState()
    let vg = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x000000, alpha: 0.0), color(0x3A2412, alpha: 0.0), color(0x2A1A0C, alpha: 0.14)] as CFArray,
        locations: [0.0, 0.65, 1.0]
    )!
    ctx.drawRadialGradient(
        vg,
        startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
        endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.72,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

// MARK: - 2. Map layer (Japan area, Mercator) — faint, dissolves into bg

struct Country {
    let bbox: [Double] // w, s, e, n
    let polys: [[[Double]]]
}

func loadCountries() -> [Country] {
    guard let data = FileManager.default.contents(atPath: countriesPath) else {
        FileHandle.standardError.write("WARN: could not read \(countriesPath)\n".data(using: .utf8)!)
        return []
    }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj["countries"] as? [[String: Any]] else {
        FileHandle.standardError.write("WARN: bad JSON in \(countriesPath)\n".data(using: .utf8)!)
        return []
    }
    var result: [Country] = []
    for c in arr {
        guard let bbox = c["bbox"] as? [Double],
              let polys = c["polys"] as? [[[Double]]] else { continue }
        result.append(Country(bbox: bbox, polys: polys))
    }
    return result
}

// Mercator projection
func mercX(_ lon: Double) -> Double { lon * Double.pi / 180.0 }
func mercY(_ lat: Double) -> Double {
    let l = max(-85.0, min(85.0, lat))
    return log(tan(Double.pi / 4.0 + l * Double.pi / 360.0))
}

do {
    let centerLon = 138.0
    let centerLat = 37.5
    let spanLonDeg = 32.0 // longitude span shown across the square

    // Projected half-width in mercator units (based on longitude span)
    let halfX = mercX(spanLonDeg / 2.0) - mercX(0.0)
    let cx = mercX(centerLon)
    let cy = mercY(centerLat)

    // viewport bbox in lon/lat for intersection test (approximate, square fit)
    let vWest = centerLon - spanLonDeg / 2.0
    let vEast = centerLon + spanLonDeg / 2.0
    func invMercY(_ y: Double) -> Double { (2.0 * atan(exp(y)) - Double.pi / 2.0) * 180.0 / Double.pi }
    let vSouth = invMercY(cy - halfX)
    let vNorth = invMercY(cy + halfX)

    // Project a lon/lat into image (top-left origin) coordinates.
    func project(_ lon: Double, _ lat: Double) -> CGPoint {
        let px = (mercX(lon) - cx) / halfX // -1..1
        let py = (mercY(lat) - cy) / halfX // -1..1
        let imgX = size / 2.0 + CGFloat(px) * (size / 2.0)
        let imgY = size / 2.0 - CGFloat(py) * (size / 2.0) // y down
        return CGPoint(x: imgX, y: imgY)
    }

    func bboxIntersects(_ b: [Double]) -> Bool {
        let w = b[0], s = b[1], e = b[2], n = b[3]
        if e < vWest || w > vEast { return false }
        if n < vSouth || s > vNorth { return false }
        return true
    }

    let countries = loadCountries()
    // Faint warm cream lines that melt into the background.
    ctx.setStrokeColor(color(0xFBF1DC, alpha: 0.16))
    ctx.setLineWidth(2.5)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    for country in countries where bboxIntersects(country.bbox) {
        for ring in country.polys {
            var started = false
            var prevLon: Double? = nil
            for pt in ring {
                guard pt.count >= 2 else { continue }
                let lon = pt[0], lat = pt[1]
                // antimeridian break
                if let pl = prevLon, abs(lon - pl) > 180 {
                    if started { ctx.strokePath(); started = false }
                }
                let p = toCG(project(lon, lat))
                if !started {
                    ctx.move(to: p)
                    started = true
                } else {
                    ctx.addLine(to: p)
                }
                prevLon = lon
            }
            if started { ctx.strokePath() }
        }
    }
}

// MARK: - 3. Sculpted ears and optical barrel
// One large silhouette, with generous margins for the system icon mask.
let lc = toCG(CGPoint(x: 512, y: 558))

func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: stops)!
}

func linearFill(_ path: CGPath, _ colors: [CGColor], _ stops: [CGFloat],
                from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(colors, stops), start: toCG(from), end: toCG(to),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func disk(_ radius: CGFloat, _ colors: [CGColor], _ stops: [CGFloat]) {
    linearFill(CGPath(ellipseIn: circle(lc, radius), transform: nil), colors, stops,
               from: CGPoint(x: 290, y: 290), to: CGPoint(x: 730, y: 840))
}

func rim(_ radius: CGFloat, _ width: CGFloat, _ tint: CGColor) {
    ctx.setStrokeColor(tint)
    ctx.setLineWidth(width)
    ctx.strokeEllipse(in: circle(lc, radius))
}

// Curved sides and a soft apex make the ears feel integrated with the body.
func ear(_ mirrored: Bool, inner: Bool) -> CGPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        toCG(CGPoint(x: mirrored ? size - x : x, y: y))
    }
    let path = CGMutablePath()
    if inner {
        path.move(to: p(269, 351))
        path.addCurve(to: p(270, 207), control1: p(260, 301), control2: p(260, 229))
        path.addQuadCurve(to: p(286, 207), control: p(276, 195))
        path.addCurve(to: p(364, 298), control1: p(316, 232), control2: p(346, 268))
    } else {
        path.move(to: p(225, 415))
        path.addCurve(to: p(230, 167), control1: p(215, 320), control2: p(215, 221))
        path.addQuadCurve(to: p(261, 154), control: p(238, 139))
        path.addCurve(to: p(429, 312), control1: p(313, 181), control2: p(382, 254))
    }
    path.closeSubpath()
    return path
}

// A single shared shadow anchors ears and barrel without seams at their bases.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30,
              color: color(0x493524, alpha: 0.30))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
for mirrored in [false, true] {
    linearFill(ear(mirrored, inner: false),
               [color(0x6F6656), color(0x343B36), color(0x202C29)], [0, 0.5, 1],
               from: CGPoint(x: 240, y: 150), to: CGPoint(x: 390, y: 420))
    linearFill(ear(mirrored, inner: true),
               [color(0xF2C3AE), color(0xD58F80), color(0xA86F64)], [0, 0.6, 1],
               from: CGPoint(x: 270, y: 195), to: CGPoint(x: 320, y: 355))
}
disk(326, [color(0x77745F), color(0x283632)], [0, 1])
ctx.endTransparencyLayer()
ctx.restoreGState()

// Broad, readable tiers: champagne bevel, dark focusing ring, inner metal seat.
disk(322, [color(0xFFF0CF), color(0xCBB38C), color(0x8D8067), color(0xE4C59A)],
     [0, 0.35, 0.72, 1])
rim(318, 2, color(0xFFF5DC, alpha: 0.65))
disk(304, [color(0x252F2C), color(0x556058), color(0x172521)], [0, 0.5, 1])
rim(297, 2, color(0x080F0E, alpha: 0.8))

// Restrained radial machining, confined to the focusing ring.
ctx.saveGState()
ctx.setLineWidth(1.3)
for i in 0..<120 {
    let angle = CGFloat(i) * 2 * .pi / 120
    let strength = 0.07 + 0.08 * max(0, sin(angle))
    ctx.setStrokeColor(color(0xE6D6B5, alpha: strength))
    ctx.move(to: CGPoint(x: lc.x + cos(angle) * 280, y: lc.y + sin(angle) * 280))
    ctx.addLine(to: CGPoint(x: lc.x + cos(angle) * 291, y: lc.y + sin(angle) * 291))
    ctx.strokePath()
}
ctx.restoreGState()
disk(275, [color(0x0F1B19), color(0x758075), color(0x162521)], [0, 0.48, 1])
disk(264, [color(0xE6CE9F), color(0x86795A), color(0xE1B87D)], [0, 0.52, 1])
disk(255, [color(0x0A1716), color(0x263C34)], [0, 1])

// MARK: - 4. Deep glass and diagonal softbox reflections
ctx.saveGState()
ctx.addEllipse(in: circle(lc, 245))
ctx.clip()
ctx.drawRadialGradient(
    gradient([color(0x588D7D), color(0x245851), color(0x102D2D), color(0x071616)],
             [0, 0.32, 0.7, 1]),
    startCenter: toCG(CGPoint(x: 434, y: 462)), startRadius: 0,
    endCenter: lc, endRadius: 252, options: [.drawsAfterEndLocation])

// Lower reflected amber light gives the glass volume without a solid graphic blob.
ctx.setBlendMode(.screen)
ctx.drawRadialGradient(
    gradient([color(0xBBA365, alpha: 0.43), color(0x5B9879, alpha: 0.16),
              color(0x366E61, alpha: 0)], [0, 0.45, 1]),
    startCenter: toCG(CGPoint(x: 593, y: 732)), startRadius: 0,
    endCenter: toCG(CGPoint(x: 566, y: 707)), endRadius: 178,
    options: [.drawsAfterEndLocation])
ctx.setBlendMode(.normal)

// Nested internal optical surfaces remain subordinate to the outer silhouette.
for (radius, opacity): (CGFloat, CGFloat) in [(209, 0.13), (173, 0.10), (122, 0.07)] {
    rim(radius, 2, color(0x9AC4A7, alpha: opacity))
}
ctx.drawRadialGradient(
    gradient([color(0x041213, alpha: 0.72), color(0x061819, alpha: 0)], [0, 1]),
    startCenter: lc, startRadius: 35, endCenter: lc, endRadius: 161,
    options: [.drawsAfterEndLocation])

// A diagonal reflection, clipped to the glass and feathered across its width.
ctx.saveGState()
ctx.translateBy(x: lc.x - 63, y: lc.y + 99)
ctx.rotate(by: -.pi / 4)
let reflection = CGPath(roundedRect: CGRect(x: -185, y: -34, width: 370, height: 68),
                        cornerWidth: 34, cornerHeight: 34, transform: nil)
ctx.addPath(reflection)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xEFFFF0, alpha: 0), color(0xEFFFF0, alpha: 0.34),
              color(0xF5FFED, alpha: 0.55), color(0xD8F3E6, alpha: 0)],
             [0, 0.48, 0.72, 1]),
    start: CGPoint(x: 0, y: -34), end: CGPoint(x: 0, y: 34), options: [])
ctx.restoreGState()
ctx.restoreGState()
rim(244, 3, color(0xA4C5A9, alpha: 0.27))

// A small cream-and-amber location target is the sole foreground symbol.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 9,
              color: color(0x000000, alpha: 0.5))
ctx.setFillColor(color(0xF5E7C8))
ctx.fillEllipse(in: circle(lc, 33))
ctx.restoreGState()
ctx.setFillColor(color(0xC88446))
ctx.fillEllipse(in: circle(lc, 24))
ctx.setFillColor(color(0xFFF1D5))
ctx.fillEllipse(in: circle(lc, 8))

// MARK: - Export PNG (opaque)

guard let image = ctx.makeImage() else { fatalError("makeImage failed") }

// Ensure output directory exists
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create image destination")
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("Wrote \(outPath) (\(Int(size))x\(Int(size)))")
} else {
    fatalError("Could not finalize PNG")
}
