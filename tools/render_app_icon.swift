#!/usr/bin/env swift
// MapCam app icon renderer.
// Generates a 1024x1024 fully-opaque PNG using AppKit / CoreGraphics.
// Usage: swift tools/render_app_icon.swift  (run from repo root)

import AppKit
import CoreGraphics
import Foundation

// MARK: - Configuration

let size: CGFloat = 1024
let outDir = "MapCam/Assets.xcassets/AppIcon.appiconset"
let outPath = "\(outDir)/icon1024.png"
let countriesPath = "MapCam/Resources/countries.min.json"

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

// MARK: - 1. Background gradient (top #16243E -> bottom #060A12)

do {
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x16243E), color(0x060A12)] as CFArray,
        locations: [0.0, 1.0]
    )!
    // top of image in CG coords is y = size
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// MARK: - 2. Map layer (Japan area, Mercator)

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
    // Convert halfX (merc units) back to lat range symmetric around center.
    let vWest = centerLon - spanLonDeg / 2.0
    let vEast = centerLon + spanLonDeg / 2.0
    // For lat, invert mercator: lat = (2*atan(exp(y)) - pi/2) * 180/pi
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
        // b: w, s, e, n
        let w = b[0], s = b[1], e = b[2], n = b[3]
        if e < vWest || w > vEast { return false }
        if n < vSouth || s > vNorth { return false }
        return true
    }

    let countries = loadCountries()
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.42))
    ctx.setLineWidth(5)
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

// MARK: - 3 & 4. Dashed route + departure marker (BELOW lens, drawn first)

let routeStart = CGPoint(x: 200, y: 850) // top-left coords
let routeEnd = CGPoint(x: 512, y: 512)

do {
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.9))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 40])
    ctx.move(to: toCG(routeStart))
    ctx.addLine(to: toCG(routeEnd))
    ctx.strokePath()
    ctx.restoreGState()
}

// Departure marker: white circle + airplane symbol rotated toward route direction
do {
    let mc = toCG(routeStart)
    let r: CGFloat = 46
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: mc.x - r, y: mc.y - r, width: r * 2, height: r * 2))

    // direction angle from start to end (in top-left coords, y down)
    let dx = routeEnd.x - routeStart.x
    let dy = routeEnd.y - routeStart.y
    let angle = atan2(dy, dx) // radians, screen coords

    var drewSymbol = false
    if #available(macOS 11.0, *) {
        if let img = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .bold)
            let symImg = img.withSymbolConfiguration(config) ?? img
            let targetSize: CGFloat = 50
            var rect = CGRect(x: 0, y: 0, width: targetSize, height: targetSize)
            if let cg = symImg.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                ctx.saveGState()
                ctx.translateBy(x: mc.x, y: mc.y)
                // airplane points up (north) by default; rotate so its nose
                // follows route direction. In CG (y up) the screen-down route
                // angle must be negated.
                ctx.rotate(by: -angle - .pi / 2)
                // tint dark grey by clipping to mask and filling
                let drawRect = CGRect(x: -targetSize / 2, y: -targetSize / 2, width: targetSize, height: targetSize)
                ctx.clip(to: drawRect, mask: cg)
                ctx.setFillColor(color(0x2A2F38))
                ctx.fill(drawRect)
                ctx.restoreGState()
                drewSymbol = true
            }
        }
    }
    if !drewSymbol {
        FileHandle.standardError.write("WARN: airplane symbol unavailable, drew white circle only\n".data(using: .utf8)!)
    }
}

// MARK: - 5. Lens (center 512, 490)

let lensCenter = CGPoint(x: 512, y: 490)
let lc = toCG(lensCenter)

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

// Outer ring r=272 white #F2F5F9
ctx.setFillColor(color(0xF2F5F9))
ctx.fillEllipse(in: circle(lc, 272))

// Barrel r=244 #11161F
ctx.setFillColor(color(0x11161F))
ctx.fillEllipse(in: circle(lc, 244))

// Glass r=206 radial gradient, center offset toward (440, 420) top-left coords
do {
    ctx.saveGState()
    ctx.addEllipse(in: circle(lc, 206))
    ctx.clip()
    let glassGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x3D6CC0), color(0x16294A), color(0x0A1526)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    let innerCenter = toCG(CGPoint(x: 440, y: 420))
    ctx.drawRadialGradient(
        glassGrad,
        startCenter: innerCenter, startRadius: 0,
        endCenter: lc, endRadius: 230,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

// Reflection: top-left translucent white ellipse alpha 0.30, center (420,400), rx90 ry60, rotate -35
do {
    ctx.saveGState()
    let hc = toCG(CGPoint(x: 420, y: 400))
    ctx.translateBy(x: hc.x, y: hc.y)
    ctx.rotate(by: 35 * .pi / 180) // -35 deg in screen coords = +35 in CG
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.30))
    ctx.fillEllipse(in: CGRect(x: -90, y: -60, width: 180, height: 120))
    ctx.restoreGState()
}

// Inner thin ring r=150 white alpha 0.14 lineWidth 10
ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.14))
ctx.setLineWidth(10)
ctx.strokeEllipse(in: circle(lc, 150))

// Center marker: white r=58 -> orange #FF5A2E r=44 -> white r=14
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: circle(lc, 58))
ctx.setFillColor(color(0xFF5A2E))
ctx.fillEllipse(in: circle(lc, 44))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: circle(lc, 14))

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
