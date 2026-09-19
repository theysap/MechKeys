import AppKit

/// The menu bar glyph: the app icon's mark, redrawn for 16 points.
///
/// The icon is a keycap with two sound arcs coming off its corner. An SF
/// Symbol keyboard was standing in for it, which made the menu bar item look
/// like it belonged to a different application than the one in the Dock and
/// the disk image.
///
/// Drawn rather than shipped as a PNG so it is a readable definition, and
/// rendered as a **template** image: macOS then tints it for light and dark
/// menu bars, for the highlighted state when the popover is open, and for
/// reduced-transparency settings, none of which a fixed bitmap would follow.
enum MenuBarIconImage {

    /// Menu bar items are laid out on an 18×18 point grid, and Apple's own
    /// glyphs sit a little inside it.
    private static let size = NSSize(width: 18, height: 16)

    static let active: NSImage = make(filled: true)
    static let inactive: NSImage = make(filled: false)

    static func image(isActive: Bool) -> NSImage {
        isActive ? active : inactive
    }

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(into: context, filled: filled)
            return true
        }
        // The whole point: let AppKit colour it to match the menu bar.
        image.isTemplate = true
        return image
    }

    private static func draw(into context: CGContext, filled: Bool) {
        context.setShouldAntialias(true)

        // Black everywhere; a template image uses only the alpha channel.
        let ink = CGColor(gray: 0, alpha: 1)
        context.setStrokeColor(ink)
        context.setFillColor(ink)

        // MARK: Keycap

        // Left of centre, leaving room for the arcs. A stroke weight of 1.3
        // survives the 1× menu bar without turning to mush and still looks
        // like a line at 2×.
        let cap = CGRect(x: 1.0, y: 3.2, width: 9.0, height: 9.0)
        let capPath = CGPath(roundedRect: cap, cornerWidth: 2.4, cornerHeight: 2.4, transform: nil)

        if filled {
            context.addPath(capPath)
            context.fillPath()

            // The dish of the keycap, knocked back out of the filled shape so
            // the "on" state still reads as a keycap rather than a blob.
            context.setBlendMode(.clear)
            let face = cap.insetBy(dx: 2.5, dy: 2.5).offsetBy(dx: 0, dy: 0.6)
            context.addPath(
                CGPath(roundedRect: face, cornerWidth: 1.0, cornerHeight: 1.0, transform: nil))
            context.fillPath()
            context.setBlendMode(.normal)
        } else {
            context.setLineWidth(1.3)
            context.addPath(capPath)
            context.strokePath()
            // No inner dish line here. It was tried: at this size a line
            // across the keycap reads as a minus sign in a box, and an inset
            // rectangle reads as one box inside another. The silhouette plus
            // the arcs is what carries the icon.
        }

        // MARK: Sound arcs

        // Concentric, struck from just off the keycap's right edge, matching
        // the app icon. Two at 1×, because a third would close up into a
        // smudge at this size.
        let origin = CGPoint(x: cap.maxX - 0.6, y: cap.midY + 0.5)
        context.setLineCap(.round)

        for (index, radius) in [3.4, 5.7].enumerated() {
            context.setLineWidth(index == 0 ? 1.45 : 1.25)
            context.addArc(
                center: origin,
                radius: radius,
                startAngle: -.pi / 3.8,
                endAngle: .pi / 3.8,
                clockwise: false)
            context.strokePath()
        }
    }
}
