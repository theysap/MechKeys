#!/usr/bin/env swift
//
// Renders MechKeys.iconset.
//
//   swift Scripts/make-icon.swift <output.iconset>
//
// Drawn with Core Graphics rather than shipped as PNGs so the icon is a
// readable definition in the repository rather than a binary blob, and so it
// can be re-rendered at any size.
//
// The mark: a single keycap, seen slightly from above, with two sound arcs
// coming off its corner. It has to survive being shown at 16 points, so it is
// one silhouette and two strokes — nothing that turns to mush when small.

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

// MARK: - Drawing

/// Apple's icon grid leaves the art inset from the canvas edge.
let artworkInset: CGFloat = 0.10

func draw(into context: CGContext, size: CGFloat) {
    let scale = size / 1024.0
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Rounded-rectangle plate, in the proportions macOS uses.
    let inset = size * artworkInset
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plateRadius = plate.width * 0.235
    let platePath = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)

    context.saveGState()
    context.addPath(platePath)
    context.clip()

    // Graphite, lit from above, like an anodised aluminium case.
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [0.24, 0.25, 0.28, 1.0])!,
            CGColor(colorSpace: space, components: [0.11, 0.11, 0.13, 1.0])!,
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    context.restoreGState()

    // Hairline highlight along the top edge: reads as a bevel at large sizes
    // and simply disappears at small ones, which is the intent.
    context.saveGState()
    context.addPath(platePath)
    context.setLineWidth(s(4))
    context.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.16])!)
    context.strokePath()
    context.restoreGState()

    // MARK: Keycap

    let capWidth = s(430)
    let capHeight = s(390)
    let capRect = CGRect(x: size * 0.5 - capWidth * 0.62,
                         y: size * 0.5 - capHeight * 0.44,
                         width: capWidth,
                         height: capHeight)
    let capRadius = capWidth * 0.20

    // Body.
    let capPath = CGPath(roundedRect: capRect, cornerWidth: capRadius, cornerHeight: capRadius, transform: nil)
    context.saveGState()
    context.addPath(capPath)
    context.setFillColor(CGColor(colorSpace: space, components: [0.93, 0.93, 0.95, 1.0])!)
    context.fillPath()
    context.restoreGState()

    // Top face, inset and slightly higher: the dish of the keycap.
    let faceInsetX = capWidth * 0.14
    let faceRect = CGRect(x: capRect.minX + faceInsetX,
                          y: capRect.minY + capHeight * 0.22,
                          width: capWidth - faceInsetX * 2,
                          height: capHeight * 0.62)
    let faceRadius = faceRect.width * 0.16
    context.saveGState()
    context.addPath(CGPath(roundedRect: faceRect, cornerWidth: faceRadius, cornerHeight: faceRadius, transform: nil))
    context.setFillColor(CGColor(colorSpace: space, components: [0.99, 0.99, 1.0, 1.0])!)
    context.fillPath()
    context.restoreGState()

    // Shadow under the front lip, so the cap sits on the plate.
    context.saveGState()
    let lip = CGRect(x: capRect.minX, y: capRect.minY, width: capRect.width, height: capHeight * 0.16)
    context.addPath(CGPath(roundedRect: lip, cornerWidth: capRadius * 0.9, cornerHeight: capRadius * 0.9, transform: nil))
    context.setFillColor(CGColor(colorSpace: space, components: [0.55, 0.56, 0.60, 0.55])!)
    context.fillPath()
    context.restoreGState()

    // MARK: Sound arcs

    // Two arcs radiating from the top-right of the cap. Concentric, struck
    // from a centre just off the keycap's corner.
    let origin = CGPoint(x: capRect.maxX + s(18), y: capRect.midY + s(40))
    context.saveGState()
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(colorSpace: space, components: [0.36, 0.72, 1.0, 1.0])!)

    for (index, radius) in [s(118), s(206)].enumerated() {
        context.setLineWidth(s(index == 0 ? 46 : 40))
        context.addArc(center: origin,
                       radius: radius,
                       startAngle: -.pi / 3.6,
                       endAngle: .pi / 3.6,
                       clockwise: false)
        context.strokePath()
    }
    context.restoreGState()
}

// MARK: - Output

func writePNG(size: CGFloat, to url: URL) throws {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "make-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create a \(pixels)px context."])
    }

    draw(into: context, size: size)

    guard let image = context.makeImage() else {
        throw NSError(domain: "make-icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not render the image."])
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
    }
    try data.write(to: url)
}

// The set of sizes `iconutil` expects, with the @2x names it insists on.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    try writePNG(size: variant.size, to: outputURL.appendingPathComponent(variant.name))
    print("  \(variant.name)")
}

print("Wrote \(variants.count) images to \(outputURL.path)")
