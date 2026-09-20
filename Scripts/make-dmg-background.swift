// Renders the disk image's background picture.
//
// Run with `swift Scripts/make-dmg-background.swift`. It writes
// Scripts/dmg/background.png and background@2x.png, which are then combined
// into the .tiff the window actually uses, so the picture is sharp on a
// Retina display. The result is committed, because a build machine has no
// business rendering artwork.
//
// Deliberately almost nothing: a grainy off-white field, the name, and an
// arrow between the two icons. The app icon is the only mark in the window
// and does not need competition. An earlier version hung a graphite keyboard
// row from the top edge, which was busy and fought with the icon below it.

import AppKit

let width = 640.0
let height = 400.0

/// Where Finder is told to put the two icons. The arrow is drawn between them,
/// so these have to agree with the positions in Scripts/dmg/layout.applescript.
let appIcon = CGPoint(x: 170, y: 215)
let applicationsIcon = CGPoint(x: 470, y: 215)

/// A fixed seed, so re-rendering produces a byte-identical picture. The
/// output is committed; regenerating it should not show up as a diff unless
/// something actually changed.
var randomState: UInt64 = 0x4D65_6368_4B65_7973  // "MechKeys"

/// SplitMix64. Small, deterministic, and good enough for grain.
func nextRandom() -> UInt64 {
    randomState &+= 0x9E37_79B9_7F4A_7C15
    var z = randomState
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

/// Paper grain, applied after everything else is drawn.
///
/// The noise is generated per *point* and then written across the whole
/// scale×scale block of pixels, so the texture is the same physical size at
/// 1x and 2x. Generating it per pixel instead would give the Retina version
/// grain half the size, and the two representations would not look like the
/// same image.
func addGrain(to rep: NSBitmapImageRep, scale: Int, amplitude: Int) {
    guard let data = rep.bitmapData else { return }
    let rowBytes = rep.bytesPerRow
    let samples = rep.samplesPerPixel

    randomState = 0x4D65_6368_4B65_7973

    for pointY in 0..<Int(height) {
        for pointX in 0..<Int(width) {
            // One value for all three channels: monochromatic, which reads as
            // paper. Per-channel noise reads as a broken sensor.
            let delta = Int(nextRandom() % UInt64(amplitude * 2 + 1)) - amplitude

            for dy in 0..<scale {
                let y = pointY * scale + dy
                guard y < rep.pixelsHigh else { continue }
                for dx in 0..<scale {
                    let x = pointX * scale + dx
                    guard x < rep.pixelsWide else { continue }
                    let offset = y * rowBytes + x * samples
                    for channel in 0..<3 {
                        let value = Int(data[offset + channel]) + delta
                        data[offset + channel] = UInt8(max(0, min(255, value)))
                    }
                }
            }
        }
    }
}

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Off-white, and light on purpose rather than by taste: Finder draws the
    // icon labels in a dark grey and offers no way to change it — its icon
    // view exposes text *size*, label position, a background picture and a
    // background colour, and no text colour at all. On a dark background the
    // two filenames are nearly invisible.
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.995, green: 0.995, blue: 1.000, alpha: 1),
            NSColor(srgbRed: 0.957, green: 0.957, blue: 0.969, alpha: 1),
        ]
    )?.draw(in: bounds, angle: 270)

    // Finder's coordinates run from the top, the drawing here from the bottom.
    func fromTop(_ y: Double) -> Double { height - y }

    func draw(_ text: String, font: NSFont, colour: NSColor, centreY: Double) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (width - size.width) / 2, y: centreY - size.height / 2),
            withAttributes: attributes)
    }

    draw(
        "MechKeys",
        font: .systemFont(ofSize: 26, weight: .semibold),
        colour: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1), centreY: fromTop(80))
    draw(
        "Drag the app into your Applications folder",
        font: .systemFont(ofSize: 13, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.5), centreY: fromTop(110))

    // The arrow between the two icons.
    let arrowY = fromTop(appIcon.y)
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 296, y: arrowY))
    arrow.line(to: CGPoint(x: 344, y: arrowY))
    arrow.move(to: CGPoint(x: 332, y: arrowY + 11))
    arrow.line(to: CGPoint(x: 344, y: arrowY))
    arrow.line(to: CGPoint(x: 332, y: arrowY - 11))
    NSColor(white: 0, alpha: 0.30).setStroke()
    arrow.stroke()

    draw(
        "First launch needs Privacy & Security → Open Anyway",
        font: .systemFont(ofSize: 11, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.42), centreY: fromTop(348))

    NSGraphicsContext.restoreGraphicsState()

    // After the graphics context is gone, so nothing draws over the grain.
    addGrain(to: rep, scale: scale, amplitude: 4)

    return rep
}

let directory = URL(fileURLWithPath: "Scripts/dmg", isDirectory: true)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for (rep, name) in [(render(scale: 1), "background.png"), (render(scale: 2), "background@2x.png")]
{
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(name)")
    }
    try data.write(to: directory.appendingPathComponent(name))
}

print("wrote Scripts/dmg/background.png and background@2x.png")
print("now: (cd Scripts/dmg && tiffutil -cathidpicheck background.png background@2x.png -out background.tiff)")
