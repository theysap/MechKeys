// Renders the disk image's background picture.
//
// Run with `swift Scripts/make-dmg-background.swift`. It writes
// Scripts/dmg/background.png and background@2x.png, which are then combined
// into the .tiff the window actually uses, so the picture is sharp on a
// Retina display. The result is committed, because a build machine has no
// business rendering artwork.
//
// The motif is the app's own: a graphite keyboard row hung from the top edge,
// with one key struck and the two sound arcs coming off it. Same shapes and
// the same palette as Scripts/make-icon.swift.

import AppKit

let width = 640.0
let height = 400.0

/// Where Finder is told to put the two icons. The arrow is drawn between them,
/// so these have to agree with the positions in Scripts/dmg/layout.applescript.
let appIcon = CGPoint(x: 170, y: 215)
let applicationsIcon = CGPoint(x: 470, y: 215)

// The palette, lifted from Scripts/make-icon.swift so the image and the app
// icon sitting on it are plainly the same object.
let graphiteLight = NSColor(srgbRed: 0.24, green: 0.25, blue: 0.28, alpha: 1)
let graphiteDark = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)
let keycapFace = NSColor(srgbRed: 0.99, green: 0.99, blue: 1.00, alpha: 1)
// A shade darker than the icon's keycap body: at 26 points across, 0.93
// against a 0.99 dish leaves no visible edge at all.
let keycapBody = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.85, alpha: 1)
let arcBlue = NSColor(srgbRed: 0.36, green: 0.72, blue: 1.00, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // A light field. This is not a style choice: Finder draws the icon labels
    // in a dark grey and offers no way to change it — its icon view exposes
    // text *size*, label position, a background picture and a background
    // colour, and no text colour at all. On a dark background the two names
    // are nearly invisible, so the background is light and the labels land on
    // it legibly.
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
            NSColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1),
        ]
    )?.draw(in: bounds, angle: 270)

    // Finder's coordinates run from the top, the drawing here from the bottom.
    func fromTop(_ y: Double) -> Double { height - y }

    // MARK: A keyboard row, hung from the top edge

    // Everything — keys and arcs — lives inside the graphite panel. The arcs
    // were tried hanging off its right-hand edge, which put them through the
    // top of the window and threw the whole composition off centre.
    let rowWidth = 236.0
    let rowHeight = 34.0
    let rowLeft = (width - rowWidth) / 2
    let rowBottom = height - rowHeight
    let rowMiddle = rowBottom + rowHeight / 2
    let rowRadius = 10.0

    // Square at the top so it reads as continuing past the window edge,
    // rounded at the bottom where it ends.
    let row = NSBezierPath()
    row.move(to: CGPoint(x: rowLeft, y: height))
    row.line(to: CGPoint(x: rowLeft, y: rowBottom + rowRadius))
    row.appendArc(
        withCenter: CGPoint(x: rowLeft + rowRadius, y: rowBottom + rowRadius),
        radius: rowRadius, startAngle: 180, endAngle: 270)
    row.line(to: CGPoint(x: rowLeft + rowWidth - rowRadius, y: rowBottom))
    row.appendArc(
        withCenter: CGPoint(x: rowLeft + rowWidth - rowRadius, y: rowBottom + rowRadius),
        radius: rowRadius, startAngle: 270, endAngle: 360)
    row.line(to: CGPoint(x: rowLeft + rowWidth, y: height))
    row.close()

    NSGraphicsContext.current?.saveGraphicsState()
    row.addClip()
    NSGradient(colors: [graphiteLight, graphiteDark])?.draw(in: bounds, angle: 270)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Five keycaps, the last one struck, with the sound arcs coming off it —
    // the app icon's composition, laid on its side.
    let capWidth = 26.0
    let capHeight = 18.0
    let capGap = 7.0
    let arcSpan = 22.0
    let contentWidth = capWidth * 5 + capGap * 4 + arcSpan
    let capsLeft = rowLeft + (rowWidth - contentWidth) / 2

    var struckCapRight = capsLeft
    for index in 0..<5 {
        let struck = index == 4
        let cap = NSRect(
            x: capsLeft + Double(index) * (capWidth + capGap),
            y: rowMiddle - capHeight / 2, width: capWidth, height: capHeight)

        // Body then dish, the same two shapes as the app icon's keycap. The
        // struck one is the accent colour rather than a different size: a key
        // drawn smaller than the four beside it reads as a mistake, not as
        // pressed.
        (struck ? arcBlue : keycapBody).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 4.5, yRadius: 4.5).fill()

        (struck ? arcBlue.blended(withFraction: 0.45, of: .white)! : keycapFace).setFill()
        NSBezierPath(
            roundedRect: cap.insetBy(dx: 3.5, dy: 4.5).offsetBy(dx: 0, dy: 1.5),
            xRadius: 2.5, yRadius: 2.5
        ).fill()

        if struck { struckCapRight = cap.maxX }
    }

    // The two arcs, struck from just off the pressed key's edge.
    let arcOrigin = CGPoint(x: struckCapRight + 1, y: rowMiddle)
    for (index, radius) in [10.0, 16.0].enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: arcOrigin, radius: radius, startAngle: -52, endAngle: 52)
        arc.lineWidth = index == 0 ? 3.5 : 3
        arc.lineCapStyle = .round
        arcBlue.setStroke()
        arc.stroke()
    }

    // MARK: Words

    func draw(_ text: String, font: NSFont, colour: NSColor, centreY: Double) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (width - size.width) / 2, y: centreY - size.height / 2),
            withAttributes: attributes)
    }

    draw(
        "MechKeys",
        font: .systemFont(ofSize: 25, weight: .semibold),
        colour: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), centreY: fromTop(92))
    draw(
        "Drag the app into your Applications folder",
        font: .systemFont(ofSize: 13, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.5), centreY: fromTop(120))

    // MARK: The arrow between the two icons

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
    NSColor(white: 0, alpha: 0.32).setStroke()
    arrow.stroke()

    draw(
        "First launch needs Privacy & Security → Open Anyway",
        font: .systemFont(ofSize: 11, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.42), centreY: fromTop(348))

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
