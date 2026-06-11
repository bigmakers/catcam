#!/usr/bin/env swift
// CATcam app icon renderer.
// Generates a 1024x1024 fully-opaque PNG using AppKit / CoreGraphics.
// Concept: retro/film-tinted camera LENS + a CAT (ears silhouette + paw mark)
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
// top cream #F2E4C8 -> mid amber #C98A4E -> bottom warm brown #6B4A2B

do {
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0xF2E4C8), color(0xD9A364), color(0x8A5C34), color(0x5E3F25)] as CFArray,
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
        colors: [color(0x000000, alpha: 0.0), color(0x3A2412, alpha: 0.0), color(0x2A1A0C, alpha: 0.38)] as CFArray,
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
    ctx.setStrokeColor(color(0xFBF1DC, alpha: 0.22))
    ctx.setLineWidth(4)
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

// MARK: - 3. Cat ears (silhouette) BEHIND/ABOVE the lens
// Drawn before the lens so the lens rests in front of the ear bases,
// reading as a round cat "head" with two pointed ears poking up.

let lensCenter = CGPoint(x: 512, y: 540)
let lc = toCG(lensCenter)
let lensOuterR: CGFloat = 268

// Warm dark fur color for the cat silhouette.
let furColor = color(0x3A2414)

do {
    // Ear is a triangle with slightly rounded tip, plus an inner pink-ish accent.
    // Pointed triangular ear with a softly rounded tip.
    func earPath(apex: CGPoint, baseL: CGPoint, baseR: CGPoint, shrink: CGFloat) -> CGPath {
        // Optionally shrink toward the centroid to build the inner ear.
        let cxp = (apex.x + baseL.x + baseR.x) / 3.0
        let cyp = (apex.y + baseL.y + baseR.y) / 3.0
        func sh(_ p: CGPoint) -> CGPoint {
            CGPoint(x: cxp + (p.x - cxp) * shrink, y: cyp + (p.y - cyp) * shrink)
        }
        let a = sh(apex), bl = sh(baseL), br = sh(baseR)
        // Round the tip: approach the apex from each side and curve across it.
        let tL = CGPoint(x: bl.x * 0.18 + a.x * 0.82, y: bl.y * 0.18 + a.y * 0.82)
        let tR = CGPoint(x: br.x * 0.18 + a.x * 0.82, y: br.y * 0.18 + a.y * 0.82)
        let path = CGMutablePath()
        path.move(to: toCG(bl))
        path.addLine(to: toCG(tL))
        path.addQuadCurve(to: toCG(tR), control: toCG(a))
        path.addLine(to: toCG(br))
        path.closeSubpath()
        return path
    }

    func drawEar(apex: CGPoint, baseL: CGPoint, baseR: CGPoint, innerColor: CGColor) {
        ctx.addPath(earPath(apex: apex, baseL: baseL, baseR: baseR, shrink: 1.0))
        ctx.setFillColor(furColor)
        ctx.fillPath()
        ctx.addPath(earPath(apex: apex, baseL: baseL, baseR: baseR, shrink: 0.52))
        ctx.setFillColor(innerColor)
        ctx.fillPath()
    }

    let innerPink = color(0xEFB199)
    // Left ear — taller, sharper, tucked behind the upper-left of the lens
    drawEar(
        apex: CGPoint(x: 282, y: 96),
        baseL: CGPoint(x: 246, y: 372),
        baseR: CGPoint(x: 446, y: 286),
        innerColor: innerPink
    )
    // Right ear
    drawEar(
        apex: CGPoint(x: 742, y: 96),
        baseL: CGPoint(x: 578, y: 286),
        baseR: CGPoint(x: 778, y: 372),
        innerColor: innerPink
    )
}

// MARK: - 4. Lens (center = lensCenter)

// Outer ring (warm cream)
ctx.setFillColor(color(0xF3E7CC))
ctx.fillEllipse(in: circle(lc, lensOuterR))

// Thin warm brass accent ring
ctx.setStrokeColor(color(0xB5793C, alpha: 0.9))
ctx.setLineWidth(8)
ctx.strokeEllipse(in: circle(lc, lensOuterR - 8))

// Barrel (dark)
ctx.setFillColor(color(0x241712))
ctx.fillEllipse(in: circle(lc, 240))

// Glass: radial gradient, warm-tinted dark glass with a teal-amber sheen
do {
    ctx.saveGState()
    ctx.addEllipse(in: circle(lc, 202))
    ctx.clip()
    let glassGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x4A6B5E), color(0x27322C), color(0x161311), color(0x0C0A09)] as CFArray,
        locations: [0.0, 0.4, 0.75, 1.0]
    )!
    let innerCenter = toCG(CGPoint(x: lensCenter.x - 70, y: lensCenter.y - 70))
    ctx.drawRadialGradient(
        glassGrad,
        startCenter: innerCenter, startRadius: 0,
        endCenter: lc, endRadius: 226,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

// Reflection: top-left translucent white ellipse for a glassy, 3D highlight
do {
    ctx.saveGState()
    let hc = toCG(CGPoint(x: lensCenter.x - 84, y: lensCenter.y - 88))
    ctx.translateBy(x: hc.x, y: hc.y)
    ctx.rotate(by: 35 * .pi / 180) // -35 deg in screen coords = +35 in CG
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.30))
    ctx.fillEllipse(in: CGRect(x: -92, y: -58, width: 184, height: 116))
    ctx.restoreGState()
}

// Inner thin ring
ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.12))
ctx.setLineWidth(10)
ctx.strokeEllipse(in: circle(lc, 148))

// Center "current location" marker: white -> warm amber -> white dot
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: circle(lc, 56))
ctx.setFillColor(color(0xF2913C))
ctx.fillEllipse(in: circle(lc, 42))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: circle(lc, 14))

// MARK: - 5. Paw print (foreground, lower-right beside the lens)

do {
    let pawCenter = CGPoint(x: 800, y: 800) // top-left coords
    let pawColor = color(0xFFFFFF, alpha: 0.95)
    ctx.setFillColor(pawColor)

    // Main pad: a rounded triangle-ish blob (use ellipse, slightly tall)
    let padW: CGFloat = 96
    let padH: CGFloat = 80
    let padC = toCG(CGPoint(x: pawCenter.x, y: pawCenter.y + 28))
    ctx.fillEllipse(in: CGRect(x: padC.x - padW / 2, y: padC.y - padH / 2, width: padW, height: padH))

    // Four toe beans arching over the pad
    let toes: [(CGFloat, CGFloat, CGFloat)] = [
        (pawCenter.x - 64, pawCenter.y - 18, 26),
        (pawCenter.x - 22, pawCenter.y - 52, 28),
        (pawCenter.x + 22, pawCenter.y - 52, 28),
        (pawCenter.x + 64, pawCenter.y - 18, 26),
    ]
    for (tx, ty, tr) in toes {
        let c = toCG(CGPoint(x: tx, y: ty))
        ctx.fillEllipse(in: CGRect(x: c.x - tr, y: c.y - tr, width: tr * 2, height: tr * 2))
    }
}

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
